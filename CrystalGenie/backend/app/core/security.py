"""Password hashing (Argon2id), JWT access tokens, opaque refresh tokens and reset codes."""
from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from app.core.config import get_settings

_hasher = PasswordHasher()  # Argon2id with library defaults (t=3, m=64 MiB, p=4)
# A valid hash of a random password, used to equalise timing when the e-mail does not exist.
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))

RESET_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    try:
        return _hasher.check_needs_rehash(password_hash)
    except InvalidHashError:
        return True


def create_access_token(user_id: uuid.UUID, token_version: int) -> tuple[str, int]:
    s = get_settings()
    now = utcnow()
    exp = now + timedelta(minutes=s.access_token_minutes)
    payload = {
        "sub": str(user_id),
        "type": "access",
        "tv": token_version,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "jti": uuid.uuid4().hex,
        "iss": "crystal-genie",
    }
    return jwt.encode(payload, s.jwt_secret, algorithm=s.jwt_algorithm), s.access_token_minutes * 60


def decode_access_token(token: str) -> dict:
    """Raise jwt.PyJWTError if invalid/expired/wrong type."""
    s = get_settings()
    payload = jwt.decode(
        token, s.jwt_secret, algorithms=[s.jwt_algorithm], issuer="crystal-genie",
        options={"require": ["exp", "iat", "sub", "type"]},
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return payload


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    """Deterministic SHA-256 (keyed) so tokens can be looked up but never stored in plaintext."""
    key = get_settings().jwt_secret.encode()
    return hmac.new(key, token.encode(), hashlib.sha256).hexdigest()


def new_reset_code(length: int = 8) -> str:
    return "".join(secrets.choice(RESET_CODE_ALPHABET) for _ in range(length))
