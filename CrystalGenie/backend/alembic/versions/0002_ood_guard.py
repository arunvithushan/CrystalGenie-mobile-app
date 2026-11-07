"""prediction OOD guard fields: uncertainty_reason, similarity

Revision ID: 0002_ood_guard
Revises: 0001_initial
Create Date: 2026-10-17
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0002_ood_guard"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("predictions") as batch:
        batch.add_column(sa.Column("uncertainty_reason", sa.String(40)))
        batch.add_column(sa.Column("similarity", sa.Float()))


def downgrade() -> None:
    with op.batch_alter_table("predictions") as batch:
        batch.drop_column("similarity")
        batch.drop_column("uncertainty_reason")
