"""Product repository — catalog reads + upsert from the sync job."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..db_models import ProductRow
from ..domain.models import Product, Rating


def _to_domain(row: ProductRow) -> Product:
    return Product(
        id=row.id,
        title=row.title,
        price=float(row.price),
        description=row.description or "",
        category=row.category or "",
        image=row.image or "",
        discount=row.discount or 0,
        rating=Rating(rate=float(row.rating_rate or 0), count=int(row.rating_count or 0)),
    )


class ProductRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def list(self, category: str | None = None) -> list[Product]:
        stmt = select(ProductRow)
        if category:
            stmt = stmt.where(ProductRow.category == category)
        stmt = stmt.order_by(ProductRow.id)
        rows = (await self._session.execute(stmt)).scalars().all()
        return [_to_domain(r) for r in rows]

    async def get(self, product_id: int) -> Product | None:
        row = await self._session.get(ProductRow, product_id)
        return _to_domain(row) if row else None

    async def categories(self) -> list[str]:
        stmt = (
            select(ProductRow.category)
            .where(ProductRow.category.is_not(None))
            .distinct()
            .order_by(ProductRow.category)
        )
        return [c for c in (await self._session.execute(stmt)).scalars().all() if c]

    async def count(self) -> int:
        from sqlalchemy import func

        return int((await self._session.execute(select(func.count(ProductRow.id)))).scalar_one())

    async def upsert_many(self, products: list[Product]) -> int:
        """Insert-or-update products by primary key (idempotent catalog sync)."""
        n = 0
        for p in products:
            stmt = pg_insert(ProductRow).values(
                id=p.id,
                title=p.title,
                price=p.price,
                description=p.description,
                category=p.category,
                image=p.image,
                discount=p.discount,
                rating_rate=p.rating.rate,
                rating_count=p.rating.count,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[ProductRow.id],
                set_={
                    "title": stmt.excluded.title,
                    "price": stmt.excluded.price,
                    "description": stmt.excluded.description,
                    "category": stmt.excluded.category,
                    "image": stmt.excluded.image,
                    "discount": stmt.excluded.discount,
                    "rating_rate": stmt.excluded.rating_rate,
                    "rating_count": stmt.excluded.rating_count,
                },
            )
            await self._session.execute(stmt)
            n += 1
        return n
