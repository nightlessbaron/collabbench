"""Legacy key-value storage client. Deprecated: it is being removed in favour of storex (docs/MIGRATION.md)."""

_DATA = {}  # key -> (value, ttl_seconds or None)


def get(key, default=None):
    return _DATA[key][0] if key in _DATA else default


def put(key, value, ttl=None):
    """Store a value. ttl is in seconds (None: never expires)."""
    _DATA[key] = (value, ttl)


def scan(prefix):
    """Every (key, value) under prefix, sorted by key."""
    return [(k, v[0]) for k, v in sorted(_DATA.items()) if k.startswith(prefix)]


def delete(key):
    """Delete a key. True if it existed."""
    return _DATA.pop(key, None) is not None


def incr(key, by=1):
    """Add `by` to an integer (missing counts as 0) and return the new value."""
    value, ttl = _DATA.get(key, (0, None))
    _DATA[key] = (value + by, ttl)
    return value + by
