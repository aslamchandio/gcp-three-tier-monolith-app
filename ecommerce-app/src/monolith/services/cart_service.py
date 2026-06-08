"""Cart service — folds the Java/Redis cart-service into the monolith.

Cart lines are self-contained (title/image/price captured at add time) by looking
the product up in the local catalog, exactly as the original service did via an
HTTP call to catalog-service.
"""

from __future__ import annotations

from ..domain.models import Cart, CartItem
from ..errors import NotFoundError, ValidationError
from ..repositories.cart_repository import CartRepository
from ..repositories.product_repository import ProductRepository


class CartService:
    def __init__(self, cart_repo: CartRepository, product_repo: ProductRepository) -> None:
        self._cart = cart_repo
        self._products = product_repo

    async def get(self, session_id: str) -> Cart:
        return await self._cart.get_cart(session_id)

    async def add_item(self, session_id: str, product_id: int, quantity: int = 1) -> Cart:
        if quantity < 1:
            raise ValidationError("quantity must be at least 1")
        product = await self._products.get(product_id)
        if product is None:
            raise NotFoundError(f"product not found: {product_id}")
        await self._cart.add_or_increment(
            session_id,
            CartItem(
                product_id=product.id,
                title=product.title,
                price=product.price,
                quantity=quantity,
                image=product.image,
            ),
        )
        return await self._cart.get_cart(session_id)

    async def remove_item(self, session_id: str, product_id: int) -> Cart:
        await self._cart.remove(session_id, product_id)
        return await self._cart.get_cart(session_id)

    async def clear(self, session_id: str) -> None:
        await self._cart.clear(session_id)
