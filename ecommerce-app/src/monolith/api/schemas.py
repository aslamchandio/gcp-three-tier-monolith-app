"""Pydantic request/response schemas for the JSON API."""

from __future__ import annotations

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str


class RatingOut(BaseModel):
    rate: float
    count: int


class ProductOut(BaseModel):
    id: int
    title: str
    price: float
    description: str = ""
    category: str = ""
    image: str = ""
    discount: int = 0
    rating: RatingOut


class CartItemOut(BaseModel):
    product_id: int
    title: str
    image: str = ""
    price: float
    quantity: int
    line_total: float


class CartOut(BaseModel):
    session_id: str
    items: list[CartItemOut]
    total: float
    count: int


class AddItemIn(BaseModel):
    product_id: int = Field(alias="productId")
    quantity: int = Field(default=1, ge=1)

    model_config = {"populate_by_name": True}


class ShippingIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    address: str = Field(min_length=4, max_length=120)
    city: str = ""
    postal: str = ""
    country: str = ""


class CheckoutIn(BaseModel):
    shipping: ShippingIn


class OrderItemOut(BaseModel):
    product_id: int
    title: str
    image: str = ""
    price: float
    quantity: int


class OrderOut(BaseModel):
    id: int
    session_id: str
    total: float
    status: str
    items: list[OrderItemOut]


class SyncResult(BaseModel):
    status: str
    products: int
