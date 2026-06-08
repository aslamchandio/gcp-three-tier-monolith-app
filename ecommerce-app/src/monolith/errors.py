"""Domain error types, independent of HTTP.

The service layer raises these; the presentation layer maps them to HTTP status
codes and a consistent JSON envelope (see ``main.register_error_handlers``).
"""

from __future__ import annotations


class AppError(Exception):
    """Base application error."""

    status_code: int = 500
    code: str = "internal_error"

    def __init__(self, message: str = "Internal server error") -> None:
        super().__init__(message)
        self.message = message


class ValidationError(AppError):
    status_code = 422
    code = "validation_error"


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"


class ConflictError(AppError):
    status_code = 409
    code = "conflict"
