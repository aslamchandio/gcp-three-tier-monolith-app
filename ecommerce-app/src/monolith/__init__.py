"""Nova Store — a layered FastAPI monolith.

One process, three internal layers (api -> services -> repositories), folded from
a polyglot microservices app (catalog/cart/checkout/order/ui) into a single
deployable backed by one Cloud SQL PostgreSQL database.
"""
