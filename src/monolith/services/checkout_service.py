"""Checkout service — folds the Node checkout-service orchestration into one call.

Original flow (3 network hops): fetch cart -> create order -> clear cart. Here it
is a single in-process transaction across the cart and order repositories.
"""

from __future__ import annotations

from ..domain.models import Order, OrderItem, Shipping
from ..errors import ValidationError
from ..repositories.cart_repository import CartRepository
from ..repositories.order_repository import OrderRepository


class CheckoutService:
    def __init__(self, cart_repo: CartRepository, order_repo: OrderRepository) -> None:
        self._cart = cart_repo
        self._orders = order_repo

    async def checkout(self, session_id: str, shipping: Shipping) -> Order:
        if not shipping.name or not shipping.address:
            raise ValidationError("shipping name and address are required")

        cart = await self._cart.get_cart(session_id)
        if not cart.items:
            raise ValidationError("cart is empty")

        order = Order(
            id=None,
            session_id=session_id,
            total=cart.total,
            shipping=shipping,
            items=[
                OrderItem(
                    product_id=i.product_id,
                    title=i.title,
                    price=i.price,
                    quantity=i.quantity,
                    image=i.image,
                )
                for i in cart.items
            ],
        )
        created = await self._orders.create(order)
        await self._cart.clear(session_id)   # clear only after the order persists
        return created
