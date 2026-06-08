"""Server-rendered storefront (folds the Java/Thymeleaf ui-service into the app).

Jinja2 templates render the same Nova Store pages. The shopping session is the
``ecom_sid`` cookie; forms post back to these routes which call the in-process
services directly (no inter-service HTTP).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ..domain.models import Shipping
from ..services.cart_service import CartService
from ..services.catalog_service import CatalogService
from ..services.checkout_service import CheckoutService
from .dependencies import get_cart_service, get_catalog_service, get_checkout_service
from .session import resolve_session, set_session_cookie

router = APIRouter(tags=["storefront"], include_in_schema=False)


def _render(request: Request, template: str, sid_new: tuple[str, bool], **ctx) -> HTMLResponse:
    """Render a template, injecting common context and setting the session cookie."""
    sid, is_new = sid_new
    templates = request.app.state.templates
    ctx.setdefault("app_version", request.app.state.settings.environment)
    response = templates.TemplateResponse(request, template, ctx)
    if is_new:
        set_session_cookie(response, sid)
    return response


@router.get("/", response_class=HTMLResponse)
async def home(
    request: Request,
    category: str | None = None,
    catalog: CatalogService = Depends(get_catalog_service),
    cart_svc: CartService = Depends(get_cart_service),
):
    sid, is_new = resolve_session(request)
    products = await catalog.list_products(category)
    categories = await catalog.categories()
    cart = await cart_svc.get(sid)
    return _render(
        request, "index.html", (sid, is_new),
        products=products, categories=categories, active_category=category, cart_count=cart.count,
    )


@router.get("/product/{product_id}", response_class=HTMLResponse)
async def product_detail(
    product_id: int,
    request: Request,
    catalog: CatalogService = Depends(get_catalog_service),
    cart_svc: CartService = Depends(get_cart_service),
):
    sid, is_new = resolve_session(request)
    product = await catalog.get_product(product_id)
    if product is None:
        return RedirectResponse(url="/", status_code=303)
    cart = await cart_svc.get(sid)
    return _render(request, "product.html", (sid, is_new), product=product, cart_count=cart.count)


@router.post("/cart/add")
async def add_to_cart(
    request: Request,
    productId: int = Form(...),  # noqa: N803 - matches the existing form field name
    quantity: int = Form(1),
    cart_svc: CartService = Depends(get_cart_service),
):
    sid, is_new = resolve_session(request)
    await cart_svc.add_item(sid, productId, quantity)
    resp = RedirectResponse(url="/cart", status_code=303)
    if is_new:
        set_session_cookie(resp, sid)
    return resp


@router.get("/cart", response_class=HTMLResponse)
async def view_cart(request: Request, cart_svc: CartService = Depends(get_cart_service)):
    sid, is_new = resolve_session(request)
    cart = await cart_svc.get(sid)
    return _render(request, "cart.html", (sid, is_new), cart=cart, cart_count=cart.count)


@router.post("/cart/remove")
async def remove_from_cart(
    request: Request,
    productId: int = Form(...),  # noqa: N803
    cart_svc: CartService = Depends(get_cart_service),
):
    sid, is_new = resolve_session(request)
    await cart_svc.remove_item(sid, productId)
    resp = RedirectResponse(url="/cart", status_code=303)
    if is_new:
        set_session_cookie(resp, sid)
    return resp


@router.get("/checkout", response_class=HTMLResponse)
async def checkout_form(request: Request, cart_svc: CartService = Depends(get_cart_service)):
    sid, is_new = resolve_session(request)
    cart = await cart_svc.get(sid)
    return _render(request, "checkout.html", (sid, is_new), cart=cart, cart_count=cart.count)


@router.post("/checkout", response_class=HTMLResponse)
async def place_order(
    request: Request,
    name: str = Form(...),
    address: str = Form(...),
    city: str = Form(""),
    postal: str = Form(""),
    country: str = Form(""),
    checkout_svc: CheckoutService = Depends(get_checkout_service),
):
    sid, is_new = resolve_session(request)
    shipping = Shipping(name=name, address=address, city=city, postal=postal, country=country)
    try:
        order = await checkout_svc.checkout(sid, shipping)
        result = {"orderId": order.id, "total": f"{order.total:.2f}"}
    except Exception as exc:  # noqa: BLE001 - surface a friendly message on the page
        result = {"error": getattr(exc, "message", str(exc))}
    return _render(request, "confirmation.html", (sid, is_new), result=result, cart_count=0)
