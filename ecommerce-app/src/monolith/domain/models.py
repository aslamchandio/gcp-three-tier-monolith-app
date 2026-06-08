"""Framework-free domain dataclasses, shared across all layers.

No SQLAlchemy, no FastAPI — pure data. Repositories map rows to these; services
operate on them; the API serializes them.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Rating:
    rate: float = 0.0
    count: int = 0


@dataclass
class Product:
    id: int
    title: str
    price: float
    description: str = ""
    category: str = ""
    image: str = ""
    discount: int = 0
    rating: Rating = field(default_factory=Rating)


@dataclass
class CartItem:
    product_id: int
    title: str
    price: float
    quantity: int
    image: str = ""

    @property
    def line_total(self) -> float:
        return round(self.price * self.quantity, 2)


@dataclass
class Cart:
    session_id: str
    items: list[CartItem] = field(default_factory=list)

    @property
    def total(self) -> float:
        return round(sum(i.line_total for i in self.items), 2)

    @property
    def count(self) -> int:
        return sum(i.quantity for i in self.items)


@dataclass
class OrderItem:
    product_id: int
    title: str
    price: float
    quantity: int
    image: str = ""


@dataclass
class Shipping:
    name: str
    address: str
    city: str = ""
    postal: str = ""
    country: str = ""


@dataclass
class Order:
    id: int | None
    session_id: str
    total: float
    shipping: Shipping
    items: list[OrderItem] = field(default_factory=list)
    status: str = "PLACED"
    created_at: datetime | None = None
