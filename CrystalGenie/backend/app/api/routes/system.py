from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter
from sqlalchemy import text

from app import __version__
from app.api.deps import DB, ClassifierDep
from app.schemas import HealthOut, ModelStatusOut

router = APIRouter(tags=["system"])


@router.get("/health", response_model=HealthOut)
def health(db: DB, classifier: ClassifierDep):
    try:
        db.execute(text("SELECT 1"))
        db_ok = "ok"
    except Exception:  # noqa: BLE001
        db_ok = "error"
    status = "ok" if db_ok == "ok" and classifier.loaded else "degraded"
    return HealthOut(status=status, version=__version__, database=db_ok, model_loaded=classifier.loaded,
                     time=datetime.now(timezone.utc))


@router.get("/model/status", response_model=ModelStatusOut)
def model_status(classifier: ClassifierDep):
    meta = classifier.metadata or {}
    return ModelStatusOut(
        loaded=classifier.loaded,
        model_version=classifier.model_version,
        architecture=meta.get("architecture"),
        num_classes=len(classifier.class_names),
        class_names=classifier.class_names,
        input_size=meta.get("input_size"),
        confidence_threshold=classifier.threshold if classifier.loaded else None,
        temperature=classifier.temperature if classifier.loaded else None,
        metrics=meta.get("metrics"),
        trained_at=meta.get("trained_at"),
        error=None if classifier.loaded else (classifier.error or "model not loaded"),
    )
