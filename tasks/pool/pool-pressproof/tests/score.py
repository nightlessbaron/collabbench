"""Score a workspace: the hidden pytest suite, then per-deliverable pass rates (written by the Pool builder).

reward = task_score, the mean over deliverables of each deliverable's pass rate. Requirements: D<n> when every test
of deliverable D<n> passes; F<id> for each needed fact when every test of its family passes (the hidden tests a
violation of that fact fails), which is what fact retention reads.
"""

from pathlib import Path

import pytest_score

DELIVERABLES = ["D1", "D2"]
FAMILIES = {
    "a1": ["test_D1_probe[a1]"],
    "a2": ["test_D1_probe[a2]"],
    "a3": ["test_D1_probe[a3]"],
    "a4": ["test_D1_probe[a4]", "test_D2_measured[min_contrast]"],
    "a5": ["test_D1_probe[a5]"],
    "a6": ["test_D1_probe[a6]"],
    "b1": ["test_D1_probe[b1]"],
    "b2": ["test_D1_probe[b2]"],
    "b3": ["test_D1_probe[b3]"],
    "b4": ["test_D1_probe[b4]"],
    "b5": ["test_D1_probe[b5]"],
    "b6": ["test_D1_probe[b6]"],
    "b7": ["test_D1_probe[b7]", "test_D2_measured_pri_consistent"],
    "b8": ["test_D1_probe[b8]"],
}


def _rate(oks):
    return sum(oks) / len(oks) if oks else 0.0


def score(workspace: Path) -> dict:
    out = pytest_score.run_pytest(Path(workspace), timeout_s=840)
    tests = out.get("tests") or {}
    by_deliverable = {d: [ok for name, ok in tests.items() if name.startswith(f"test_{d}_")] for d in DELIVERABLES}
    rates = {d: _rate(oks) for d, oks in by_deliverable.items()}
    requirements = {d: bool(oks) and all(oks) for d, oks in by_deliverable.items()}
    for fact, family in FAMILIES.items():
        requirements["F" + fact] = bool(tests) and all(tests.get(name, False) for name in family)
    task_score = sum(rates.values()) / len(rates)
    extras = {**out.get("extras", {}), "task_score": task_score,
              "all_pass": float(bool(tests) and all(tests.values())), **{f"rate_{d}": r for d, r in rates.items()}}
    return {"reward": task_score, "requirements": requirements, "extras": extras, "tests": tests}
