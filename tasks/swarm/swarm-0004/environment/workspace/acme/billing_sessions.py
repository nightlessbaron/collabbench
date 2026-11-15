"""Billing sessions: a cache of signed-in session data."""

from legacy import storage

PREFIX = "session/billing/"
TTL_SECONDS = 2700


def load(session_id):
    """The session's data, or None if it expired or never existed."""
    return storage.get(PREFIX + session_id)


def save(session_id, data):
    storage.put(PREFIX + session_id, data, ttl=TTL_SECONDS)


def drop(session_id):
    """Delete the session. True if it existed."""
    return storage.delete(PREFIX + session_id)


def touch(session_id):
    """Save the session again to restart its ttl. False if there is no session."""
    data = storage.get(PREFIX + session_id)
    if data is None:
        return False
    storage.put(PREFIX + session_id, data, ttl=TTL_SECONDS)
    return True
