from __future__ import annotations

from fastapi import APIRouter, Request, status

from app.api.deps import DB, CurrentUser, OptionalUser
from app.core.config import get_settings
from app.core.rate_limit import client_ip, login_limiter, sensitive_limiter
from app.schemas import (
    ChangePasswordRequest,
    ForgotPasswordRequest,
    ForgotPasswordResponse,
    LoginRequest,
    LogoutRequest,
    Message,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenPair,
)
from app.services import auth_service
from app.services.serializers import user_out

router = APIRouter(prefix="/auth", tags=["auth"])


def _pair(tokens: dict, user) -> TokenPair:
    return TokenPair(access_token=tokens["access_token"], refresh_token=tokens["refresh_token"],
                     expires_in=tokens["expires_in"], user=user_out(user))


@router.post("/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
def register(body: RegisterRequest, request: Request, db: DB):
    sensitive_limiter.hit(f"register:{client_ip(request)}")
    user = auth_service.register(db, body.full_name, body.email, body.password)
    return _pair(auth_service.issue_tokens(db, user, request.headers.get("user-agent")), user)


@router.post("/login", response_model=TokenPair)
def login(body: LoginRequest, request: Request, db: DB):
    login_limiter.hit(f"login:{client_ip(request)}:{body.email.lower()}")
    user = auth_service.authenticate(db, body.email, body.password)
    return _pair(auth_service.issue_tokens(db, user, request.headers.get("user-agent")), user)


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshRequest, request: Request, db: DB):
    login_limiter.hit(f"refresh:{client_ip(request)}")
    user, tokens = auth_service.rotate_refresh_token(db, body.refresh_token, request.headers.get("user-agent"))
    return _pair(tokens, user)


@router.post("/logout", response_model=Message)
def logout(body: LogoutRequest, db: DB, user: OptionalUser):
    auth_service.logout(db, user, body.refresh_token, body.all_devices)
    return Message(message="Signed out.")


@router.post("/forgot-password", response_model=ForgotPasswordResponse, status_code=status.HTTP_202_ACCEPTED)
def forgot_password(body: ForgotPasswordRequest, request: Request, db: DB):
    sensitive_limiter.hit(f"forgot:{client_ip(request)}")
    code = auth_service.forgot_password(db, body.email)
    # Same response whether or not the account exists (no account enumeration).
    return ForgotPasswordResponse(
        message="If an account exists for this e-mail, a reset code has been sent.",
        dev_reset_code=code if get_settings().reset_code_exposed else None,
    )


@router.post("/reset-password", response_model=Message)
def reset_password(body: ResetPasswordRequest, request: Request, db: DB):
    sensitive_limiter.hit(f"reset:{client_ip(request)}")
    auth_service.reset_password(db, body.email, body.code, body.new_password)
    return Message(message="Password updated. Please sign in with your new password.")


@router.post("/change-password", response_model=TokenPair)
def change_password(body: ChangePasswordRequest, request: Request, db: DB, user: CurrentUser):
    auth_service.change_password(db, user, body.current_password, body.new_password)
    db.refresh(user)
    return _pair(auth_service.issue_tokens(db, user, request.headers.get("user-agent")), user)
