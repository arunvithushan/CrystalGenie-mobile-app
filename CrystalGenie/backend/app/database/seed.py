"""Seed / update the gemstone library from app/data/gemstones.json (idempotent upsert by slug).

Run:  python -m app.database.seed
"""
from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Gemstone

DATA_FILE = Path(__file__).resolve().parents[1] / "data" / "gemstones.json"
FIELDS = ("class_name", "name", "tagline", "category", "description", "mineral_family", "chemical_formula",
          "hardness_min", "hardness_max", "colors", "characteristics", "sources", "traditional_meanings",
          "care_instructions", "is_natural", "image_file", "references")


def load_seed() -> list[dict]:
    return json.loads(DATA_FILE.read_text(encoding="utf-8"))


def seed_gemstones(db: Session) -> tuple[int, int]:
    created = updated = 0
    for item in load_seed():
        g = db.scalar(select(Gemstone).where(Gemstone.slug == item["slug"]))
        if g is None:
            g = Gemstone(slug=item["slug"])
            db.add(g)
            created += 1
        else:
            updated += 1
        for f in FIELDS:
            setattr(g, f, item.get(f))
    db.commit()
    return created, updated


def main() -> None:
    from app.database.session import SessionLocal, get_engine

    get_engine()
    with SessionLocal() as db:
        c, u = seed_gemstones(db)
    print(f"Gemstones seeded: {c} created, {u} updated")


if __name__ == "__main__":
    main()
