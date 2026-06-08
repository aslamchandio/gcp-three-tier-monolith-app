"""Alembic environment — async, configured from the application's settings.

Migrations are run as a SEPARATE command (`alembic upgrade head`), never on app
startup. The DB URL is derived from the same environment variables the app uses.
"""

from __future__ import annotations

import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from monolith.config import get_settings
from monolith.db import asyncpg_connect_args, make_url
from monolith.db_models import Base

config = context.config
target_metadata = Base.metadata


def _url() -> str:
    return make_url(get_settings()).render_as_string(hide_password=False)


def run_migrations_offline() -> None:
    context.configure(
        url=_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def _do_run_migrations(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    settings = get_settings()
    engine = create_async_engine(make_url(settings), connect_args=asyncpg_connect_args(settings))
    async with engine.connect() as connection:
        await connection.run_sync(_do_run_migrations)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
