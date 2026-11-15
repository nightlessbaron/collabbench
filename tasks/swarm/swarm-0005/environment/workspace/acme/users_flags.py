"""Users feature flags."""

from legacy import storage

PREFIX = "flag/users/"
DEFAULT = False


def enabled(flag):
    return bool(storage.get(PREFIX + flag, DEFAULT))


def set_flag(flag, on):
    storage.put(PREFIX + flag, bool(on))


def toggle(flag):
    now = not enabled(flag)
    set_flag(flag, now)
    return now
