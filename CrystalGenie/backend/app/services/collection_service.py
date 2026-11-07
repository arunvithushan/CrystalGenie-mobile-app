"""Saved crystals ('My Finds') and favourites — always scoped to the current user."""
from __future__ import annotations

import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import NotFound
from app.models import Favorite, Gemstone, Prediction, SavedCrystal, User
from app.services import gemstone_service, prediction_service


# ----------------------------------------------------------------------------- saved
def list_saved(db: Session, user: User, page: int, page_size: int, q: str | None = None):
    stmt = select(SavedCrystal).join(Prediction, SavedCrystal.prediction_id == Prediction.id).where(SavedCrystal.user_id == user.id)
    if q:
        like = f"%{q.strip().lower().replace(' ', '_')}%"
        like2 = f"%{q.strip().lower()}%"
        stmt = stmt.outerjoin(Gemstone, Prediction.gemstone_id == Gemstone.id).where(
            or_(func.lower(Prediction.predicted_class).like(like), func.lower(Gemstone.name).like(like2))
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = list(db.scalars(stmt.order_by(SavedCrystal.created_at.desc(), SavedCrystal.id)
                           .offset((page - 1) * page_size).limit(page_size)).unique())
    return rows, int(total)


def save_prediction(db: Session, user: User, prediction_id: uuid.UUID, note: str | None) -> tuple[SavedCrystal, bool]:
    prediction_service.get_owned(db, user, prediction_id)  # 404 if not the user's prediction
    existing = db.scalar(select(SavedCrystal).where(SavedCrystal.user_id == user.id, SavedCrystal.prediction_id == prediction_id))
    if existing:
        return existing, False
    s = SavedCrystal(user_id=user.id, prediction_id=prediction_id, note=note)
    db.add(s)
    try:
        db.commit()
    except IntegrityError:  # concurrent double-tap
        db.rollback()
        return db.scalar(select(SavedCrystal).where(SavedCrystal.user_id == user.id, SavedCrystal.prediction_id == prediction_id)), False
    db.refresh(s)
    return s, True


def delete_saved(db: Session, user: User, saved_id: uuid.UUID) -> None:
    s = db.get(SavedCrystal, saved_id)
    if s is None or s.user_id != user.id:
        raise NotFound("Saved crystal")
    db.delete(s)
    db.commit()


# ----------------------------------------------------------------------------- favorites
def list_favorites(db: Session, user: User, page: int, page_size: int, q: str | None = None):
    stmt = select(Favorite).join(Gemstone, Favorite.gemstone_id == Gemstone.id).where(Favorite.user_id == user.id)
    if q:
        stmt = stmt.where(func.lower(Gemstone.name).like(f"%{q.strip().lower()}%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = list(db.scalars(stmt.order_by(Favorite.created_at.desc(), Favorite.id)
                           .offset((page - 1) * page_size).limit(page_size)).unique())
    return rows, int(total)


def add_favorite(db: Session, user: User, gemstone_id: uuid.UUID) -> tuple[Favorite, bool]:
    gemstone_service.get_gemstone(db, gemstone_id)
    existing = db.scalar(select(Favorite).where(Favorite.user_id == user.id, Favorite.gemstone_id == gemstone_id))
    if existing:
        return existing, False
    f = Favorite(user_id=user.id, gemstone_id=gemstone_id)
    db.add(f)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return db.scalar(select(Favorite).where(Favorite.user_id == user.id, Favorite.gemstone_id == gemstone_id)), False
    db.refresh(f)
    return f, True


def delete_favorite(db: Session, user: User, favorite_or_gem_id: uuid.UUID) -> None:
    """Accepts either the favourite id or the gemstone id (convenient for toggle buttons)."""
    f = db.get(Favorite, favorite_or_gem_id)
    if f is None or f.user_id != user.id:
        f = db.scalar(select(Favorite).where(Favorite.user_id == user.id, Favorite.gemstone_id == favorite_or_gem_id))
    if f is None:
        raise NotFound("Favorite")
    db.delete(f)
    db.commit()
