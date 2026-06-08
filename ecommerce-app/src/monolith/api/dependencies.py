"""FastAPI dependency wiring: request -> AsyncSession -> repositories -> services.

The DB session is opened per-request, committed on success, rolled back on error.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from ..repositories.cart_repository import CartRepository
from ..repositories.order_repository import OrderRepository
from ..repositories.product_repository import ProductRepository
from ..services.cart_service import CartService
from ..services.catalog_service import CatalogService
from ..services.checkout_service import CheckoutService


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    db = request.app.state.db
    async with db.sessionmaker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


def get_catalog_service(session: AsyncSession = Depends(get_session)) -> CatalogService:
    return CatalogService(ProductRepository(session))


def get_cart_service(session: AsyncSession = Depends(get_session)) -> CartService:
    return CartService(CartRepository(session), ProductRepository(session))


def get_checkout_service(session: AsyncSession = Depends(get_session)) -> CheckoutService:
    return CheckoutService(CartRepository(session), OrderRepository(session))


def get_order_repository(session: AsyncSession = Depends(get_session)) -> OrderRepository:
    return OrderRepository(session)
