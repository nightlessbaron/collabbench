import itertools
import math
import random

import pytest

from collabbench.metrics.outcome import (collaboration_gain, comm_value_captured, expected_best_of_k,
                                          interaction_gain, multiplier, time_to_score)


def test_best_of_k_matches_bruteforce():
    rng = random.Random(7)
    scores = [round(rng.random(), 3) for _ in range(6)]
    for k in range(1, 7):
        subsets = list(itertools.combinations(scores, k))
        assert expected_best_of_k(scores, k) == pytest.approx(sum(max(s) for s in subsets) / len(subsets))


def test_best_of_k_needs_n_at_least_k():
    with pytest.raises(ValueError):
        expected_best_of_k([0.1, 0.2], 3)


def test_multiplier_inf_when_unreached():
    assert multiplier([1.0, 1.0], [0.1, 0.2, 0.3], 2) == math.inf


def test_multiplier_is_smallest_matching_k_over_k():
    solo = [0.0, 0.0, 1.0, 1.0]  # best of 1 = 0.5, best of 2 = 5/6, best of 3 = 1
    assert multiplier([0.8, 0.8], solo, 2) == 2 / 2
    assert multiplier([0.4, 0.4], solo, 2) == 1 / 2


def test_gains():
    assert collaboration_gain([0.6, 0.8], [0.35, 0.35]) == pytest.approx(2.0)
    assert interaction_gain([0.9], [0.0, 1.0], 2) == pytest.approx(0.9 - 1.0)


def test_cvc_none_when_degenerate():
    assert comm_value_captured([0.9], [0.5], [0.5]) is None
    assert comm_value_captured([0.7], [0.5], [0.9]) == pytest.approx(0.5)


def test_time_to_score():
    trace = [{"t": 30, "reward": 0.5, "label": "workspace"}, {"t": 10, "reward": 0.25, "label": "workspace"},
             {"t": 60, "reward": 1.0, "label": "workspace"}]
    assert time_to_score(trace, 0.5) == 30
    assert time_to_score(trace, 1.0) == 60
    assert time_to_score(trace[:1], 1.0) is None


def test_time_to_score_reads_only_graded_clean_rows():
    trace = [{"t": 5, "reward": 1.0, "label": "agent-1"},                      # a worktree copy, not the deliverable
             {"t": 8, "reward": 0.0, "label": "workspace", "error": "boom"},
             {"t": 20, "reward": 1.0, "label": "workspace"}]
    assert time_to_score(trace, 1.0) == 20
    assert time_to_score(trace[:2], 0.0) is None  # an error row's fallback 0.0 is not a score
