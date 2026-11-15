"""Outcome statistics over scores: best-of-k, gains, the multiplier, communication value, time to score."""

import math
from statistics import fmean

from collabbench.metrics.trial import graded_trace


def expected_best_of_k(scores: list[float], k: int) -> float:
    """Expected maximum of k scores drawn without replacement from `scores` (unbiased)."""
    n = len(scores)
    if k < 1 or n < k:
        raise ValueError(f"need 1 <= k <= n, got k={k}, n={n}")
    ordered = sorted(scores)
    return sum(s * math.comb(i - 1, k - 1) for i, s in enumerate(ordered, 1)) / math.comb(n, k)


def collaboration_gain(team: list[float], solo: list[float]) -> float:
    """Ratio of mean team score to mean solo score."""
    t, s = fmean(team), fmean(solo)
    if s == 0:
        return math.inf if t > 0 else math.nan
    return t / s


def interaction_gain(team: list[float], solo_B: list[float], k: int) -> float:
    """Team mean minus the expected best of k independent solo runs at budget B."""
    return fmean(team) - expected_best_of_k(solo_B, k)


def multiplier(team: list[float], solo_B: list[float], k: int) -> float:
    """How many independent solo runs it takes to match the team mean, relative to k (inf when never)."""
    target = fmean(team)
    for k_prime in range(1, len(solo_B) + 1):
        if expected_best_of_k(solo_B, k_prime) >= target:
            return k_prime / k
    return math.inf


def comm_value_captured(team: list[float], nocomm: list[float], oracle: list[float]) -> float | None:
    """Share of the gap between no communication and the oracle that the team closes."""
    t, n, o = fmean(team), fmean(nocomm), fmean(oracle)
    return None if o == n else (t - n) / (o - n)


def time_to_score(trace: list[dict], q: float) -> float | None:
    """Time of the first graded-workspace snapshot whose reward reaches q, or None."""
    for point in graded_trace(trace):
        if point["reward"] >= q:
            return point["t"]
    return None


def interaction_gain_by_instance(per_instance: list[tuple[list[float], list[float]]], k: int) -> float:
    """Mean over instances of interaction_gain(team_i, solo_B_i, k); instances with fewer than k solo runs or no team
    runs are left out. Raises ValueError when none remain."""
    gains = [interaction_gain(t, s, k) for t, s in per_instance if t and len(s) >= k]
    if not gains:
        raise ValueError("no instance has team runs and k solo runs")
    return fmean(gains)


def multiplier_by_instance(per_instance: list[tuple[list[float], list[float]]], k: int) -> float:
    """multiplier with best-of-k' taken within each instance and then averaged over instances."""
    usable = [(t, s) for t, s in per_instance if t and len(s) >= k]
    if not usable:
        raise ValueError("no instance has team runs and k solo runs")
    target = fmean(fmean(t) for t, _ in usable)
    for k_prime in range(1, min(len(s) for _, s in usable) + 1):
        if fmean(expected_best_of_k(s, k_prime) for _, s in usable) >= target:
            return k_prime / k
    return math.inf
