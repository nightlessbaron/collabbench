"""storex: the new key-value store client. See docs/MIGRATION.md."""

from dataclasses import dataclass
from datetime import timedelta


class Missing(KeyError):
    """The key does not exist."""


@dataclass(frozen=True)
class Record:
    key: str
    value: object
    ttl: timedelta | None


@dataclass(frozen=True)
class Page:
    items: list
    next_cursor: str | None  # None on the last page


class Store:
    PAGE_LIMIT = 50

    def __init__(self):
        self._data = {}

    def fetch(self, key):
        """The Record for key; raises Missing if there is none."""
        if key not in self._data:
            raise Missing(key)
        value, ttl = self._data[key]
        return Record(key, value, ttl)

    def put(self, key, value, *, ttl=None):
        """Store a value. ttl is a datetime.timedelta, keyword-only (None: never expires)."""
        if ttl is not None and not isinstance(ttl, timedelta):
            raise TypeError("ttl must be a datetime.timedelta or None")
        self._data[key] = (value, ttl)

    def scan(self, prefix, *, cursor=None, limit=PAGE_LIMIT):
        """One page (at most `limit` Records) under prefix, in key order, after `cursor`."""
        keys = sorted(k for k in self._data if k.startswith(prefix) and (cursor is None or k > cursor))
        chunk = keys[:limit]
        return Page([Record(k, *self._data[k]) for k in chunk], chunk[-1] if len(keys) > limit else None)

    def remove(self, key):
        """Delete key; raises Missing if there is none."""
        if key not in self._data:
            raise Missing(key)
        del self._data[key]

    def add(self, key, by=1):
        """Add `by` to a counter (missing counts as 0) and return the new value."""
        value, ttl = self._data.get(key, (0, None))
        self._data[key] = (value + by, ttl)
        return value + by

    def ttl_of(self, key):
        return self.fetch(key).ttl

    def clear(self):
        self._data.clear()


store = Store()
