from __future__ import annotations

import uuid
from typing import Annotated

import jwt
from fastapi import Depends, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.errors import Unauthorized
from app.core.logging import request_id_var  # noqa: F401  (re-export convenience)
from app.core.security import decode_access_token
from app.database.session import get_db
from app.ml.classifier import Classifier, get_classifier
from app.models import User

bearer = HTTPBearer(auto_error=False)

DB = Annotated[Session, Depends(get_db)]


def _user_from_token(db: Session, creds: HTTPAuthorizationCredentials | None) -> User | None:
    if creds is None or creds.scheme.lower() != "bearer" or not creds.credentials:
        return None
    try:
        payload = decode_access_token(creds.credentials)
        user_id = uuid.UUID(payload["sub"])
    except jwt.ExpiredSignatureError:
        raise Unauthorized("Access token expired.", code="token_expired") from None
    except (jwt.PyJWTError, ValueError, KeyError):
        raise Unauthorized("Invalid access token.", code="invalid_token") from None
    user = db.get(User, user_id)
    if user is None or not user.is_active or user.token_version != payload.get("tv", -1):
        raise Unauthorized("Session is no longer valid. Please sign in again.", code="invalid_token")
    return user


def get_current_user(db: DB, creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]) -> User:
    user = _user_from_token(db, creds)
    if user is None:
        raise Unauthorized()
    return user


def get_optional_user(db: DB, creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]) -> User | None:
    return _user_from_token(db, creds)


CurrentUser = Annotated[User, Depends(get_current_user)]
OptionalUser = Annotated[User | None, Depends(get_optional_user)]
ClassifierDep = Annotated[Classifier, Depends(get_classifier)]


class Paging:
    def __init__(self, page: int = Query(1, ge=1, le=10_000), page_size: int = Query(20, ge=1, le=100)):
        self.page, self.page_size = page, page_size


PagingDep = Annotated[Paging, Depends()]
