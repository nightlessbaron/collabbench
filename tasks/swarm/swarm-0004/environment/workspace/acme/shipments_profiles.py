"""Shipments profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/shipments/"
TTL_SECONDS = 14400
DEFAULTS = {'digest': 'off', 'region': 'a', 'timezone': 'c'}


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)


def clear_profile(uid):
    return storage.delete(PREFIX + uid)
