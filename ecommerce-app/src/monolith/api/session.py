"""Anonymous shopping-session cookie (mirrors the original ``ecom_sid`` cookie).

A random session id identifies a cart across requests with no login. Set
HttpOnly with a 30-day lifetime, exactly as the Java storefront did.
"""

from __future__ import annotations

import uuid

from fastapi import Request, Response

COOKIE_NAME = "ecom_sid"
MAX_AGE = 60 * 60 * 24 * 30  # 30 days


def resolve_session(request: Request) -> tuple[str, bool]:
    """Return (session_id, is_new). Caller sets the cookie when is_new is True."""
    sid = request.cookies.get(COOKIE_NAME)
    if sid:
        return sid, False
    return str(uuid.uuid4()), True


def set_session_cookie(response: Response, sid: str) -> None:
    response.set_cookie(
        key=COOKIE_NAME, value=sid, max_age=MAX_AGE, httponly=True, samesite="lax", path="/"
    )


def get_or_create_session(request: Request, response: Response) -> str:
    """Convenience for JSON routes where a Response is injected up front."""
    sid, is_new = resolve_session(request)
    if is_new:
        set_session_cookie(response, sid)
    return sid
