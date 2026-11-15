"""Exports leaderboard: each player's best score."""

from legacy import storage

PREFIX = "score/exports/"


def submit(player, points):
    if points > storage.get(PREFIX + player, 0):
        storage.put(PREFIX + player, points)


def top(n=5):
    """The n best (player, points), highest first, ties by name."""
    scores = [(key[len(PREFIX):], points) for key, points in storage.scan(PREFIX)]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]
