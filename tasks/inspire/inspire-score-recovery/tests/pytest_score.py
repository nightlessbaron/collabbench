"""Shared scorer for test-based tracks: run the hidden pytest suite against a workspace, in a subprocess.

A test named test_<ID>_... belongs to requirement <ID> (R1, F2, ...). Otherwise `areas` ({requirement: [key prefix,
...]}) assigns it by its key. The reward is the fraction of hidden tests that pass (partial credit); a requirement is
met when all of its tests pass.

Keys: `key="name"` keys a test by its function name (synthetic tracks); `key="nodeid"` by `<dotted file path>::<name>`
(upstream suites repeat test names across files). `targets` (paths under hidden/) run as separate pytest processes, for
suites whose packages share a top-level name (several `tests` packages). hidden/expected_tests.json pins the test list:
a pinned test missing from the report counts as failed. The marker "collect" pins nothing (harvest mode: the run
reports every test it collected, for `collabbench pin-tests`). Every run also returns `collected` (each reported test,
pinned or not, so a re-gate can be re-pinned) and `failures` (per failed test, its outcome and the first line of its
message: pytest's assertion introspection after it is dropped, as it can show hidden expected values); the grader keeps
both in details.json. expected_tests.json is read before the suite runs, so agent code cannot rewrite the pin.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

HIDDEN = Path(__file__).resolve().parent / "hidden"
_REQ = re.compile(r"test_([A-Z]+\d+)_")


def _run_one(workspace: Path, hidden: Path, target: Path, timeout_s: int, args, key: str) -> tuple | None:
    """({test key: passed}, {failed test key: short reason}) for one pytest process, or None when the run did not
    produce a scoring."""
    with tempfile.TemporaryDirectory() as tmp:
        junit = Path(tmp) / "junit.xml"
        # -I: no PYTHONPATH, no cwd on sys.path, no user site (and no PYTHON* variables, hence -B: no bytecode written
        # into tests/). hidden/conftest.py appends the workspace to sys.path.
        env = {**os.environ, "COLLAB_WORKSPACE": str(workspace), "PYTHONDONTWRITEBYTECODE": "1"}
        cmd = [sys.executable, "-I", "-B", "-m", "pytest", str(target), "-q", "-p", "no:cacheprovider", "--rootdir",
               str(hidden), "-c", os.devnull, f"--junitxml={junit}", "-o", "junit_family=xunit1", *args]
        try:
            run = subprocess.run(cmd, cwd=workspace, env=env, capture_output=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            return None
        if run.returncode not in (0, 1) or not junit.exists():  # 0 all passed, 1 some failed; else not a scoring
            return None
        results, failures = {}, {}
        for case in ET.parse(junit).getroot().iter("testcase"):
            if any(c.tag == "error" and c.get("message") == "collection failure" for c in case):
                continue  # a module that failed to import: its tests are missing, and count as failed if pinned
            bad = [child for child in case if child.tag in ("failure", "error", "skipped")]
            name = case.get("name", "")
            name = f"{case.get('classname', '')}::{name}" if key == "nodeid" else name
            results[name] = not bad
            if bad:  # why, for details.json (never shown to the agents): the first line only, the exception and its
                # message; pytest's assertion introspection after it can hold expected values
                why = (bad[0].get("message") or bad[0].text or "").strip().splitlines()
                failures[name] = f"{bad[0].tag}: {why[0] if why else ''}"[:300]
        return results, failures


def run_pytest(workspace: Path, hidden: Path = HIDDEN, timeout_s: int = 600, *, key: str = "name",
               targets: list[str] | None = None, args: list[str] = (), areas: dict | None = None) -> dict:
    workspace, hidden = Path(workspace).resolve(), Path(hidden)
    expected_path = hidden / "expected_tests.json"  # read before any agent code runs, so the run cannot rewrite it
    expected = json.loads(expected_path.read_text()) if expected_path.exists() else None
    results, failures, broken = {}, {}, 0
    for target in targets or [None]:
        got = _run_one(workspace, hidden, hidden / target if target else hidden, timeout_s, list(args), key)
        if got is None:
            broken += 1
        else:
            results.update(got[0])
            failures.update(got[1])
    collected = dict(results)  # every test the run reported, pinned or not (for re-pinning after a re-gate)
    extras = {}
    if broken:
        extras["collection_error"] = 1.0
    if expected == "collect":
        extras["harvest"] = 1.0
    elif expected is not None:  # pinned from the reference run: a test missing from the report counts as failed
        results = {name: results.get(name, False) for name in expected}
    if not results:
        return {"reward": 0.0, "requirements": {}, "extras": {**extras, "collection_error": 1.0}}
    requirements: dict[str, bool] = {}
    for name, ok in results.items():
        m = _REQ.match(name.rsplit("::", 1)[-1])
        req = m.group(1) if m else next((r for r, prefixes in (areas or {}).items()
                                         if any(name.startswith(p) for p in prefixes)), None)
        if req:
            requirements[req] = requirements.get(req, True) and ok
    return {"reward": sum(results.values()) / len(results), "requirements": requirements,
            "extras": {**extras, "tests_passed": float(sum(results.values())), "tests_total": float(len(results))},
            "tests": results, "collected": collected, "failures": failures}
