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
        done = re.search(rf"^Task {num}: complete \(commits (\w+)\.\.(\w+), tests: .*?→ (.+?)\)$", ledger, re.M)
        tests = re.search(r"(\d+) passed", done.group(3)).group(1) if done else None
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
    for name, fn in (("tasks", tasks), ("trials", trials), ("rulings", rulings)):
        (OUT / f"{name}.json").write_text(json.dumps({"rows": fn(), "meta": meta}, indent=1))
        print(OUT / f"{name}.json", file=sys.stderr)


if __name__ == "__main__":
    main()
