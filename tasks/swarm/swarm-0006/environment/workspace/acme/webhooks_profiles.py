"""Webhooks profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/webhooks/"
TTL_SECONDS = 3600
DEFAULTS = {'theme': 'eu', 'locale': 'a', 'currency': 'a'}


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)


def clear_profile(uid):
    return storage.delete(PREFIX + uid)
