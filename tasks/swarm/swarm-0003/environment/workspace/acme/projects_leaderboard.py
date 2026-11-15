"""Projects leaderboard: each player's best score."""

from legacy import storage

PREFIX = "score/projects/"


def submit(player, points):
    if points > storage.get(PREFIX + player, 0):
        storage.put(PREFIX + player, points)


def top(n=3):
    """The n best (player, points), highest first, ties by name."""
    scores = [(key[len(PREFIX):], points) for key, points in storage.scan(PREFIX)]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]


def rank(player):
    """1-based position of the player, or None."""
    order = [name for name, _ in top(10**9)]
    return order.index(player) + 1 if player in order else None
