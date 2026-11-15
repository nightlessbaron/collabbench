"""Pin a task's hidden test list from gate runs on Modal (harvest mode).

A task written with `expected_tests="collect"` reports every collected test in its verifier's details.json
(`final.tests`, {test key: passed}). `pin_tests` reads the reference (oracle) run, and optionally the untouched-start
(nop) run, and writes hidden/expected_tests.json: the tests that pass on the reference and, when a start run is given,
fail on the start (a test that already passes before the migration measures nothing about it).
"""

import json
from pathlib import Path


def gate_tests(run_dir: Path, allow_empty: bool = False) -> dict[str, bool]:
    """Every collected test ({key: passed}) of the single verifier details.json under a gate job or trial directory:
    `final.collected` (any run), else `final.tests` (a harvest run). A start run may collect nothing, when every test
    module fails to import; a scoring error is never read as "nothing passes"."""
    found = sorted(Path(run_dir).rglob("verifier/details.json"))
    if len(found) != 1:
        raise ValueError(f"expected exactly one verifier/details.json under {run_dir}, found {len(found)}")
    final = json.loads(found[0].read_text())["final"]
    if final.get("error"):
        raise ValueError(f"{found[0]} records a scoring error: {str(final['error'])[:200]}")
    tests = final.get("collected") or final.get("tests") or {}
    if not tests and not allow_empty:
        raise ValueError(f"{found[0]} lists no tests: was the task in harvest mode (expected_tests 'collect')?")
    return tests


def pin_tests(task_dir: Path, oracle_run: Path, nop_run: Path | None = None) -> dict:
    ref = gate_tests(oracle_run)
    start = gate_tests(nop_run, allow_empty=True) if nop_run else {}
    passed = {name for name, ok in ref.items() if ok}
    pinned = sorted(name for name in passed if not start.get(name, False))
    (Path(task_dir) / "tests" / "hidden" / "expected_tests.json").write_text(json.dumps(pinned, indent=1))
    return {"collected": len(ref), "pinned": len(pinned), "failed_on_reference": len(ref) - len(passed),
            "passed_on_start": len(passed) - len(pinned)}
