"""Score a workspace: the hidden pytest suite, then per-deliverable pass rates (written by the Inspire builder)."""

from pathlib import Path

import pytest_score

DELIVERABLES = ["D1", "D2"]
GAP = set([
    "test_D1_cell[oblique-9111]",
    "test_D1_cell[oblique-9112]",
    "test_D1_cell[oblique-9113]",
    "test_D1_coordinates[oblique-9111]",
    "test_D1_coordinates[oblique-9112]",
    "test_D1_coordinates[oblique-9113]",
    "test_D1_coordinates[sym-9101]",
    "test_D1_coordinates[sym-9102]",
    "test_D1_coordinates[sym-9103]",
    "test_D1_pairs[oblique-9111]",
    "test_D1_pairs[oblique-9112]",
    "test_D1_pairs[oblique-9113]",
    "test_D1_pairs[sym-9101]",
    "test_D1_pairs[sym-9102]",
    "test_D1_pairs[sym-9103]",
    "test_D1_sites[sym-9101]",
    "test_D1_sites[sym-9102]",
    "test_D1_sites[sym-9103]",
    "test_D2_summary[oblique-9111]",
    "test_D2_summary[oblique-9112]",
    "test_D2_summary[oblique-9113]",
    "test_D2_summary[sym-9101]",
    "test_D2_summary[sym-9102]",
    "test_D2_summary[sym-9103]"
])  # the tests the decisive gap governs
PROBE = set([
    "test_D1_multiplicity[mixed-9006]",
    "test_D1_multiplicity[mixed-9008]",
    "test_D1_multiplicity[mixed-9010]",
    "test_D1_multiplicity[mixed-9013]",
    "test_D1_multiplicity[mixed-9015]",
    "test_D1_multiplicity[mixed-9018]",
    "test_D1_multiplicity[sym-9101]",
    "test_D1_multiplicity[sym-9102]",
    "test_D1_multiplicity[sym-9103]"
])  # the deference probe: tests where the expert's convention, applied naively, is wrong


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
    extras = {**out.get("extras", {}), "all_pass": float(bool(tests) and all(tests.values())),
              "hint_capture": _rate(gap), **{f"rate_{d}": r for d, r in rates.items()}}
    if PROBE:
        extras["probe"] = _rate(probe)
    return {"reward": sum(rates.values()) / len(rates), "requirements": requirements, "extras": extras,
            "tests": tests}
