from __future__ import annotations

import logging

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core import security
from app.core.config import get_settings
from app.core.errors import AppError, Conflict
from app.ml.preprocessing import ImageValidationError, decode_upload, to_storage_jpeg
from app.models import User, UserSettings
from app.schemas import SettingsUpdate, UserUpdate
from app.services import storage

log = logging.getLogger("app.users")


def update_profile(db: Session, user: User, data: UserUpdate) -> User:
    if data.full_name is not None:
        user.full_name = data.full_name
    if data.email is not None:
        email = data.email.strip().lower()
        if email != user.email:
            taken = db.scalar(select(User.id).where(func.lower(User.email) == email, User.id != user.id))
            if taken:
                raise Conflict("An account with this e-mail already exists.", code="email_taken")
            user.email = email
    user.updated_at = security.utcnow()
    db.commit()
    db.refresh(user)
    return user


def update_avatar(db: Session, user: User, data: bytes, content_type: str | None) -> User:
    s = get_settings()
    try:
        decoded = decode_upload(data, content_type, max_bytes=s.max_upload_bytes, max_pixels=s.max_image_pixels, min_side=32)
    except ImageValidationError as e:
        status = 413 if e.code in ("file_too_large", "image_too_large") else 415 if e.code == "unsupported_type" else 400
        raise AppError(status, e.code, e.message) from None
    # square-crop avatars to 512px
    img = decoded.image
    side = min(img.size)
    left, top = (img.width - side) // 2, (img.height - side) // 2
    img = img.crop((left, top, left + side, top + side))
    old = user.avatar_path
    user.avatar_path = storage.save_bytes("avatars", user.id, to_storage_jpeg(img, max_side=512, quality=90))
    user.updated_at = security.utcnow()
    db.commit()
    db.refresh(user)
    storage.delete(old)
    return user


def get_settings_row(db: Session, user: User) -> UserSettings:
    row = db.get(UserSettings, user.id)
    if row is None:
        row = UserSettings(user_id=user.id)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


def update_settings(db: Session, user: User, data: SettingsUpdate) -> UserSettings:
    row = get_settings_row(db, user)
    for k, v in data.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(row, k, v)
    row.updated_at = security.utcnow()
    db.commit()
    db.refresh(row)
    return row


def delete_account(db: Session, user: User, password: str) -> None:
    if not security.verify_password(password, user.password_hash):
        raise AppError(400, "invalid_password", "Password is incorrect.")
    uid = user.id
    db.delete(user)  # FK ON DELETE CASCADE removes tokens, settings, predictions, saved, favourites
    db.commit()
    storage.delete_user_media(uid)
    log.info("account deleted", extra={"event": "account_deleted", "user_id": str(uid)})
