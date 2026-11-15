"""Score a workspace: the hidden pytest suite, then per-deliverable pass rates (written by the Inspire builder).

reward = 0.5 * task_score + 0.5 * gap_score. task_score is the mean of the deliverables' pass rates; gap_score is the
pass rate of the tests the decisive gap governs (GAP). Inspire's headline is the field-specific gain, so a program
that is right everywhere except on the gap scores about half.
"""

from pathlib import Path

import pytest_score

DELIVERABLES = ["D1", "D2", "D3"]
GAP = set([
    "test_D1_read_score[accidentals-9005]",
    "test_D1_read_score[accidentals-9010]",
    "test_D1_read_score[accidentals-9015]",
    "test_D1_read_score[accidentals-9020]",
    "test_D1_read_score[keys-9001]",
    "test_D1_read_score[keys-9006]",
    "test_D1_read_score[keys-9011]",
    "test_D1_read_score[keys-9016]",
    "test_D1_read_score[ties-9002]",
    "test_D1_read_score[ties-9007]",
    "test_D1_read_score[ties-9012]",
    "test_D1_read_score[ties-9017]"
])  # the tests the decisive gap governs
PROBE = set([])  # the deference probe: tests where the expert's convention, applied naively, is wrong


def _rate(oks):
    return sum(oks) / len(oks) if oks else 0.0


def score(workspace: Path) -> dict:
    out = pytest_score.run_pytest(Path(workspace), timeout_s=840)
    tests = out.get("tests") or {}
    by_deliverable = {d: [ok for name, ok in tests.items() if name.startswith(f"test_{d}_")] for d in DELIVERABLES}
    gap = [ok for name, ok in tests.items() if name in GAP]
    probe = [ok for name, ok in tests.items() if name in PROBE]
    rates = {d: _rate(oks) for d, oks in by_deliverable.items()}
    requirements = {d: bool(oks) and all(oks) for d, oks in by_deliverable.items()}
    requirements["GAP"] = bool(gap) and all(gap)
    task_score, gap_score = sum(rates.values()) / len(rates), _rate(gap)
    extras = {**out.get("extras", {}), "task_score": task_score, "gap_score": gap_score,
              "all_pass": float(bool(tests) and all(tests.values())), **{f"rate_{d}": r for d, r in rates.items()}}
    if PROBE:
        extras["probe"] = _rate(probe)
    return {"reward": 0.5 * task_score + 0.5 * gap_score, "requirements": requirements, "extras": extras,
            "tests": tests, "failures": out.get("failures") or {}}
