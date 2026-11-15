"""Comments profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/comments/"
TTL_SECONDS = 7200
DEFAULTS = {'digest': 'c', 'region': 'off', 'locale': 'a'}


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)


def clear_profile(uid):
    return storage.delete(PREFIX + uid)
