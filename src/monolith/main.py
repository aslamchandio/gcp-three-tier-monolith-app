"""Application entrypoint and composition root for Nova Store.

Builds the FastAPI app, wires the database into app state, mounts the storefront
templates + static assets, installs structured request logging, an inbound
request timeout, centralized error handling, and a background catalog sync.

Run in production with:
    uvicorn monolith.main:app --host 0.0.0.0 --port ${PORT:-8080}
"""

from __future__ import annotations

import asyncio
import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from .api import routes_api, routes_health, routes_storefront
from .config import Settings, get_settings
from .db import Database
from .errors import AppError
from .logging_config import configure_logging
from .services.catalog_service import sync_catalog

logger = logging.getLogger("monolith.request")

_PKG_DIR = Path(__file__).resolve().parent
_TEMPLATES_DIR = _PKG_DIR / "templates"
_STATIC_DIR = _PKG_DIR / "static"


async def _catalog_sync_loop(app: FastAPI) -> None:
    """Initial best-effort sync, then re-sync on the configured interval."""
    settings: Settings = app.state.settings
    db: Database = app.state.db

    # Initial sync with a few retries (upstream may be briefly unreachable).
    for attempt in range(1, 6):
        try:
            await sync_catalog(db, settings)
            break
        except Exception as exc:  # noqa: BLE001 - log and retry; never crash the app
            logger.warning("catalog_sync_retry", extra={"attempt": attempt, "error": str(exc)})
            await asyncio.sleep(5 * attempt)

    interval = max(1, settings.sync_interval_hours) * 3600
    while True:
        await asyncio.sleep(interval)
        try:
            await sync_catalog(db, settings)
        except Exception as exc:  # noqa: BLE001
            logger.warning("catalog_sync_failed", extra={"error": str(exc)})


@asynccontextmanager
async def lifespan(app: FastAPI):
    db: Database = app.state.db
    await db.connect()

    sync_task: asyncio.Task | None = None
    if app.state.settings.sync_on_startup:
        sync_task = asyncio.create_task(_catalog_sync_loop(app))

    try:
        yield
    finally:
        if sync_task is not None:
            sync_task.cancel()
            try:
                await sync_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        await db.disconnect()


def _error_body(code: str, message: str) -> dict[str, dict[str, str]]:
    return {"error": {"code": code, "message": message}}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=_error_body(exc.code, exc.message))

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "validation_error", "message": "Invalid request", "details": exc.errors()}},
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(_: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_exception")
        return JSONResponse(status_code=500, content=_error_body("internal_error", "Internal server error"))


def register_request_middleware(app: FastAPI, settings: Settings) -> None:
    @app.middleware("http")
    async def log_and_timeout(request: Request, call_next):
        start = time.perf_counter()
        try:
            response = await asyncio.wait_for(call_next(request), timeout=settings.request_timeout_seconds)
        except TimeoutError:
            elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
            logger.warning(
                "request_timeout",
                extra={"method": request.method, "path": request.url.path, "latency_ms": elapsed_ms},
            )
            return JSONResponse(status_code=504, content=_error_body("timeout", "Request timed out"))

        elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
        logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "latency_ms": elapsed_ms,
            },
        )
        return response


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(title="Nova Store (FastAPI monolith)", version="1.0.0", lifespan=lifespan)
    app.state.settings = settings
    app.state.db = Database(settings)
    app.state.templates = Jinja2Templates(directory=str(_TEMPLATES_DIR))

    register_error_handlers(app)
    register_request_middleware(app, settings)

    # Static assets served at the paths the templates reference (/css, /js).
    app.mount("/css", StaticFiles(directory=str(_STATIC_DIR / "css")), name="css")
    app.mount("/js", StaticFiles(directory=str(_STATIC_DIR / "js")), name="js")

    app.include_router(routes_health.router)
    app.include_router(routes_api.router)
    app.include_router(routes_storefront.router)

    return app


app = create_app()
