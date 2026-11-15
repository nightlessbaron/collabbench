"""Files audit log: one record per event."""

from legacy import storage

PREFIX = "audit/files/"
TTL_SECONDS = 43200


def record(event_id, payload):
    storage.put(PREFIX + event_id, payload, ttl=TTL_SECONDS)


def history():
    """Every payload, in event-id order."""
    return [payload for _, payload in storage.scan(PREFIX)]


def count():
    return len(storage.scan(PREFIX))
