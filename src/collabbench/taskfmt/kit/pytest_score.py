"""Shared scorer for test-based tracks: run the hidden pytest suite against a workspace, in a subprocess.

A test named test_<ID>_... belongs to requirement <ID> (R1, F2, ...). The reward is the fraction of hidden tests that
pass (partial credit); a requirement is met when all of its tests pass.
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


def run_pytest(workspace: Path, hidden: Path = HIDDEN, timeout_s: int = 600) -> dict:
    workspace = Path(workspace).resolve()
    expected = hidden / "expected_tests.json"  # read before any agent code runs, so the run cannot rewrite it
    pinned = json.loads(expected.read_text()) if expected.exists() else None
    with tempfile.TemporaryDirectory() as tmp:
        junit = Path(tmp) / "junit.xml"
        # -I: no PYTHONPATH, no cwd on sys.path, no user site (and no PYTHON* variables, hence -B: no bytecode written
        # into tests/). hidden/conftest.py appends the workspace to sys.path.
        env = {**os.environ, "COLLAB_WORKSPACE": str(workspace), "PYTHONDONTWRITEBYTECODE": "1"}
        cmd = [sys.executable, "-I", "-B", "-m", "pytest", str(hidden), "-q", "-p", "no:cacheprovider", "--rootdir",
               str(hidden), "-c", os.devnull, f"--junitxml={junit}", "-o", "junit_family=xunit1"]
        try:
            run = subprocess.run(cmd, cwd=workspace, env=env, capture_output=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            return {"reward": 0.0, "requirements": {}, "extras": {"timeout": 1.0}}
        if run.returncode not in (0, 1) or not junit.exists():  # 0 all passed, 1 some failed; else not a scoring
            return {"reward": 0.0, "requirements": {}, "extras": {"collection_error": 1.0}}
        results = {}
        for case in ET.parse(junit).getroot().iter("testcase"):
            failed = any(child.tag in ("failure", "error", "skipped") for child in case)
            results[case.get("name", "")] = not failed
    if pinned is not None:  # pinned from the reference run: a test missing from the report counts as failed
        results = {name: results.get(name, False) for name in pinned}
    if not results:
        return {"reward": 0.0, "requirements": {}, "extras": {"collection_error": 1.0}}
    requirements: dict[str, bool] = {}
    for name, ok in results.items():
        m = _REQ.match(name)
        if m:
            requirements[m.group(1)] = requirements.get(m.group(1), True) and ok
    return {"reward": sum(results.values()) / len(results), "requirements": requirements,
            "extras": {"tests_passed": float(sum(results.values())), "tests_total": float(len(results))},
            "tests": results}
