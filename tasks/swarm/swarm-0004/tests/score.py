from pathlib import Path

from pytest_score import run_pytest


def score(workspace: Path) -> dict:
    return run_pytest(workspace)
