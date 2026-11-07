from __future__ import annotations

import uuid
from typing import Literal

from fastapi import APIRouter, Query

from app.api.deps import DB, OptionalUser, PagingDep
from app.schemas import CategoryOut, GemstoneDetail, GemstoneSummary, Page
from app.services import gemstone_service
from app.services.serializers import gem_detail, gem_summary

router = APIRouter(prefix="/gemstones", tags=["gemstones"])


def _page(db, user, paging, **filters) -> Page[GemstoneSummary]:
    rows, total = gemstone_service.list_gemstones(db, page=paging.page, page_size=paging.page_size, **filters)
    fav = gemstone_service.favorite_ids(db, user.id if user else None)
    return Page(items=[gem_summary(g, fav) for g in rows], total=total, page=paging.page,
                page_size=paging.page_size, has_more=paging.page * paging.page_size < total)


@router.get("", response_model=Page[GemstoneSummary])
def list_gemstones(
    db: DB, user: OptionalUser, paging: PagingDep,
    category: str | None = Query(None, max_length=60),
    color: str | None = Query(None, max_length=30),
    natural: bool | None = Query(None),
    sort: Literal["name_asc", "name_desc"] = "name_asc",
    q: str | None = Query(None, max_length=80),
):
    return _page(db, user, paging, q=q, category=category, color=color, natural=natural, sort=sort)


@router.get("/search", response_model=Page[GemstoneSummary])
def search_gemstones(
    db: DB, user: OptionalUser, paging: PagingDep,
    q: str = Query(..., min_length=1, max_length=80),
    category: str | None = Query(None, max_length=60),
    sort: Literal["name_asc", "name_desc"] = "name_asc",
):
    return _page(db, user, paging, q=q, category=category, sort=sort)


@router.get("/categories", response_model=list[CategoryOut])
def list_categories(db: DB):
    return [CategoryOut(name=n, count=c) for n, c in gemstone_service.categories(db)]


@router.get("/colors", response_model=list[str])
def list_colors(db: DB):
    return gemstone_service.colors(db)


@router.get("/{gemstone_id}", response_model=GemstoneDetail)
def get_gemstone(gemstone_id: uuid.UUID, db: DB, user: OptionalUser):
    g = gemstone_service.get_gemstone(db, gemstone_id)
    return gem_detail(g, gemstone_service.favorite_ids(db, user.id if user else None))
