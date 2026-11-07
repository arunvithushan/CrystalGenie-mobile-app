"""Consistent JSON error responses:  {"error": {"code", "message", "details"}}."""
from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import request_id_var

log = logging.getLogger("app.errors")


class AppError(Exception):
    def __init__(self, status_code: int, code: str, message: str, details: Any = None, headers: dict | None = None):
        super().__init__(message)
        self.status_code, self.code, self.message, self.details, self.headers = status_code, code, message, details, headers


class NotFound(AppError):
    def __init__(self, what: str = "Resource"):
        super().__init__(status.HTTP_404_NOT_FOUND, "not_found", f"{what} not found")


class Unauthorized(AppError):
    def __init__(self, message: str = "Authentication required", code: str = "unauthorized"):
        super().__init__(status.HTTP_401_UNAUTHORIZED, code, message, headers={"WWW-Authenticate": "Bearer"})


class Forbidden(AppError):
    def __init__(self, message: str = "Not allowed"):
        super().__init__(status.HTTP_403_FORBIDDEN, "forbidden", message)


class Conflict(AppError):
    def __init__(self, message: str, code: str = "conflict"):
        super().__init__(status.HTTP_409_CONFLICT, code, message)


class BadRequest(AppError):
    def __init__(self, message: str, code: str = "bad_request", details: Any = None):
        super().__init__(status.HTTP_400_BAD_REQUEST, code, message, details)


def _body(code: str, message: str, details: Any = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details, "request_id": request_id_var.get()}}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError):
        return JSONResponse(_body(exc.code, exc.message, exc.details), status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        details = [
            {"field": ".".join(str(p) for p in e.get("loc", []) if p not in ("body", "query", "path")), "message": e.get("msg")}
            for e in exc.errors()
        ]
        return JSONResponse(_body("validation_error", "Some fields are invalid", details), status_code=422)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException):
        code = {404: "not_found", 405: "method_not_allowed", 401: "unauthorized", 403: "forbidden",
                413: "payload_too_large"}.get(exc.status_code, "http_error")
        message = exc.detail if isinstance(exc.detail, str) else "Request failed"
        return JSONResponse(_body(code, message), status_code=exc.status_code, headers=getattr(exc, "headers", None))

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception):
        log.exception("Unhandled error: %s", type(exc).__name__)
        return JSONResponse(_body("internal_error", "Something went wrong. Please try again."), status_code=500)
