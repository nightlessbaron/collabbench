"""Routes stock levels, one key per item."""

from legacy import storage

PREFIX = "stock/routes/"


def restock(item, qty):
    storage.put(PREFIX + item, storage.get(PREFIX + item, 0) + qty)


def total():
    return sum(qty for _, qty in storage.scan(PREFIX))


def items():
    """Item names, sorted."""
    return [key[len(PREFIX):] for key, _ in storage.scan(PREFIX)]


def low_stock(threshold=15):
    return [key[len(PREFIX):] for key, qty in storage.scan(PREFIX) if qty < threshold]
