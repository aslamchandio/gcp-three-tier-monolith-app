"""Health endpoints.

- /healthz (LIVENESS): fast, must NOT depend on the database. This is what the
  load balancer health check and MIG auto-healing probe.
- /readyz (READINESS): also verifies the app can reach Cloud SQL (SELECT 1).
"""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from .schemas import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/healthz", response_model=HealthResponse)
async def healthz() -> HealthResponse:
    return HealthResponse(status="ok")


@router.get("/readyz")
async def readyz(request: Request) -> JSONResponse:
    db = request.app.state.db
    try:
        await db.ping()
    except Exception:  # noqa: BLE001 - any failure means "not ready"
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "checks": {"database": "unavailable"}},
        )
    return JSONResponse(status_code=200, content={"status": "ready", "checks": {"database": "ok"}})
