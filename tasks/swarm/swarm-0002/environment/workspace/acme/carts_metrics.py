"""Carts metrics: named counters."""

from legacy import storage

PREFIX = "count/carts/"


def bump(metric, by=1):
    """Add `by` to the counter and return its new value."""
    return storage.incr(PREFIX + metric, by)


def read(metric):
    return storage.get(PREFIX + metric, 0)
