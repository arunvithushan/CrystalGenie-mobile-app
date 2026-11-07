"""Convert ORM objects into API schemas (adds URLs and per-user flags)."""
from __future__ import annotations

import uuid

from app.models import Favorite, Gemstone, Prediction, SavedCrystal, User
from app.schemas import FavoriteOut, GemstoneDetail, GemstoneSummary, PredictionOut, SavedOut, TopPrediction, UserOut

UNLIKE_MESSAGE = (
    "Uncertain identification. This photo does not look like any of the gemstones the model was trained on — "
    "make sure a single crystal fills most of the frame on a plain background."
)
UNCERTAIN_MESSAGE = (
    "Uncertain identification. The model is not confident about this photo — "
    "try a clearer, well-lit close-up of a single stone on a plain background."
)


def uncertainty_message(is_uncertain: bool, reason: str | None) -> str | None:
    if not is_uncertain:
        return None
    return UNLIKE_MESSAGE if reason == "unlike_training_data" else UNCERTAIN_MESSAGE


def display_name(class_name: str) -> str:
    special = {"Tigers_Eye": "Tiger's Eye", "Smokey_Quartz": "Smoky Quartz"}
    return special.get(class_name, class_name.replace("_", " "))


def user_out(user: User) -> UserOut:
    avatar = None
    if user.avatar_path:
        avatar = f"/api/users/me/avatar?v={int(user.updated_at.timestamp())}"
    return UserOut(id=user.id, email=user.email, full_name=user.full_name, avatar_url=avatar, created_at=user.created_at)


def gem_image_url(g: Gemstone) -> str | None:
    return f"/static/gemstones/{g.image_file}" if g.image_file else None


def _first_sentence(text: str, limit: int = 180) -> str:
    text = " ".join((text or "").split())
    cut = text.find(". ")
    s = text[: cut + 1] if 0 < cut < limit else text[:limit]
    return s if len(s) == len(text) or s.endswith(".") else s.rstrip() + "…"


def hardness_label(g: Gemstone) -> str | None:
    if g.hardness_min is None:
        return None
    lo, hi = float(g.hardness_min), float(g.hardness_max or g.hardness_min)
    fmt = lambda v: f"{v:g}"  # noqa: E731
    return f"{fmt(lo)}" if lo == hi else f"{fmt(lo)}–{fmt(hi)}"


def gem_summary(g: Gemstone, favorite_ids: set[uuid.UUID] | None = None) -> GemstoneSummary:
    return GemstoneSummary(
        id=g.id, slug=g.slug, name=g.name, tagline=g.tagline, category=g.category,
        image_url=gem_image_url(g), short_description=_first_sentence(g.description),
        colors=list(g.colors or []), is_favorite=bool(favorite_ids and g.id in favorite_ids),
    )


def gem_detail(g: Gemstone, favorite_ids: set[uuid.UUID] | None = None) -> GemstoneDetail:
    base = gem_summary(g, favorite_ids).model_dump()
    return GemstoneDetail(
        **base,
        class_name=g.class_name, description=g.description, mineral_family=g.mineral_family,
        chemical_formula=g.chemical_formula,
        hardness_min=float(g.hardness_min) if g.hardness_min is not None else None,
        hardness_max=float(g.hardness_max) if g.hardness_max is not None else None,
        hardness_label=hardness_label(g), characteristics=dict(g.characteristics or {}),
        sources=list(g.sources or []), traditional_meanings=g.traditional_meanings,
        care_instructions=g.care_instructions, is_natural=g.is_natural, references=list(g.references or []),
    )


def prediction_out(
    p: Prediction,
    gem_by_class: dict[str, Gemstone] | None = None,
    favorite_ids: set[uuid.UUID] | None = None,
    saved_id: uuid.UUID | None = None,
) -> PredictionOut:
    gem_by_class = gem_by_class or {}
    top = [
        TopPrediction(
            class_name=t["class_name"], display_name=display_name(t["class_name"]), confidence=t["confidence"],
            gemstone_id=(gem_by_class[t["class_name"]].id if t["class_name"] in gem_by_class else None),
        )
        for t in (p.top_predictions or [])
    ]
    gem = p.gemstone or gem_by_class.get(p.predicted_class)
    return PredictionOut(
        id=p.id, predicted_class=p.predicted_class, display_name=display_name(p.predicted_class),
        confidence=p.confidence, is_uncertain=p.is_uncertain,
        uncertainty_reason=p.uncertainty_reason if p.is_uncertain else None,
        uncertainty_message=uncertainty_message(p.is_uncertain, p.uncertainty_reason),
        similarity=p.similarity,
        threshold=p.threshold,
        top_predictions=top, quality_warnings=list(p.quality_warnings or []),
        image_url=f"/api/predictions/{p.id}/image", model_version=p.model_version, latency_ms=p.latency_ms,
        created_at=p.created_at, gemstone=gem_detail(gem, favorite_ids) if gem else None,
        is_saved=saved_id is not None, saved_id=saved_id, stored=True,
    )


def saved_out(s: SavedCrystal, gem_by_class: dict[str, Gemstone], favorite_ids: set[uuid.UUID]) -> SavedOut:
    return SavedOut(id=s.id, created_at=s.created_at, note=s.note,
                    prediction=prediction_out(s.prediction, gem_by_class, favorite_ids, saved_id=s.id))


def favorite_out(f: Favorite) -> FavoriteOut:
    return FavoriteOut(id=f.id, created_at=f.created_at, gemstone=gem_detail(f.gemstone, {f.gemstone_id}))
