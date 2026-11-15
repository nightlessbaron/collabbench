"""Shared scorer for test-based tracks: run the hidden pytest suite against a workspace, in a subprocess.

A test named test_<ID>_... belongs to requirement <ID> (R1, F2, ...). The reward is the fraction of hidden tests that
pass (partial credit); a requirement is met when all of its tests pass.
"""

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
    with tempfile.TemporaryDirectory() as tmp:
        junit = Path(tmp) / "junit.xml"
        env = {**os.environ, "PYTHONPATH": str(workspace), "PYTHONDONTWRITEBYTECODE": "1"}
        cmd = [sys.executable, "-m", "pytest", str(hidden), "-q", "-p", "no:cacheprovider", "--rootdir", str(hidden),
               "-c", os.devnull, f"--junitxml={junit}", "-o", "junit_family=xunit1"]
        try:
            subprocess.run(cmd, cwd=workspace, env=env, capture_output=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            return {"reward": 0.0, "requirements": {}, "extras": {"timeout": 1.0}}
        if not junit.exists():
            return {"reward": 0.0, "requirements": {}, "extras": {"collection_error": 1.0}}
        results = {}
        for case in ET.parse(junit).getroot().iter("testcase"):
            failed = any(child.tag in ("failure", "error", "skipped") for child in case)
            results[case.get("name", "")] = not failed
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
