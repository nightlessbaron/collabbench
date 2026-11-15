"""Sensors profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/sensors/"
TTL_SECONDS = 14400
DEFAULTS = {'currency': 'off', 'theme': 'eu', 'region': 'a'}


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)
