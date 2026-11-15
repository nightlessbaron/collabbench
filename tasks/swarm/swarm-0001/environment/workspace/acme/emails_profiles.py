"""Emails profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/emails/"
TTL_SECONDS = 7200
DEFAULTS = {'plan': 'eu', 'timezone': 'off', 'locale': 'on'}


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)


def clear_profile(uid):
    return storage.delete(PREFIX + uid)
