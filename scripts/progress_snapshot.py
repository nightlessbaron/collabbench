"""Writes the build-progress datasets for the CollabBench progress dashboard (tasks, live runs, rulings) as JSON
{rows, meta} files under runs/progress/. Reads the plan, the execution ledger and the Modal spend ledger."""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PLAN = REPO / "docs/superpowers/plans/2026-11-15-collabbench-v1.md"
WS = REPO / ".superpowers/sdd/2026-11-15-collabbench-v1"
OUT = REPO / "runs/progress"
HOME = str(Path.home())


def clean(text: str) -> str:
    return text.replace(HOME, "~").replace(str(REPO), "freedom")


def tasks() -> list[dict]:
    titles = re.findall(r"^### Task (\d+): (.+)$", PLAN.read_text(), re.M)
    ledger = (WS / "progress.md").read_text() if (WS / "progress.md").exists() else ""
    rows = []
    for num, title in titles:
        done = re.search(rf"^Task {num}: complete \(commits (\w+)\.\.(\w+)(.*)$", ledger, re.M)
        tests = re.search(r"(\d+) passed", done.group(3)) if done else None
        tests = tests.group(1) if tests else None
        started = (WS / f"task-{num}-brief.md").exists()
        status = "done" if done else ("in progress" if started else "to do")
        rows.append({"task": int(num), "title": clean(title.strip()), "status": status,
                     "tests_passed": int(tests) if tests else None,
                     "commits": f"{done.group(1)}..{done.group(2)}" if done else None})
    return rows


def trials() -> list[dict]:
    path = REPO / "runs/ledger.jsonl"
    rows = []
    for line in path.read_text().splitlines() if path.exists() else []:
        r = json.loads(line)
        reward = None
        for res in (REPO / "runs").glob(f"**/{r['trial']}/result.json"):
            rewards = (json.loads(res.read_text()).get("verifier_result") or {}).get("rewards") or {}
            reward = rewards.get("reward")
            break
        rows.append({"when": datetime.fromtimestamp(r["time"], tz=timezone.utc).strftime("%Y-%m-%d %H:%M"),
                     "trial": r["trial"], "kind": r.get("kind", "trial"), "pool": r["pool"],
                     "instance": r.get("task") or r["job"].split("--")[0],
                     "run": r.get("condition") or r["job"].split("--")[1], "reward": reward,
                     "usd": round(r["usd"], 4)})
    return rows


# The methodology's 15 tracks: (family, track, stage, branch that builds its realistic tasks).
TRACKS = [
    ("Divide work", "Orchestrate", "Later", None), ("Divide work", "Swarm", "v1", None),
    ("Divide work", "Share a workspace", "Next", None), ("Divide work", "Hand off", "Next", None),
    ("Share knowledge", "Pool", "v1", "feat/pool-real"), ("Share knowledge", "Ask", "Next", "feat/ask-real"),
    ("Share knowledge", "Inspire", "v1", None), ("Share knowledge", "Search together", "Later", None),
    ("Trust each other", "Verify", "Next", "feat/verify-real"), ("Trust each other", "Defer", "Next", None),
    ("Trust each other", "Contain", "Next", None), ("Trust each other", "Keep boundaries", "Next", None),
    ("Handle change", "Adapt", "Next", None), ("Handle change", "Meet a stranger", "Later", None),
    ("Handle change", "Learn as a team", "Later", None),
]
MAIN = "feat/collabbench-v1"


def _realistic(ref: str, track: str) -> list[str]:
    """Realistic task dirs under tasks/<track>/ on a branch (generated instances end in -NNNN and are skipped)."""
    import subprocess
    out = subprocess.run(["git", "-C", str(REPO), "ls-tree", "--name-only", f"{ref}:tasks/{track}"],
                         capture_output=True, text=True)
    return [n for n in out.stdout.split() if not re.search(r"-\d{4}$", n)] if out.returncode == 0 else []


def benchmark(trial_rows: list[dict]) -> list[dict]:
    """One row per realistic task (or per track not yet built): where it stands, its gate, its admission runs."""
    gates, runs = {}, {}
    for r in trial_rows:
        if r["kind"] == "gate" and r["run"] in ("gate-oracle", "gate-nop") and r["reward"] is not None:
            gates[(r["instance"], r["run"])] = r["reward"]  # rows are in time order: the latest wins
        elif r["kind"] != "gate" and r["reward"] is not None:
            runs.setdefault((r["instance"], r["run"]), []).append(r["reward"])
    rows = []
    for family, track, stage, branch in TRACKS:
        key = track.lower().replace(" ", "-")
        merged = _realistic(MAIN, key)
        built = [t for t in _realistic(branch, key) if t not in merged] if branch else []
        worktree = branch and (REPO / ".worktrees" / branch.removeprefix("feat/")).exists()
        tasks = [(t, "in main") for t in merged] + [(t, f"built on {branch}, in review") for t in built]
        if not tasks:
            tasks = [("", "building" if worktree else "not started")]
        for task, status in tasks:
            cal = "; ".join(f"{c} {sum(v) / len(v):.2f} (n={len(v)})"
                            for (i, c), v in sorted(runs.items()) if i == task)
            rows.append({"family": family, "track": track, "stage": stage, "task": task or None,
                         "status": status, "oracle": gates.get((task, "gate-oracle")),
                         "nop": gates.get((task, "gate-nop")), "admission_runs": cal or None})
    return rows


def rulings() -> list[dict]:
    ledger = (WS / "progress.md").read_text() if (WS / "progress.md").exists() else ""
    rows = []
    for i, line in enumerate(l for l in ledger.splitlines() if "Ruling:" in l):
        where, _, text = line.partition("Ruling:")
        rows.append({"n": i + 1, "where": where.strip(" :-") or "Setup", "ruling": clean(text.strip())})
    return rows


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta = [{"label": "Made by", "value": "scripts/progress_snapshot.py in the freedom repository"},
            {"label": "Inputs", "value": "the v1 plan, the execution ledger (.superpowers/sdd), runs/ledger.jsonl"}]
    trial_rows = trials()
    for name, rows in (("tasks", tasks()), ("trials", trial_rows), ("rulings", rulings()),
                       ("benchmark", benchmark(trial_rows))):
        (OUT / f"{name}.json").write_text(json.dumps({"rows": rows, "meta": meta}, indent=1))
        print(OUT / f"{name}.json", file=sys.stderr)


if __name__ == "__main__":
    main()
