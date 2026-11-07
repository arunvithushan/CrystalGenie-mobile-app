"""SQLAlchemy ORM models. Importing this package registers every table on Base.metadata."""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, Timestamped, UUIDPk

JSONType = JSON().with_variant(JSONB(), "postgresql")


class User(UUIDPk, Timestamped, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(320), nullable=False)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    avatar_path: Mapped[str | None] = mapped_column(String(500))
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    # Incremented on password change / logout-all / delete to invalidate access tokens.
    token_version: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    settings: Mapped[UserSettings] = relationship(back_populates="user", uselist=False, cascade="all, delete-orphan", passive_deletes=True)

    __table_args__ = (Index("uq_users_email_lower", func.lower(email), unique=True),)


class UserSettings(Timestamped, Base):
    __tablename__ = "user_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    notifications_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    scan_tips_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    new_crystal_alerts: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    language: Mapped[str] = mapped_column(String(10), nullable=False, default="en", server_default="en")

    user: Mapped[User] = relationship(back_populates="settings")


class RefreshToken(UUIDPk, Base):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    user_agent: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class PasswordResetToken(UUIDPk, Base):
    __tablename__ = "password_reset_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    code_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Gemstone(UUIDPk, Timestamped, Base):
    __tablename__ = "gemstones"

    slug: Mapped[str] = mapped_column(String(80), nullable=False, unique=True)
    class_name: Mapped[str | None] = mapped_column(String(80), unique=True)  # label used by the ML model
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    tagline: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    category: Mapped[str] = mapped_column(String(60), nullable=False, index=True)  # e.g. Quartz variety, Natural glass
    mineral_family: Mapped[str | None] = mapped_column(String(160))
    chemical_formula: Mapped[str | None] = mapped_column(String(160))
    hardness_min: Mapped[float | None] = mapped_column(Numeric(3, 1))
    hardness_max: Mapped[float | None] = mapped_column(Numeric(3, 1))
    colors: Mapped[list] = mapped_column(JSONType, nullable=False, default=list)
    characteristics: Mapped[dict] = mapped_column(JSONType, nullable=False, default=dict)  # luster, transparency ...
    sources: Mapped[list] = mapped_column(JSONType, nullable=False, default=list)  # typical localities
    traditional_meanings: Mapped[str | None] = mapped_column(Text)  # cultural beliefs, labelled as such in the UI
    care_instructions: Mapped[str | None] = mapped_column(Text)
    is_natural: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
    image_file: Mapped[str | None] = mapped_column(String(200))
    references: Mapped[list] = mapped_column("reference_links", JSONType, nullable=False, default=list)

    __table_args__ = (
        CheckConstraint("hardness_min IS NULL OR (hardness_min >= 1 AND hardness_min <= 10)", name="hardness_min_range"),
        CheckConstraint("hardness_max IS NULL OR (hardness_max >= 1 AND hardness_max <= 10)", name="hardness_max_range"),
        Index("ix_gemstones_name_lower", func.lower(name)),
    )


class Prediction(UUIDPk, Base):
    __tablename__ = "predictions"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    gemstone_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("gemstones.id", ondelete="SET NULL"))
    predicted_class: Mapped[str] = mapped_column(String(80), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False)
    is_uncertain: Mapped[bool] = mapped_column(Boolean, nullable=False)
    threshold: Mapped[float] = mapped_column(Float, nullable=False)  # uncertainty threshold used at prediction time
    uncertainty_reason: Mapped[str | None] = mapped_column(String(40))  # low_confidence | unlike_training_data
    similarity: Mapped[float | None] = mapped_column(Float)  # cosine similarity to nearest class centroid
    top_predictions: Mapped[list] = mapped_column(JSONType, nullable=False, default=list)
    quality_warnings: Mapped[list] = mapped_column(JSONType, nullable=False, default=list)
    image_path: Mapped[str] = mapped_column(String(500), nullable=False)
    model_version: Mapped[str] = mapped_column(String(80), nullable=False)
    latency_ms: Mapped[float] = mapped_column(Float, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    gemstone: Mapped[Gemstone | None] = relationship(lazy="joined")

    __table_args__ = (
        Index("ix_predictions_user_created", "user_id", "created_at"),
        CheckConstraint("confidence >= 0 AND confidence <= 1", name="confidence_range"),
    )


class SavedCrystal(UUIDPk, Base):
    """'My Finds': a prediction the user chose to keep."""

    __tablename__ = "saved_crystals"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    prediction_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("predictions.id", ondelete="CASCADE"), nullable=False)
    note: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    prediction: Mapped[Prediction] = relationship(lazy="joined")

    __table_args__ = (
        UniqueConstraint("user_id", "prediction_id", name="uq_saved_crystals_user_prediction"),
        Index("ix_saved_crystals_user_created", "user_id", "created_at"),
    )


class Favorite(UUIDPk, Base):
    __tablename__ = "favorites"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    gemstone_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("gemstones.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

    gemstone: Mapped[Gemstone] = relationship(lazy="joined")

    __table_args__ = (
        UniqueConstraint("user_id", "gemstone_id", name="uq_favorites_user_gemstone"),
        Index("ix_favorites_user_created", "user_id", "created_at"),
    )


__all__ = [
    "Base", "User", "UserSettings", "RefreshToken", "PasswordResetToken",
    "Gemstone", "Prediction", "SavedCrystal", "Favorite",
]
