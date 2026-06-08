"""JSON API — the former microservice REST surface, now in one process.

Catalog, cart, checkout, and orders endpoints under /api. The shopping session is
identified by the same ``ecom_sid`` cookie the storefront uses.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import JSONResponse

from ..domain.models import Cart, Order, Product, Shipping
from ..errors import NotFoundError
from ..services.cart_service import CartService
from ..services.catalog_service import CatalogService, sync_catalog
from ..services.checkout_service import CheckoutService
from .dependencies import (
    get_cart_service,
    get_catalog_service,
    get_checkout_service,
    get_order_repository,
)
from .schemas import (
    AddItemIn,
    CartItemOut,
    CartOut,
    CheckoutIn,
    OrderItemOut,
    OrderOut,
    ProductOut,
    RatingOut,
    SyncResult,
)
from .session import get_or_create_session

router = APIRouter(prefix="/api", tags=["api"])


def _product_out(p: Product) -> ProductOut:
    return ProductOut(
        id=p.id, title=p.title, price=p.price, description=p.description,
        category=p.category, image=p.image, discount=p.discount,
        rating=RatingOut(rate=p.rating.rate, count=p.rating.count),
    )


def _cart_out(c: Cart) -> CartOut:
    return CartOut(
        session_id=c.session_id,
        items=[
            CartItemOut(
                product_id=i.product_id, title=i.title, image=i.image,
                price=i.price, quantity=i.quantity, line_total=i.line_total,
            )
            for i in c.items
        ],
        total=c.total,
        count=c.count,
    )


def _order_out(o: Order) -> OrderOut:
    return OrderOut(
        id=o.id, session_id=o.session_id, total=o.total, status=o.status,
        items=[
            OrderItemOut(product_id=i.product_id, title=i.title, image=i.image, price=i.price, quantity=i.quantity)
            for i in o.items
        ],
    )


# --- Catalog ------------------------------------------------------------------
@router.get("/products", response_model=list[ProductOut])
async def list_products(category: str | None = None, svc: CatalogService = Depends(get_catalog_service)):
    return [_product_out(p) for p in await svc.list_products(category)]


@router.get("/products/{product_id}", response_model=ProductOut)
async def get_product(product_id: int, svc: CatalogService = Depends(get_catalog_service)):
    product = await svc.get_product(product_id)
    if product is None:
        raise NotFoundError(f"product not found: {product_id}")
    return _product_out(product)


@router.get("/categories", response_model=list[str])
async def list_categories(svc: CatalogService = Depends(get_catalog_service)):
    return await svc.categories()


# --- Cart ---------------------------------------------------------------------
@router.get("/cart", response_model=CartOut)
async def get_cart(request: Request, response: Response, svc: CartService = Depends(get_cart_service)):
    sid = get_or_create_session(request, response)
    return _cart_out(await svc.get(sid))


@router.post("/cart/items", response_model=CartOut)
async def add_to_cart(
    body: AddItemIn, request: Request, response: Response, svc: CartService = Depends(get_cart_service)
):
    sid = get_or_create_session(request, response)
    return _cart_out(await svc.add_item(sid, body.product_id, body.quantity))


@router.delete("/cart/items/{product_id}", response_model=CartOut)
async def remove_from_cart(
    product_id: int, request: Request, response: Response, svc: CartService = Depends(get_cart_service)
):
    sid = get_or_create_session(request, response)
    return _cart_out(await svc.remove_item(sid, product_id))


@router.delete("/cart", status_code=204)
async def clear_cart(request: Request, response: Response, svc: CartService = Depends(get_cart_service)):
    sid = get_or_create_session(request, response)
    await svc.clear(sid)
    return Response(status_code=204)


# --- Checkout / Orders --------------------------------------------------------
@router.post("/checkout", response_model=OrderOut, status_code=201)
async def checkout(
    body: CheckoutIn, request: Request, response: Response, svc: CheckoutService = Depends(get_checkout_service)
):
    sid = get_or_create_session(request, response)
    s = body.shipping
    order = await svc.checkout(
        sid, Shipping(name=s.name, address=s.address, city=s.city, postal=s.postal, country=s.country)
    )
    return _order_out(order)


@router.get("/orders", response_model=list[OrderOut])
async def list_orders(request: Request, response: Response, repo=Depends(get_order_repository)):
    sid = get_or_create_session(request, response)
    return [_order_out(o) for o in await repo.list_by_session(sid)]


@router.get("/orders/{order_id}", response_model=OrderOut)
async def get_order(order_id: int, repo=Depends(get_order_repository)):
    order = await repo.get(order_id)
    if order is None:
        raise NotFoundError(f"order not found: {order_id}")
    return _order_out(order)


# --- Admin --------------------------------------------------------------------
@router.post("/admin/sync", response_model=SyncResult)
async def trigger_sync(request: Request) -> JSONResponse:
    """Manually trigger a catalog sync from the upstream feed."""
    n = await sync_catalog(request.app.state.db, request.app.state.settings)
    return JSONResponse(status_code=200, content={"status": "ok", "products": n})
