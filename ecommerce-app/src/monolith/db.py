"""Async database engine, connection pool, and startup connectivity handling.

Connects to Cloud SQL for PostgreSQL over its PRIVATE IP (supplied via DB_HOST).
The pool is sized from DB_MAX_CONNECTIONS. On startup we retry with exponential
backoff so a VM that boots slightly before the database is reachable does not
crash-loop.
"""

from __future__ import annotations

import asyncio
import logging
import ssl

from sqlalchemy import text
from sqlalchemy.engine import URL
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from .config import Settings

logger = logging.getLogger("monolith.db")


def make_url(settings: Settings) -> URL:
    """Build a SQLAlchemy URL. Using URL.create safely escapes special chars
    in the generated password (which may contain symbols)."""
    return URL.create(
        drivername="postgresql+asyncpg",
        username=settings.db_user,
        password=settings.db_password.get_secret_value(),
        host=settings.db_host,
        port=settings.db_port,
        database=settings.db_name,
    )


def asyncpg_connect_args(settings: Settings) -> dict[str, object]:
    """connect_args passed to asyncpg, shared by the app engine and migrations.

    ``ssl`` is an asyncpg SSL mode string; 'require' encrypts in transit without
    verifying the server certificate, which is what Cloud SQL's ENCRYPTED_ONLY
    needs when connecting over the private IP.
    """
    args: dict[str, object] = {
        "timeout": settings.db_command_timeout_seconds,
        "command_timeout": settings.db_command_timeout_seconds,
    }
    mode = (settings.db_ssl_mode or "").lower()
    if mode in ("", "disable"):
        return args
    if mode in ("allow", "prefer", "require"):
        # Encrypt in transit without verifying the server cert (matches Cloud SQL
        # ENCRYPTED_ONLY over the private IP). Passing an explicit SSLContext
        # avoids asyncpg reading a CA file from the home dir, which systemd's
        # ProtectHome=true blocks for the non-root app user.
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        args["ssl"] = ctx
    else:
        # verify-ca / verify-full: let asyncpg load the configured CA bundle.
        args["ssl"] = settings.db_ssl_mode
    return args


class Database:
    """Owns the async engine and session factory for the process lifetime."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._engine: AsyncEngine | None = None
        self._sessionmaker: async_sessionmaker[AsyncSession] | None = None

    @property
    def sessionmaker(self) -> async_sessionmaker[AsyncSession]:
        if self._sessionmaker is None:
            raise RuntimeError("Database is not connected; call connect() first.")
        return self._sessionmaker

    def _create_engine(self) -> AsyncEngine:
        s = self._settings
        return create_async_engine(
            make_url(s),
            pool_size=s.db_max_connections,
            max_overflow=0,                 # hard cap = DB_MAX_CONNECTIONS
            pool_pre_ping=True,             # drop dead connections transparently
            pool_timeout=s.db_command_timeout_seconds,
            pool_recycle=1800,
            connect_args=asyncpg_connect_args(s),
        )

    async def connect(self, *, max_attempts: int = 10, base_delay: float = 0.5) -> None:
        """Create the engine and verify connectivity with retry/backoff."""
        self._engine = self._create_engine()
        self._sessionmaker = async_sessionmaker(self._engine, expire_on_commit=False)

        for attempt in range(1, max_attempts + 1):
            try:
                await self.ping()
                logger.info("database_connected", extra={"attempt": attempt})
                return
            except Exception as exc:  # noqa: BLE001 - report and retry any driver error
                if attempt >= max_attempts:
                    logger.error(
                        "database_connect_failed",
                        extra={"attempt": attempt, "error": str(exc)},
                    )
                    raise
                delay = min(base_delay * (2 ** (attempt - 1)), 10.0)
                logger.warning(
                    "database_connect_retry",
                    extra={"attempt": attempt, "delay_seconds": round(delay, 2), "error": str(exc)},
                )
                await asyncio.sleep(delay)

    async def ping(self) -> None:
        """Lightweight liveness probe for the database (used by /readyz)."""
        if self._engine is None:
            raise RuntimeError("Database is not connected.")
        async with self._engine.connect() as conn:
            await conn.execute(text("SELECT 1"))

    async def disconnect(self) -> None:
        """Dispose the pool on graceful shutdown."""
        if self._engine is not None:
            await self._engine.dispose()
            logger.info("database_disconnected")
            self._engine = None
            self._sessionmaker = None
