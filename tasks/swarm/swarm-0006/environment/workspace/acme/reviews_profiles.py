"""Reviews profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/reviews/"
TTL_SECONDS = 600
DEFAULTS = {'theme': 'c', 'region': 'on', 'plan': 'on'}


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)


def clear_profile(uid):
    return storage.delete(PREFIX + uid)
