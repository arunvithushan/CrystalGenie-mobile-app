"""Application settings loaded from environment variables / backend/.env."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8", extra="ignore", case_sensitive=False
    )

    app_name: str = "Crystal Genie API"
    app_env: str = "development"
    debug: bool = False
    log_level: str = "INFO"
    api_prefix: str = "/api"

    database_url: str = "postgresql+psycopg://crystal:crystal_dev_password@localhost:5432/crystal_genie"
    test_database_url: str = ""

    jwt_secret: str = Field(default="dev-insecure-secret-change-me", min_length=16)
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    password_reset_minutes: int = 20
    password_reset_max_attempts: int = 5
    expose_reset_code_in_response: bool = False

    cors_origins: str = ""

    media_root: Path = BACKEND_DIR / "var" / "media"
    static_root: Path = BACKEND_DIR / "static"
    outbox_dir: Path = BACKEND_DIR / "var" / "outbox"
    max_upload_mb: float = 10
    max_image_pixels: int = 40_000_000
    min_image_side: int = 64

    model_dir: Path = BACKEND_DIR.parent / "models"
    model_file: str = "gemstone_model.keras"
    confidence_threshold: str = ""  # empty -> use model_metadata.json
    load_model_on_startup: bool = True

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = "Crystal Genie <no-reply@crystalgenie.local>"
    smtp_starttls: bool = True

    # "Browse this computer" in the app (development only). Read-only, image files only, and by default
    # only for requests from this PC itself (the Android emulator reaches it as 127.0.0.1).
    pc_browse_enabled: bool = False
    pc_browse_roots: str = ""  # ';'-separated folders/drives; empty = your user folder + every other drive (D:\, E:\ ...)
    pc_browse_allow_lan: bool = False  # true = also allow a phone on your Wi-Fi (any signed-in account on the LAN)

    @field_validator("media_root", "static_root", "outbox_dir", "model_dir", mode="after")
    @classmethod
    def _absolute(cls, v: Path) -> Path:
        return v if v.is_absolute() else (BACKEND_DIR / v).resolve()

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def max_upload_bytes(self) -> int:
        return int(self.max_upload_mb * 1024 * 1024)

    @property
    def threshold_override(self) -> float | None:
        try:
            return float(self.confidence_threshold) if self.confidence_threshold.strip() else None
        except ValueError:
            return None

    @property
    def reset_code_exposed(self) -> bool:
        return self.expose_reset_code_in_response and not self.is_production

    def validate_for_production(self) -> None:
        if self.is_production:
            if self.pc_browse_enabled:
                raise RuntimeError("PC_BROWSE_ENABLED must be false in production")
            if self.jwt_secret.startswith(("dev-", "change-me")) or len(self.jwt_secret) < 32:
                raise RuntimeError("JWT_SECRET must be a long random value in production")
            if self.debug:
                raise RuntimeError("DEBUG must be false in production")


@lru_cache
def get_settings() -> Settings:
    return Settings()
