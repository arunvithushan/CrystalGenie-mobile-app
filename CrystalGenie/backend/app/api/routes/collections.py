from __future__ import annotations

import uuid

from fastapi import APIRouter, Query, Response, status

from app.api.deps import DB, CurrentUser, PagingDep
from app.schemas import FavoriteOut, FavoriteRequest, Message, Page, SavedOut, SaveRequest
from app.services import collection_service, gemstone_service
from app.services.serializers import favorite_out, saved_out

saved_router = APIRouter(prefix="/saved", tags=["saved crystals"])
favorites_router = APIRouter(prefix="/favorites", tags=["favorites"])


# ---------------------------------------------------------------- saved crystals (My Finds)
@saved_router.get("", response_model=Page[SavedOut])
def list_saved(db: DB, user: CurrentUser, paging: PagingDep, q: str | None = Query(None, max_length=80)):
    rows, total = collection_service.list_saved(db, user, paging.page, paging.page_size, q)
    gem_by_class = gemstone_service.gems_by_class(db)
    fav = gemstone_service.favorite_ids(db, user.id)
    return Page(items=[saved_out(s, gem_by_class, fav) for s in rows], total=total, page=paging.page,
                page_size=paging.page_size, has_more=paging.page * paging.page_size < total)


@saved_router.post("", response_model=SavedOut, status_code=status.HTTP_201_CREATED)
def save(body: SaveRequest, db: DB, user: CurrentUser, response: Response):
    s, created = collection_service.save_prediction(db, user, body.prediction_id, body.note)
    if not created:
        response.status_code = status.HTTP_200_OK
    return saved_out(s, gemstone_service.gems_by_class(db), gemstone_service.favorite_ids(db, user.id))


@saved_router.delete("/{saved_id}", response_model=Message)
def unsave(saved_id: uuid.UUID, db: DB, user: CurrentUser):
    collection_service.delete_saved(db, user, saved_id)
    return Message(message="Removed from My Finds.")


# ---------------------------------------------------------------- favorites
@favorites_router.get("", response_model=Page[FavoriteOut])
def list_favorites(db: DB, user: CurrentUser, paging: PagingDep, q: str | None = Query(None, max_length=80)):
    rows, total = collection_service.list_favorites(db, user, paging.page, paging.page_size, q)
    return Page(items=[favorite_out(f) for f in rows], total=total, page=paging.page, page_size=paging.page_size,
                has_more=paging.page * paging.page_size < total)


@favorites_router.post("", response_model=FavoriteOut, status_code=status.HTTP_201_CREATED)
def add_favorite(body: FavoriteRequest, db: DB, user: CurrentUser, response: Response):
    f, created = collection_service.add_favorite(db, user, body.gemstone_id)
    if not created:
        response.status_code = status.HTTP_200_OK
    return favorite_out(f)


@favorites_router.delete("/{favorite_id}", response_model=Message)
def remove_favorite(favorite_id: uuid.UUID, db: DB, user: CurrentUser):
    """`favorite_id` may be the favourite's id or the gemstone's id."""
    collection_service.delete_favorite(db, user, favorite_id)
    return Message(message="Removed from Favorites.")
