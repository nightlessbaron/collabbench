"""Projects feature flags."""

from legacy import storage

PREFIX = "flag/projects/"
DEFAULT = True


def enabled(flag):
    return bool(storage.get(PREFIX + flag, DEFAULT))


def set_flag(flag, on):
    storage.put(PREFIX + flag, bool(on))
