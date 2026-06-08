"""Cart repository — per-session cart lines in Postgres (was Redis)."""

from __future__ import annotations

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db_models import CartItemRow
from ..domain.models import Cart, CartItem


def _to_domain_item(row: CartItemRow) -> CartItem:
    return CartItem(
        product_id=row.product_id,
        title=row.title,
        price=float(row.price),
        quantity=row.quantity,
        image=row.image or "",
    )


class CartRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_cart(self, session_id: str) -> Cart:
        stmt = select(CartItemRow).where(CartItemRow.session_id == session_id).order_by(CartItemRow.id)
        rows = (await self._session.execute(stmt)).scalars().all()
        return Cart(session_id=session_id, items=[_to_domain_item(r) for r in rows])

    async def _find_row(self, session_id: str, product_id: int) -> CartItemRow | None:
        stmt = select(CartItemRow).where(
            CartItemRow.session_id == session_id, CartItemRow.product_id == product_id
        )
        return (await self._session.execute(stmt)).scalars().first()

    async def add_or_increment(self, session_id: str, item: CartItem) -> None:
        existing = await self._find_row(session_id, item.product_id)
        if existing:
            existing.quantity += item.quantity
        else:
            self._session.add(
                CartItemRow(
                    session_id=session_id,
                    product_id=item.product_id,
                    title=item.title,
                    image=item.image,
                    price=item.price,
                    quantity=item.quantity,
                )
            )

    async def remove(self, session_id: str, product_id: int) -> None:
        await self._session.execute(
            delete(CartItemRow).where(
                CartItemRow.session_id == session_id, CartItemRow.product_id == product_id
            )
        )

    async def clear(self, session_id: str) -> None:
        await self._session.execute(delete(CartItemRow).where(CartItemRow.session_id == session_id))
