from __future__ import annotations

import uuid

from fastapi import APIRouter, File, Query, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse

from app.api.deps import DB, ClassifierDep, CurrentUser, OptionalUser, PagingDep
from app.api.routes.users import read_limited
from app.schemas import Message, Page, PredictionOut
from app.services import gemstone_service, prediction_service, serializers

router = APIRouter(tags=["predictions"])


@router.post("/predict", response_model=PredictionOut, status_code=status.HTTP_201_CREATED)
async def predict(db: DB, classifier: ClassifierDep, user: OptionalUser, file: UploadFile = File(...)):
    """Identify the gemstone in an uploaded photo using the trained model.

    Authenticated requests are stored in the user's history (`id` is set); anonymous requests are not.
    """
    data = await read_limited(file)
    return await run_in_threadpool(prediction_service.run_prediction, db, classifier, user, data, file.content_type)


@router.get("/predictions", response_model=Page[PredictionOut])
def list_predictions(db: DB, user: CurrentUser, paging: PagingDep, uncertain: bool | None = Query(None)):
    rows, total = prediction_service.list_predictions(db, user, paging.page, paging.page_size, uncertain)
    gem_by_class = gemstone_service.gems_by_class(db)
    fav = gemstone_service.favorite_ids(db, user.id)
    saved = prediction_service.saved_map(db, user, [p.id for p in rows])
    items = [serializers.prediction_out(p, gem_by_class, fav, saved.get(p.id)) for p in rows]
    return Page(items=items, total=total, page=paging.page, page_size=paging.page_size,
                has_more=paging.page * paging.page_size < total)


@router.get("/predictions/{prediction_id}", response_model=PredictionOut)
def get_prediction(prediction_id: uuid.UUID, db: DB, user: CurrentUser):
    p = prediction_service.get_owned(db, user, prediction_id)
    saved = prediction_service.saved_map(db, user, [p.id])
    return serializers.prediction_out(p, gemstone_service.gems_by_class(db), gemstone_service.favorite_ids(db, user.id),
                                      saved.get(p.id))


@router.get("/predictions/{prediction_id}/image", response_class=FileResponse,
            responses={200: {"content": {"image/jpeg": {}}}})
def prediction_image(prediction_id: uuid.UUID, db: DB, user: CurrentUser):
    p = prediction_service.get_owned(db, user, prediction_id)
    return FileResponse(prediction_service.ensure_image(p), media_type="image/jpeg",
                        headers={"Cache-Control": "private, max-age=604800, immutable"})


@router.delete("/predictions/{prediction_id}", response_model=Message)
def delete_prediction(prediction_id: uuid.UUID, db: DB, user: CurrentUser):
    prediction_service.delete_prediction(db, user, prediction_id)
    return Message(message="Prediction deleted.")
