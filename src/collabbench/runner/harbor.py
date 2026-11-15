"""Harbor invocation: one `harbor run` job per cell, its spend recorded per trial."""

import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path

from collabbench import settings
from collabbench.runner.grid import Cell, Grid
from collabbench.runner.ledger import Ledger, choose_pool
from collabbench.runner.pools import Pool, trial_cost

HARBOR = settings.REPO / ".venv" / "bin" / "harbor"
AGENT = "collabbench.harness.team:TeamAgent"
FIRST_GUESS_USD = 0.25  # projected cost of one trial before any has been measured


def harbor_command(cell: Cell, jobs_dir: Path, job_name: str, model: str, concurrency: int) -> list[str]:
    cmd = [str(HARBOR), "run", "-p", str(cell.task_dir), "-a", AGENT, "-m", model, "-e", "modal",
           "--ek", "app_name=collabbench", "-n", str(min(concurrency, cell.runs)), "-k", str(cell.runs),
           "-o", str(jobs_dir), "--job-name", job_name, "-q", "-y"]
    for k, v in cell.kwargs.items():
        cmd += ["--ak", f"{k}={v}"]
    return cmd


def harbor_env(pool: Pool, key: str | None = None) -> dict[str, str]:
    """The key travels only in the environment. COLLAB_LLM_BASE_URL is left unset for Comet, so the harness re-reads
    the gateway's live URL (it moves when Comet's service job is preempted)."""
    env = {k: v for k, v in os.environ.items() if k != "COLLAB_LLM_BASE_URL"}
    env.update({"MODAL_PROFILE": pool.profile, "MODAL_ENVIRONMENT": pool.environment,
                "PYTHONPATH": str(settings.REPO / "src"),
                "COLLAB_LLM_API_KEY": key if key is not None else settings.gateway_key()})
    return env


def _ts(value) -> float | None:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() if value else None


def trial_sandbox_seconds(trial_dir: Path) -> tuple[float, float]:
    """(agent sandbox seconds, verifier sandbox seconds) from Harbor's result.json; conservative where unsure."""
    r = json.loads((Path(trial_dir) / "result.json").read_text())
    start, end = _ts(r.get("started_at")), _ts(r.get("finished_at"))
    v = r.get("verifier") or {}
    v_start, v_end = _ts(v.get("started_at")), _ts(v.get("finished_at"))
    if start is None or end is None:
        return 0.0, 0.0
    agent_s = (v_start or end) - start
    verifier_s = (v_end - v_start) if v_start and v_end else 0.0
    return agent_s, verifier_s


def run_cell(cell: Cell, grid: Grid, ledger: Ledger, jobs_root: Path) -> list[Path]:
    projected = cell.runs * (ledger.mean_cost() or FIRST_GUESS_USD)
    pool = choose_pool(ledger, grid.pool, projected)
    job_name = f"{cell.task_dir.name}--{cell.condition}--{time.strftime('%Y%m%d-%H%M%S')}"
    jobs_dir = Path(jobs_root) / grid.name
    jobs_dir.mkdir(parents=True, exist_ok=True)
    log = jobs_dir / f"{job_name}.log"
    with log.open("w") as f:
        subprocess.run(harbor_command(cell, jobs_dir, job_name, grid.model, grid.concurrency),
                       env=harbor_env(pool), stdout=f, stderr=subprocess.STDOUT, cwd=settings.REPO)
    trials = sorted(p.parent for p in (jobs_dir / job_name).glob("*/result.json"))
    for t in trials:
        agent_s, verifier_s = trial_sandbox_seconds(t)
        ledger.record(pool.name, job_name, t.name, trial_cost(agent_s, verifier_s), kind="trial",
                      track=cell.track, condition=cell.condition, agent_s=round(agent_s, 1),
                      verifier_s=round(verifier_s, 1))
    return trials
