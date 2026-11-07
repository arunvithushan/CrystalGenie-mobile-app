"""Pydantic request/response schemas."""
from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

T = TypeVar("T")

SUPPORTED_LANGUAGES = ("en", "si", "ta")


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
    has_more: bool


class Message(BaseModel):
    message: str


# --------------------------------------------------------------------------- auth
def _password_rules(v: str) -> str:
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters")
    if len(v) > 128:
        raise ValueError("Password must be at most 128 characters")
    if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
        raise ValueError("Password must contain letters and numbers")
    return v


def _name_rules(v: str) -> str:
    v = " ".join(v.split())
    if len(v) < 2:
        raise ValueError("Name must be at least 2 characters")
    if len(v) > 120:
        raise ValueError("Name must be at most 120 characters")
    return v


class RegisterRequest(BaseModel):
    full_name: str
    email: EmailStr
    password: str

    @field_validator("full_name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        return _name_rules(v)

    @field_validator("password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        return _password_rules(v)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


class LogoutRequest(BaseModel):
    refresh_token: str | None = Field(default=None, max_length=200)
    all_devices: bool = False


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    message: str
    dev_reset_code: str | None = None  # only in development when EXPOSE_RESET_CODE_IN_RESPONSE=true


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=12)
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        return _password_rules(v)

    @field_validator("code")
    @classmethod
    def _code(cls, v: str) -> str:
        return v.strip().upper().replace("-", "").replace(" ", "")


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        return _password_rules(v)


class UserOut(ORM):
    id: uuid.UUID
    email: str
    full_name: str
    avatar_url: str | None = None
    created_at: datetime


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: UserOut


# --------------------------------------------------------------------------- users
class UserUpdate(BaseModel):
    full_name: str | None = None
    email: EmailStr | None = None

    @field_validator("full_name")
    @classmethod
    def _n(cls, v):
        return None if v is None else _name_rules(v)


class DeleteAccountRequest(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    confirm: Literal["DELETE"]


class SettingsOut(ORM):
    notifications_enabled: bool
    scan_tips_enabled: bool
    new_crystal_alerts: bool
    language: str
    updated_at: datetime


class SettingsUpdate(BaseModel):
    notifications_enabled: bool | None = None
    scan_tips_enabled: bool | None = None
    new_crystal_alerts: bool | None = None
    language: str | None = None

    @field_validator("language")
    @classmethod
    def _lang(cls, v):
        if v is not None and v not in SUPPORTED_LANGUAGES:
            raise ValueError(f"Language must be one of {', '.join(SUPPORTED_LANGUAGES)}")
        return v


# --------------------------------------------------------------------------- gemstones
class GemstoneSummary(ORM):
    id: uuid.UUID
    slug: str
    name: str
    tagline: str
    category: str
    image_url: str | None = None
    short_description: str = ""
    colors: list[str] = []
    is_favorite: bool = False


class GemstoneDetail(GemstoneSummary):
    class_name: str | None
    description: str
    mineral_family: str | None
    chemical_formula: str | None
    hardness_min: float | None
    hardness_max: float | None
    hardness_label: str | None = None
    characteristics: dict
    sources: list[str]
    traditional_meanings: str | None
    care_instructions: str | None
    is_natural: bool
    references: list[str]


class CategoryOut(BaseModel):
    name: str
    count: int


# --------------------------------------------------------------------------- predictions
class TopPrediction(BaseModel):
    class_name: str
    display_name: str
    confidence: float
    gemstone_id: uuid.UUID | None = None


class PredictionOut(BaseModel):
    id: uuid.UUID | None
    predicted_class: str
    display_name: str
    confidence: float
    is_uncertain: bool
    uncertainty_reason: str | None = None
    uncertainty_message: str | None = None
    similarity: float | None = None
    threshold: float
    top_predictions: list[TopPrediction]
    quality_warnings: list[str] = []
    image_url: str | None = None
    model_version: str
    latency_ms: float
    created_at: datetime | None = None
    gemstone: GemstoneDetail | None = None
    is_saved: bool = False
    saved_id: uuid.UUID | None = None
    stored: bool = True


# --------------------------------------------------------------------------- saved / favorites
class SaveRequest(BaseModel):
    prediction_id: uuid.UUID
    note: str | None = Field(default=None, max_length=500)


class SavedOut(BaseModel):
    id: uuid.UUID
    created_at: datetime
    note: str | None
    prediction: PredictionOut


class FavoriteRequest(BaseModel):
    gemstone_id: uuid.UUID


class FavoriteOut(BaseModel):
    id: uuid.UUID
    created_at: datetime
    gemstone: GemstoneDetail


# --------------------------------------------------------------------------- system
class HealthOut(BaseModel):
    status: Literal["ok", "degraded"]
    version: str
    database: Literal["ok", "error"]
    model_loaded: bool
    time: datetime


class ModelStatusOut(BaseModel):
    loaded: bool
    model_version: str | None = None
    architecture: str | None = None
    num_classes: int = 0
    class_names: list[str] = []
    input_size: list[int] | None = None
    confidence_threshold: float | None = None
    temperature: float | None = None
    metrics: dict | None = None
    trained_at: str | None = None
    error: str | None = None
