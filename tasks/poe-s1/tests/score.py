import json
import shutil
import tempfile
from pathlib import Path

from pytest_score import run_pytest
from units_score import score_units

HERE = Path(__file__).resolve().parent


def score(workspace: Path) -> dict:
    # The suite writes into its own tree (tests/temp, .coverage, fixture build/ assets), and grade.py voids a grade when
    # anything under /tests changes: run it on a fresh copy of hidden/ for each scoring (also hermetic between snapshots).
    with tempfile.TemporaryDirectory() as tmp:
        hidden = Path(tmp) / "hidden"
        shutil.copytree(HERE / "hidden", hidden)
        out = run_pytest(workspace, hidden=hidden, key="nodeid", targets=["tests"], timeout_s=1500,
                         args=['--continue-on-collection-errors'])
    units_path = HERE / "hidden" / "units.json"
    if not units_path.exists() or "tests" not in out:  # harvest mode, or nothing ran: pytest_score's own reward
        return out
    scored = score_units(out["tests"], json.loads(units_path.read_text()))
    return {**out, "reward": scored["reward"], "requirements": scored["requirements"],
            "extras": {**out["extras"], **scored["extras"]}}
