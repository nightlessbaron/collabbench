import json
from pathlib import Path

from pytest_score import run_pytest

HERE = Path(__file__).resolve().parent
AREAS = {req: area["prefixes"] for req, area in json.loads((HERE / "hidden" / "areas.json").read_text()).items()}


def score(workspace: Path) -> dict:
    return run_pytest(workspace, key="nodeid", areas=AREAS, targets=None, timeout_s=1200,
                      args=['--continue-on-collection-errors'])
