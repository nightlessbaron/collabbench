"""Media feature flags."""

from legacy import storage

PREFIX = "flag/media/"
DEFAULT = False


def enabled(flag):
    return bool(storage.get(PREFIX + flag, DEFAULT))


def set_flag(flag, on):
    storage.put(PREFIX + flag, bool(on))
