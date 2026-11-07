"""Registration, login, refresh-token rotation (with reuse detection), logout and password reset."""
from __future__ import annotations

import logging
import uuid
from datetime import timedelta

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core import security
from app.core.config import get_settings
from app.core.errors import AppError, BadRequest, Conflict, Unauthorized
from app.models import PasswordResetToken, RefreshToken, User, UserSettings
from app.services import email_service

log = logging.getLogger("app.auth")


def normalize_email(email: str) -> str:
    return email.strip().lower()


def get_user_by_email(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(func.lower(User.email) == normalize_email(email)))


def register(db: Session, full_name: str, email: str, password: str) -> User:
    if get_user_by_email(db, email):
        raise Conflict("An account with this e-mail already exists.", code="email_taken")
    user = User(email=normalize_email(email), full_name=full_name, password_hash=security.hash_password(password))
    user.settings = UserSettings()
    db.add(user)
    db.commit()
    db.refresh(user)
    log.info("user registered", extra={"event": "register", "user_id": str(user.id)})
    return user


def authenticate(db: Session, email: str, password: str) -> User:
    user = get_user_by_email(db, email)
    ok = security.verify_password(password, user.password_hash if user else None)
    if not user or not ok:
        raise Unauthorized("Incorrect e-mail or password.", code="invalid_credentials")
    if not user.is_active:
        raise Unauthorized("This account is disabled.", code="account_disabled")
    if security.needs_rehash(user.password_hash):
        user.password_hash = security.hash_password(password)
    user.last_login_at = security.utcnow()
    db.commit()
    return user


def issue_tokens(db: Session, user: User, user_agent: str | None = None, family_id: uuid.UUID | None = None) -> dict:
    s = get_settings()
    access, expires_in = security.create_access_token(user.id, user.token_version)
    refresh = security.new_refresh_token()
    rt = RefreshToken(
        user_id=user.id,
        token_hash=security.hash_token(refresh),
        family_id=family_id or uuid.uuid4(),
        expires_at=security.utcnow() + timedelta(days=s.refresh_token_days),
        user_agent=(user_agent or "")[:255] or None,
    )
    db.add(rt)
    db.commit()
    return {"access_token": access, "refresh_token": refresh, "expires_in": expires_in, "_rt": rt}


def _as_aware(dt):
    from datetime import timezone

    return dt if dt is None or dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def rotate_refresh_token(db: Session, refresh_token: str, user_agent: str | None = None) -> tuple[User, dict]:
    token_hash = security.hash_token(refresh_token)
    rt = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    if rt is None:
        raise Unauthorized("Invalid refresh token.", code="invalid_refresh_token")
    now = security.utcnow()
    if rt.revoked_at is not None:
        # Reuse of a rotated/revoked token => possible theft: revoke the whole family.
        db.execute(update(RefreshToken).where(RefreshToken.family_id == rt.family_id, RefreshToken.revoked_at.is_(None))
                   .values(revoked_at=now))
        db.commit()
        log.warning("refresh token reuse detected", extra={"event": "refresh_reuse", "user_id": str(rt.user_id)})
        raise Unauthorized("Session expired. Please sign in again.", code="refresh_token_reused")
    if _as_aware(rt.expires_at) <= now:
        raise Unauthorized("Session expired. Please sign in again.", code="refresh_token_expired")
    user = db.get(User, rt.user_id)
    if user is None or not user.is_active:
        raise Unauthorized("Session expired. Please sign in again.", code="invalid_refresh_token")
    tokens = issue_tokens(db, user, user_agent, family_id=rt.family_id)
    rt.revoked_at = now
    rt.replaced_by_id = tokens["_rt"].id
    db.commit()
    return user, tokens


def logout(db: Session, user: User | None, refresh_token: str | None, all_devices: bool) -> None:
    now = security.utcnow()
    if refresh_token:
        rt = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(refresh_token)))
        if rt is not None and (user is None or rt.user_id == user.id):
            db.execute(update(RefreshToken).where(RefreshToken.family_id == rt.family_id, RefreshToken.revoked_at.is_(None))
                       .values(revoked_at=now))
    if all_devices and user is not None:
        db.execute(update(RefreshToken).where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
                   .values(revoked_at=now))
        user.token_version += 1  # invalidates outstanding access tokens
    db.commit()


def forgot_password(db: Session, email: str) -> str | None:
    """Create a reset code and e-mail it. Returns the code (caller decides whether to expose it)."""
    s = get_settings()
    user = get_user_by_email(db, email)
    if user is None or not user.is_active:
        return None
    now = security.utcnow()
    # Only one active code per user.
    db.execute(update(PasswordResetToken).where(PasswordResetToken.user_id == user.id, PasswordResetToken.used_at.is_(None))
               .values(used_at=now))
    code = security.new_reset_code()
    db.add(PasswordResetToken(user_id=user.id, code_hash=security.hash_token(f"{user.id}:{code}"),
                              expires_at=now + timedelta(minutes=s.password_reset_minutes)))
    db.commit()
    email_service.send_password_reset(user.email, user.full_name, code, s.password_reset_minutes)
    return code


def reset_password(db: Session, email: str, code: str, new_password: str) -> None:
    s = get_settings()
    generic = BadRequest("The reset code is invalid or has expired.", code="invalid_reset_code")
    user = get_user_by_email(db, email)
    if user is None:
        raise generic
    now = security.utcnow()
    token = db.scalar(
        select(PasswordResetToken)
        .where(PasswordResetToken.user_id == user.id, PasswordResetToken.used_at.is_(None))
        .order_by(PasswordResetToken.created_at.desc())
    )
    if token is None or _as_aware(token.expires_at) <= now or token.attempts >= s.password_reset_max_attempts:
        raise generic
    if token.code_hash != security.hash_token(f"{user.id}:{code}"):
        token.attempts += 1
        if token.attempts >= s.password_reset_max_attempts:
            token.used_at = now
        db.commit()
        raise generic
    token.used_at = now
    user.password_hash = security.hash_password(new_password)
    user.token_version += 1
    db.execute(update(RefreshToken).where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None)).values(revoked_at=now))
    db.commit()
    log.info("password reset", extra={"event": "password_reset", "user_id": str(user.id)})


def change_password(db: Session, user: User, current: str, new: str) -> None:
    if not security.verify_password(current, user.password_hash):
        raise AppError(400, "invalid_password", "Current password is incorrect.")
    user.password_hash = security.hash_password(new)
    user.token_version += 1
    db.execute(update(RefreshToken).where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
               .values(revoked_at=security.utcnow()))
    db.commit()
