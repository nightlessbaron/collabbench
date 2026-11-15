"""Static gates on Modal (design 9): the reference scores 1 (and is graded isolated, where the task runs agent code),
the untouched start scores 0, the image builds, the tripwire stays quiet under the reference, private context is gone
before agents start, and concurrent exec works."""

import json
import subprocess
import time
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from collabbench import settings
from collabbench.runner.harbor import AGENT, HARBOR, harbor_env, trial_cost, trial_sandbox_seconds
from collabbench.runner.ledger import Ledger
from collabbench.runner.pools import POOLS

ORACLE_MIN = {"inspire": 0.98}  # every other track needs exactly 1.0
NOP_MAX = 0.05
PARALLEL_MAX_S = 6.0


@dataclass
class GateReport:
    task: str
    track: str
    oracle_reward: float | None
    nop_reward: float | None
    unauthorized_on_oracle: int | None
    private_removed: bool
    image_ok: bool
    parallel_exec_s: float | None
    passed: bool
    notes: list[str] = field(default_factory=list)
    cost_usd: float = 0.0


def parse_trial(trial_dir: Path) -> dict:
    r = json.loads((Path(trial_dir) / "result.json").read_text())
    rewards = (r.get("verifier_result") or {}).get("rewards") or {}
    return {"reward": rewards.get("reward"), "rewards": rewards,
            "metadata": (r.get("agent_result") or {}).get("metadata") or {},
            "exception": (r.get("exception_info") or {}).get("exception_type"), "dir": str(trial_dir)}


def evaluate_gate(task: str, track: str, oracle: dict, nop: dict, probe: dict) -> GateReport:
    notes = []
    image_ok = not any(t.get("exception") for t in (oracle, nop, probe))
    if not image_ok:
        notes.append("a gate trial raised: " + ", ".join(f"{k}={t['exception']}" for k, t in
                                                          (("oracle", oracle), ("nop", nop), ("probe", probe))
                                                          if t.get("exception")))
    o, n = oracle.get("reward"), nop.get("reward")
    need = ORACLE_MIN.get(track, 1.0)
    if o is None or o < need:
        notes.append(f"oracle reward {o} < {need}")
    if n is None or n > NOP_MAX:
        notes.append(f"nop reward {n} > {NOP_MAX}")
    unauthorized = oracle.get("rewards", {}).get("unauthorized")
    if unauthorized:
        notes.append("the reference run fired the tripwire")
    if oracle.get("rewards", {}).get("isolated") == 0:  # recorded only by tasks that run agent code (agent_uid)
        notes.append("the reference run was graded unisolated (isolated = 0): agent code ran as the grader's user")
    p = probe.get("metadata", {}).get("probe") or {}
    removed = p.get("private_exists") is False
    if not removed:
        notes.append("private context still present after setup (or probe missing)")
    par = p.get("parallel_exec_s")
    if par is None or par >= PARALLEL_MAX_S:
        notes.append(f"8 concurrent 2 s commands took {par} s (expected < {PARALLEL_MAX_S})")
    return GateReport(task, track, o, n, unauthorized, removed, image_ok, par, not notes, notes)


def _job(task_dir: Path, agent: str, extra: list[str], jobs_dir: Path, name: str) -> list[str]:
    return [str(HARBOR), "run", "-p", str(task_dir), "-a", agent, "-e", "modal", "--ek", "app_name=collabbench",
            "-n", "1", "-k", "1", "-o", str(jobs_dir), "--job-name", name, "-q", "-y", *extra]


def gate_instance(task_dir: Path, pool: str = "personal", ledger: Ledger | None = None) -> GateReport:
    task_dir = Path(task_dir).resolve()
    track = tomllib.loads((task_dir / "task.toml").read_text())["metadata"]["collab"]["track"]
    ledger = ledger or Ledger(settings.REPO / "runs" / "ledger.jsonl")
    jobs_dir = settings.REPO / "runs" / "gates"
    jobs_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    kinds = {"oracle": ("oracle", []), "nop": ("nop", []),
             "probe": (AGENT, ["-m", settings.MODEL, "--ak", "probe=true"])}
    env = harbor_env(POOLS[pool])
    procs = {}
    for kind, (agent, extra) in kinds.items():
        name = f"{task_dir.name}--gate-{kind}--{stamp}"
        log = (jobs_dir / f"{name}.log").open("w")
        procs[kind] = (name, subprocess.Popen(_job(task_dir, agent, extra, jobs_dir, name), env=env, stdout=log,
                                              stderr=subprocess.STDOUT, cwd=settings.REPO))
    results, cost = {}, 0.0
    for kind, (name, proc) in procs.items():
        proc.wait()
        trials = sorted(p.parent for p in (jobs_dir / name).glob("*/result.json"))
        if not trials:
            results[kind] = {"reward": None, "rewards": {}, "metadata": {}, "exception": "NoTrial"}
            continue
        results[kind] = parse_trial(trials[0])
        usd = trial_cost(*trial_sandbox_seconds(trials[0]))
        cost += usd
        ledger.record(pool, name, trials[0].name, usd, kind="gate", task=task_dir.name)
    report = evaluate_gate(task_dir.name, track, results["oracle"], results["nop"], results["probe"])
    report.cost_usd = round(cost, 4)
    return report
