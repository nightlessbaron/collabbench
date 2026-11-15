"""Score a task locally, without Docker: the reference or the untouched start, through the task's own grader."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Literal


def score_locally(task_dir: Path, state: Literal["reference", "start"], workspace: Path | None = None) -> dict:
    task_dir = Path(task_dir)
    with tempfile.TemporaryDirectory() as tmp:
        ws = Path(tmp) / "workspace"
        shutil.copytree(workspace or task_dir / "environment" / "workspace", ws)
        if state == "reference":
            subprocess.run(["bash", str(task_dir / "solution" / "solve.sh")], check=True, capture_output=True,
                           env={**os.environ, "WORKSPACE": str(ws)})
        run = subprocess.run([sys.executable, str(task_dir / "tests" / "grade.py"), "--score-one", str(ws)],
                             capture_output=True, text=True, timeout=900)
        if run.returncode != 0:
            raise RuntimeError(f"scoring {task_dir.name} ({state}) failed:\n{run.stderr[-3000:]}")
        return json.loads(run.stdout.strip().splitlines()[-1])
