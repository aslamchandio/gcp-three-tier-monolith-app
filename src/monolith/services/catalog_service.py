"""Catalog service — product reads + the upstream sync job.

Folds the standalone Go catalog-service into the monolith: the same FakeStore
feed is fetched and upserted into the products table, on a schedule and on
startup. Reads (list/get/categories) are served from the local table.
"""

from __future__ import annotations

import logging

import httpx

from ..config import Settings
from ..domain.models import Product, Rating
from ..repositories.product_repository import ProductRepository

logger = logging.getLogger("monolith.catalog")

# Deterministic, illustrative banner discounts (mirrors the original Go service).
_DISCOUNT_BUCKETS = [0, 0, 10, 15, 20, 25, 30, 40]


def _pseudo_discount(product_id: int) -> int:
    return _DISCOUNT_BUCKETS[product_id % len(_DISCOUNT_BUCKETS)]


class CatalogService:
    """Request-scoped read API over the local product catalog."""

    def __init__(self, repo: ProductRepository) -> None:
        self._repo = repo

    async def list_products(self, category: str | None = None) -> list[Product]:
        return await self._repo.list(category)

    async def get_product(self, product_id: int) -> Product | None:
        return await self._repo.get(product_id)

    async def categories(self) -> list[str]:
        return await self._repo.categories()


async def fetch_upstream_products(settings: Settings) -> list[Product]:
    """Fetch the product feed from the upstream API (reached via Cloud NAT)."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(settings.fakestore_url)
        resp.raise_for_status()
        raw = resp.json()

    products: list[Product] = []
    for item in raw:
        pid = int(item["id"])
        rating = item.get("rating") or {}
        products.append(
            Product(
                id=pid,
                title=item.get("title", ""),
                price=float(item.get("price", 0) or 0),
                description=item.get("description", "") or "",
                category=item.get("category", "") or "",
                image=item.get("image", "") or "",
                discount=_pseudo_discount(pid),
                rating=Rating(rate=float(rating.get("rate", 0) or 0), count=int(rating.get("count", 0) or 0)),
            )
        )
    return products


async def sync_catalog(db, settings: Settings) -> int:
    """Fetch the upstream feed and upsert it into the products table.

    Opens its own session because it runs outside the request lifecycle (startup
    task / scheduled loop / admin endpoint). Idempotent.
    """
    products = await fetch_upstream_products(settings)
    async with db.sessionmaker() as session:
        repo = ProductRepository(session)
        n = await repo.upsert_many(products)
        await session.commit()
    logger.info("catalog_synced", extra={"products": n})
    return n
