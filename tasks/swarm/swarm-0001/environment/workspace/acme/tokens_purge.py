"""Tokens scratch space, purged in bulk."""

from legacy import storage

PREFIX = "tmp/tokens/"


def stash(name, value):
    storage.put(PREFIX + name, value)


def purge():
    """Delete everything under PREFIX. Returns how many keys were deleted."""
    removed = 0
    for key, _ in storage.scan(PREFIX):
        if storage.delete(key):
            removed += 1
    return removed


def purge_matching(fragment):
    removed = 0
    for key, _ in storage.scan(PREFIX):
        if fragment in key[len(PREFIX):] and storage.delete(key):
            removed += 1
    return removed
