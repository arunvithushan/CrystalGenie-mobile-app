"""Run the classifier on an uploaded image and persist the result for the user."""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.errors import AppError, BadRequest, NotFound
from app.ml.classifier import Classifier
from app.ml.preprocessing import ImageValidationError, decode_upload, to_storage_jpeg
from app.models import Prediction, SavedCrystal, User
from app.schemas import PredictionOut, TopPrediction
from app.services import gemstone_service, serializers, storage

log = logging.getLogger("app.predict")


def run_prediction(db: Session, classifier: Classifier, user: User | None, data: bytes, content_type: str | None,
                   store: bool = True) -> PredictionOut:
    s = get_settings()
    if not classifier.loaded:
        raise AppError(503, "model_unavailable", "The gemstone model is not available right now. Please try again later.",
                       details={"reason": "model not loaded"})
    try:
        decoded = decode_upload(data, content_type, max_bytes=s.max_upload_bytes, max_pixels=s.max_image_pixels,
                                min_side=s.min_image_side)
    except ImageValidationError as e:
        status = 413 if e.code in ("file_too_large", "image_too_large") else 415 if e.code == "unsupported_type" else 400
        raise AppError(status, e.code, e.message) from None

    result = classifier.predict(decoded.image, top_k=3)
    gem_by_class = gemstone_service.gems_by_class(db)
    fav = gemstone_service.favorite_ids(db, user.id if user else None)
    top_json = [{"class_name": t.class_name, "confidence": round(t.confidence, 6)} for t in result.top]
    best = result.best

    should_store = store and user is not None
    if should_store:
        rel = storage.save_bytes("predictions", user.id, to_storage_jpeg(decoded.image))
        gem = gem_by_class.get(best.class_name)
        p = Prediction(
            user_id=user.id, gemstone_id=gem.id if gem else None, predicted_class=best.class_name,
            confidence=round(best.confidence, 6), is_uncertain=result.is_uncertain, threshold=result.threshold,
            uncertainty_reason=result.uncertainty_reason,
            similarity=round(result.similarity, 6) if result.similarity is not None else None,
            top_predictions=top_json, quality_warnings=decoded.warnings, image_path=rel,
            model_version=result.model_version, latency_ms=result.latency_ms,
        )
        db.add(p)
        db.commit()
        db.refresh(p)
        log.info("prediction stored", extra={"event": "predict", "user_id": str(user.id)})
        return serializers.prediction_out(p, gem_by_class, fav)

    # Not stored (anonymous request)
    gem = gem_by_class.get(best.class_name)
    return PredictionOut(
        id=None, predicted_class=best.class_name, display_name=serializers.display_name(best.class_name),
        confidence=best.confidence, is_uncertain=result.is_uncertain,
        uncertainty_reason=result.uncertainty_reason,
        uncertainty_message=serializers.uncertainty_message(result.is_uncertain, result.uncertainty_reason),
        similarity=result.similarity,
        threshold=result.threshold,
        top_predictions=[TopPrediction(class_name=t.class_name, display_name=serializers.display_name(t.class_name),
                                       confidence=t.confidence,
                                       gemstone_id=gem_by_class[t.class_name].id if t.class_name in gem_by_class else None)
                         for t in result.top],
        quality_warnings=decoded.warnings, image_url=None, model_version=result.model_version,
        latency_ms=result.latency_ms, created_at=datetime.now(timezone.utc),
        gemstone=serializers.gem_detail(gem, fav) if gem else None, stored=False,
    )


def get_owned(db: Session, user: User, prediction_id: uuid.UUID) -> Prediction:
    p = db.get(Prediction, prediction_id)
    if p is None or p.user_id != user.id:  # same 404 for "not yours" to avoid leaking existence
        raise NotFound("Prediction")
    return p


def saved_map(db: Session, user: User, prediction_ids: list[uuid.UUID]) -> dict[uuid.UUID, uuid.UUID]:
    if not prediction_ids:
        return {}
    rows = db.execute(select(SavedCrystal.prediction_id, SavedCrystal.id)
                      .where(SavedCrystal.user_id == user.id, SavedCrystal.prediction_id.in_(prediction_ids)))
    return {pid: sid for pid, sid in rows}


def list_predictions(db: Session, user: User, page: int, page_size: int, uncertain: bool | None = None):
    from sqlalchemy import func

    stmt = select(Prediction).where(Prediction.user_id == user.id)
    if uncertain is not None:
        stmt = stmt.where(Prediction.is_uncertain.is_(uncertain))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = list(db.scalars(stmt.order_by(Prediction.created_at.desc(), Prediction.id).offset((page - 1) * page_size).limit(page_size)))
    return rows, int(total)


def delete_prediction(db: Session, user: User, prediction_id: uuid.UUID) -> None:
    p = get_owned(db, user, prediction_id)
    path = p.image_path
    db.delete(p)
    db.commit()
    storage.delete(path)


def ensure_image(p: Prediction):
    path = storage.resolve(p.image_path)
    if path is None:
        raise NotFound("Image")
    return path


__all__ = ["run_prediction", "get_owned", "list_predictions", "delete_prediction", "saved_map", "ensure_image", "BadRequest"]
