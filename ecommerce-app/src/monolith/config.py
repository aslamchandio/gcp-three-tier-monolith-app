"""Application configuration.

ALL configuration is read from environment variables — no hardcoded hosts,
ports, passwords, or connection strings. In local dev values may come from a
`.env` file; in production the VM startup script populates the environment (with
DB_PASSWORD injected from Google Secret Manager).
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Strongly-typed settings loaded from the environment.

    Field names map case-insensitively to env vars, e.g. ``db_host`` <- ``DB_HOST``.
    """

    model_config = SettingsConfigDict(
        env_file=".env",            # loaded only if present (dev convenience)
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- Server ---------------------------------------------------------------
    port: int = Field(default=8080, ge=1, le=65535, description="HTTP port; matches the MIG named port.")
    environment: str = Field(default="development", description="Deployment environment name.")
    log_level: str = Field(default="INFO", description="Root log level (DEBUG/INFO/WARNING/ERROR).")

    # --- Database (Cloud SQL PostgreSQL over PRIVATE IP) ----------------------
    db_host: str = Field(default="127.0.0.1", description="Cloud SQL PRIVATE IP (e.g. 10.77.0.2).")
    db_port: int = Field(default=5432, ge=1, le=65535)
    db_name: str = Field(default="appdb")
    db_user: str = Field(default="appuser")
    db_password: SecretStr = Field(default=SecretStr(""), description="Injected from Secret Manager at deploy time.")
    db_max_connections: int = Field(default=10, ge=1, le=200, description="Connection pool size.")
    db_ssl_mode: str = Field(
        default="require",
        description="asyncpg SSL mode: 'require' encrypts (Cloud SQL ENCRYPTED_ONLY); 'disable' for local dev.",
    )

    # --- Timeouts -------------------------------------------------------------
    request_timeout_seconds: float = Field(default=15.0, gt=0, description="Inbound request hard timeout.")
    db_command_timeout_seconds: float = Field(default=10.0, gt=0, description="Per-statement DB timeout.")

    # --- Catalog sync (replaces the standalone catalog-service sync loop) ------
    fakestore_url: str = Field(
        default="https://fakestoreapi.com/products",
        description="Upstream product feed synced into the products table (reached via Cloud NAT).",
    )
    sync_interval_hours: int = Field(default=6, ge=1, description="How often to re-sync the product catalog.")
    sync_on_startup: bool = Field(default=True, description="Run an initial catalog sync when the app boots.")

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in {"prod", "production"}


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (read the environment exactly once)."""
    return Settings()
