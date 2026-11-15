import json
from pathlib import Path

import sims

HERE = Path(__file__).resolve().parent


def score(workspace: Path) -> dict:
    spec = json.loads((HERE / "sim_params.json").read_text())
    sim, params = sims.SIMULATORS[spec["concept"]], spec["params"]
    try:
        plan = json.loads((Path(workspace) / "plan.json").read_text())
    except (OSError, ValueError):
        plan = None
    if plan is None or sim.validate(plan, params) is not None:
        return {"reward": 0.0, "requirements": {"R1": False, "R2": False, "R3": False},
                "extras": {"hint_capture": 0.0, "normalized": 0.0}}
    normalized = sim.normalized(plan, params)
    return {"reward": min(1.0, max(0.0, normalized)),
            "requirements": {"R1": True, "R2": normalized >= 0.5, "R3": normalized >= 0.9},
            "extras": {"hint_capture": sim.hint_capture(plan, params), "normalized": normalized}}
