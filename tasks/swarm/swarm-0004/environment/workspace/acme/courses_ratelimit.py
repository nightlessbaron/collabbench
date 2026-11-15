"""Courses rate limiting: at most LIMIT actions per user."""

from legacy import storage

PREFIX = "count/rate/courses/"
LIMIT = 5


def hit(user):
    """Count one action. True while the user is within the limit."""
    return storage.incr(PREFIX + user) <= LIMIT


def reset(user):
    storage.delete(PREFIX + user)
