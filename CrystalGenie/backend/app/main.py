"""Crystal Genie FastAPI application."""
from __future__ import annotations

import logging
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image

from app import __version__
from app.api.routes import auth, collections, gemstones, pc_files, predictions, system, users
from app.core.config import get_settings
from app.core.errors import install_error_handlers
from app.core.logging import configure_logging, request_id_var

log = logging.getLogger("app")


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    s.validate_for_production()
    s.media_root.mkdir(parents=True, exist_ok=True)
    Image.MAX_IMAGE_PIXELS = s.max_image_pixels
    if s.load_model_on_startup:
        from app.ml.classifier import get_classifier

        clf = get_classifier()
        log.info("startup complete; model loaded=%s", clf.loaded)
    yield


def create_app() -> FastAPI:
    s = get_settings()
    configure_logging(s.log_level)
    app = FastAPI(
        title=s.app_name,
        version=__version__,
        lifespan=lifespan,
        docs_url="/docs" if not s.is_production else None,
        redoc_url=None,
        openapi_url="/openapi.json" if not s.is_production else None,
    )
    install_error_handlers(app)

    if s.cors_origin_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=s.cors_origin_list,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
        )

    max_body = s.max_upload_bytes + 1024 * 1024  # file + multipart overhead

    @app.middleware("http")
    async def request_context(request: Request, call_next):
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:16]
        token = request_id_var.set(rid)
        start = time.perf_counter()
        try:
            cl = request.headers.get("content-length")
            if cl and cl.isdigit() and int(cl) > max_body:
                return JSONResponse({"error": {"code": "payload_too_large", "message": "Request body too large.",
                                               "details": None, "request_id": rid}}, status_code=413)
            response = await call_next(request)
            response.headers["X-Request-ID"] = rid
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["Referrer-Policy"] = "no-referrer"
            log.info("request", extra={"method": request.method, "path": request.url.path, "status": response.status_code,
                                       "duration_ms": round((time.perf_counter() - start) * 1000, 1)})
            return response
        finally:
            request_id_var.reset(token)

    api = APIRouter(prefix=s.api_prefix)
    for r in (auth.router, users.router, predictions.router, gemstones.router,
              collections.saved_router, collections.favorites_router, system.router, pc_files.router):
        api.include_router(r)
    app.include_router(api)

    s.static_root.mkdir(parents=True, exist_ok=True)
    app.mount("/static", StaticFiles(directory=s.static_root), name="static")

    @app.get("/", include_in_schema=False)
    def root():
        return {"name": s.app_name, "version": __version__, "docs": "/docs", "health": f"{s.api_prefix}/health"}

    return app


app = create_app()
