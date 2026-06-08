"""Order repository — persist and read placed orders + their items."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db_models import OrderItemRow, OrderRow
from ..domain.models import Order, OrderItem, Shipping


def _to_domain(row: OrderRow) -> Order:
    return Order(
        id=row.id,
        session_id=row.session_id,
        total=float(row.total),
        shipping=Shipping(
            name=row.shipping_name or "",
            address=row.shipping_address or "",
            city=row.shipping_city or "",
            postal=row.shipping_postal or "",
            country=row.shipping_country or "",
        ),
        items=[
            OrderItem(
                product_id=i.product_id,
                title=i.title,
                price=float(i.price),
                quantity=i.quantity,
                image=i.image or "",
            )
            for i in row.items
        ],
        status=row.status,
        created_at=row.created_at,
    )


class OrderRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(self, order: Order) -> Order:
        row = OrderRow(
            session_id=order.session_id,
            total=order.total,
            shipping_name=order.shipping.name,
            shipping_address=order.shipping.address,
            shipping_city=order.shipping.city,
            shipping_postal=order.shipping.postal,
            shipping_country=order.shipping.country,
            status=order.status,
            items=[
                OrderItemRow(
                    product_id=i.product_id,
                    title=i.title,
                    image=i.image,
                    price=i.price,
                    quantity=i.quantity,
                )
                for i in order.items
            ],
        )
        self._session.add(row)
        await self._session.flush()      # assign the order id
        await self._session.refresh(row)
        return _to_domain(row)

    async def get(self, order_id: int) -> Order | None:
        row = await self._session.get(OrderRow, order_id)
        return _to_domain(row) if row else None

    async def list_by_session(self, session_id: str) -> list[Order]:
        stmt = (
            select(OrderRow)
            .where(OrderRow.session_id == session_id)
            .order_by(OrderRow.created_at.desc())
        )
        rows = (await self._session.execute(stmt)).scalars().all()
        return [_to_domain(r) for r in rows]
