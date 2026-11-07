from __future__ import annotations

import uuid
from typing import Literal

from sqlalchemy import String, cast, func, or_, select
from sqlalchemy.orm import Session

from app.core.errors import NotFound
from app.models import Favorite, Gemstone


def favorite_ids(db: Session, user_id: uuid.UUID | None) -> set[uuid.UUID]:
    if user_id is None:
        return set()
    return set(db.scalars(select(Favorite.gemstone_id).where(Favorite.user_id == user_id)))


def gems_by_class(db: Session) -> dict[str, Gemstone]:
    return {g.class_name: g for g in db.scalars(select(Gemstone).where(Gemstone.class_name.is_not(None)))}


def list_gemstones(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    color: str | None = None,
    natural: bool | None = None,
    sort: Literal["name_asc", "name_desc"] = "name_asc",
    page: int = 1,
    page_size: int = 20,
) -> tuple[list[Gemstone], int]:
    stmt = select(Gemstone)
    if q:
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(or_(func.lower(Gemstone.name).like(like), func.lower(Gemstone.tagline).like(like),
                              func.lower(Gemstone.category).like(like)))
    if category:
        stmt = stmt.where(func.lower(Gemstone.category) == category.strip().lower())
    if color:
        # colors is a JSON array of lower-case colour words; a text search is portable across PG/SQLite
        stmt = stmt.where(func.lower(cast(Gemstone.colors, String)).like(f'%"{color.strip().lower()}"%'))
    if natural is not None:
        stmt = stmt.where(Gemstone.is_natural.is_(natural))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    order = func.lower(Gemstone.name).asc() if sort == "name_asc" else func.lower(Gemstone.name).desc()
    rows = list(db.scalars(stmt.order_by(order, Gemstone.id).offset((page - 1) * page_size).limit(page_size)))
    return rows, int(total)


def get_gemstone(db: Session, gem_id: uuid.UUID) -> Gemstone:
    g = db.get(Gemstone, gem_id)
    if g is None:
        raise NotFound("Gemstone")
    return g


def categories(db: Session) -> list[tuple[str, int]]:
    rows = db.execute(select(Gemstone.category, func.count()).group_by(Gemstone.category).order_by(Gemstone.category))
    return [(c, int(n)) for c, n in rows]


def colors(db: Session) -> list[str]:
    out: set[str] = set()
    for cs in db.scalars(select(Gemstone.colors)):
        out.update(c.lower() for c in (cs or []))
    return sorted(out)
