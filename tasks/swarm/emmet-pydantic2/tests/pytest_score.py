"""Shared scorer for test-based tracks: run the hidden pytest suite against a workspace, in a subprocess.

A test named test_<ID>_... belongs to requirement <ID> (R1, F2, ...). Otherwise `areas` ({requirement: [key prefix,
...]}) assigns it by its key. The reward is the fraction of hidden tests that pass (partial credit); a requirement is
met when all of its tests pass.

Keys: `key="name"` keys a test by its function name (synthetic tracks); `key="nodeid"` by `<dotted file path>::<name>`
(upstream suites repeat test names across files). `targets` (paths under hidden/) run as separate pytest processes, for
suites whose packages share a top-level name (several `tests` packages). hidden/expected_tests.json pins the test list:
a pinned test missing from the report counts as failed. The marker "collect" pins nothing (harvest mode: the run
reports every test it collected, for `collabbench pin-tests`).
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


def _run_one(workspace: Path, hidden: Path, target: Path, timeout_s: int, args, key: str) -> dict | None:
    """{test key: passed} for one pytest process, or None when the run did not produce a scoring."""
    with tempfile.TemporaryDirectory() as tmp:
        junit = Path(tmp) / "junit.xml"
        # -I: no PYTHONPATH, no cwd on sys.path, no user site. hidden/conftest.py appends the workspace to sys.path.
        env = {**os.environ, "COLLAB_WORKSPACE": str(workspace), "PYTHONDONTWRITEBYTECODE": "1"}
        cmd = [sys.executable, "-I", "-m", "pytest", str(target), "-q", "-p", "no:cacheprovider", "--rootdir",
               str(hidden), "-c", os.devnull, f"--junitxml={junit}", "-o", "junit_family=xunit1", *args]
        try:
            run = subprocess.run(cmd, cwd=workspace, env=env, capture_output=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            return None
        if run.returncode not in (0, 1) or not junit.exists():  # 0 all passed, 1 some failed; else not a scoring
            return None
        results = {}
        for case in ET.parse(junit).getroot().iter("testcase"):
            if any(c.tag == "error" and c.get("message") == "collection failure" for c in case):
                continue  # a module that failed to import: its tests are missing, and count as failed if pinned
            failed = any(child.tag in ("failure", "error", "skipped") for child in case)
            name = case.get("name", "")
            results[f"{case.get('classname', '')}::{name}" if key == "nodeid" else name] = not failed
        return results


def run_pytest(workspace: Path, hidden: Path = HIDDEN, timeout_s: int = 600, *, key: str = "name",
               targets: list[str] | None = None, args: list[str] = (), areas: dict | None = None) -> dict:
    workspace, hidden = Path(workspace).resolve(), Path(hidden)
    results, broken = {}, 0
    for target in targets or [None]:
        got = _run_one(workspace, hidden, hidden / target if target else hidden, timeout_s, list(args), key)
        if got is None:
            broken += 1
        else:
            results.update(got)
    extras = {}
    if broken:
        extras["collection_error"] = 1.0
    expected_path = hidden / "expected_tests.json"
    expected = json.loads(expected_path.read_text()) if expected_path.exists() else None
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
            "tests": results}
