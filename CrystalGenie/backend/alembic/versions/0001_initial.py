"""initial schema: users, settings, tokens, gemstones, predictions, saved crystals, favorites

Revision ID: 0001_initial
Revises:
Create Date: 2026-10-14
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

JSONType = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")


def _ts(name: str, nullable: bool = False) -> sa.Column:
    return sa.Column(name, sa.DateTime(timezone=True), nullable=nullable, server_default=sa.func.now())


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("full_name", sa.String(120), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("avatar_path", sa.String(500)),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("token_version", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_login_at", sa.DateTime(timezone=True)),
        _ts("created_at"),
        _ts("updated_at"),
    )
    op.create_index("uq_users_email_lower", "users", [sa.text("lower(email)")], unique=True)

    op.create_table(
        "user_settings",
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE", name="fk_user_settings_user_id_users"),
                  primary_key=True),
        sa.Column("notifications_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("scan_tips_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("new_crystal_alerts", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("language", sa.String(10), nullable=False, server_default="en"),
        _ts("created_at"),
        _ts("updated_at"),
    )

    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE", name="fk_refresh_tokens_user_id_users"),
                  nullable=False),
        sa.Column("token_hash", sa.String(128), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column("replaced_by_id", sa.Uuid()),
        sa.Column("user_agent", sa.String(255)),
        _ts("created_at"),
        sa.UniqueConstraint("token_hash", name="uq_refresh_tokens_token_hash"),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index("ix_refresh_tokens_family_id", "refresh_tokens", ["family_id"])

    op.create_table(
        "password_reset_tokens",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(),
                  sa.ForeignKey("users.id", ondelete="CASCADE", name="fk_password_reset_tokens_user_id_users"), nullable=False),
        sa.Column("code_hash", sa.String(128), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True)),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        _ts("created_at"),
        sa.UniqueConstraint("code_hash", name="uq_password_reset_tokens_code_hash"),
    )
    op.create_index("ix_password_reset_tokens_user_id", "password_reset_tokens", ["user_id"])

    op.create_table(
        "gemstones",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("slug", sa.String(80), nullable=False),
        sa.Column("class_name", sa.String(80)),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("tagline", sa.String(200), nullable=False, server_default=""),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("category", sa.String(60), nullable=False),
        sa.Column("mineral_family", sa.String(160)),
        sa.Column("chemical_formula", sa.String(160)),
        sa.Column("hardness_min", sa.Numeric(3, 1)),
        sa.Column("hardness_max", sa.Numeric(3, 1)),
        sa.Column("colors", JSONType, nullable=False),
        sa.Column("characteristics", JSONType, nullable=False),
        sa.Column("sources", JSONType, nullable=False),
        sa.Column("traditional_meanings", sa.Text()),
        sa.Column("care_instructions", sa.Text()),
        sa.Column("is_natural", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("image_file", sa.String(200)),
        sa.Column("reference_links", JSONType, nullable=False),
        _ts("created_at"),
        _ts("updated_at"),
        sa.UniqueConstraint("slug", name="uq_gemstones_slug"),
        sa.UniqueConstraint("class_name", name="uq_gemstones_class_name"),
        sa.CheckConstraint("hardness_min IS NULL OR (hardness_min >= 1 AND hardness_min <= 10)",
                           name="ck_gemstones_hardness_min_range"),
        sa.CheckConstraint("hardness_max IS NULL OR (hardness_max >= 1 AND hardness_max <= 10)",
                           name="ck_gemstones_hardness_max_range"),
    )
    op.create_index("ix_gemstones_category", "gemstones", ["category"])
    op.create_index("ix_gemstones_name_lower", "gemstones", [sa.text("lower(name)")])

    op.create_table(
        "predictions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE", name="fk_predictions_user_id_users"),
                  nullable=False),
        sa.Column("gemstone_id", sa.Uuid(),
                  sa.ForeignKey("gemstones.id", ondelete="SET NULL", name="fk_predictions_gemstone_id_gemstones")),
        sa.Column("predicted_class", sa.String(80), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("is_uncertain", sa.Boolean(), nullable=False),
        sa.Column("threshold", sa.Float(), nullable=False),
        sa.Column("top_predictions", JSONType, nullable=False),
        sa.Column("quality_warnings", JSONType, nullable=False),
        sa.Column("image_path", sa.String(500), nullable=False),
        sa.Column("model_version", sa.String(80), nullable=False),
        sa.Column("latency_ms", sa.Float(), nullable=False),
        _ts("created_at"),
        sa.CheckConstraint("confidence >= 0 AND confidence <= 1", name="ck_predictions_confidence_range"),
    )
    op.create_index("ix_predictions_user_created", "predictions", ["user_id", "created_at"])

    op.create_table(
        "saved_crystals",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE", name="fk_saved_crystals_user_id_users"),
                  nullable=False),
        sa.Column("prediction_id", sa.Uuid(),
                  sa.ForeignKey("predictions.id", ondelete="CASCADE", name="fk_saved_crystals_prediction_id_predictions"),
                  nullable=False),
        sa.Column("note", sa.String(500)),
        _ts("created_at"),
        sa.UniqueConstraint("user_id", "prediction_id", name="uq_saved_crystals_user_prediction"),
    )
    op.create_index("ix_saved_crystals_user_created", "saved_crystals", ["user_id", "created_at"])

    op.create_table(
        "favorites",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE", name="fk_favorites_user_id_users"),
                  nullable=False),
        sa.Column("gemstone_id", sa.Uuid(),
                  sa.ForeignKey("gemstones.id", ondelete="CASCADE", name="fk_favorites_gemstone_id_gemstones"), nullable=False),
        _ts("created_at"),
        sa.UniqueConstraint("user_id", "gemstone_id", name="uq_favorites_user_gemstone"),
    )
    op.create_index("ix_favorites_user_created", "favorites", ["user_id", "created_at"])


def downgrade() -> None:
    for t in ("favorites", "saved_crystals", "predictions", "gemstones", "password_reset_tokens", "refresh_tokens",
              "user_settings", "users"):
        op.drop_table(t)
