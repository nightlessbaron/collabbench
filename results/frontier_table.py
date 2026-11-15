"""Frontier-model results -> markdown table spliced into README.md between the FRONTIER markers.

python3 -I frontier_table.py <runs_dir> <README.md>
Reads runs/<prefix>*/<job>/<trial>/result.json (Harbor) and agent/collab/events.jsonl (tokens) for the frontier grids.
"""
import json
import sys
from pathlib import Path

MODELS = {"opus55": "Claude Opus 5.5", "gpt61sol": "GPT-6.1 sol (high)"}
TASKS = ["aldol-s4", "cohort-s4", "fiscal-s4", "poe-s1"]
COND = {"solo": "one agent", "team_k3": "team of three"}
START, END = "<!-- FRONTIER:START -->", "<!-- FRONTIER:END -->"


def trials(runs: Path):
    for prefix, label in MODELS.items():
        for grid in sorted(runs.glob(f"{prefix}*")):
            for job in grid.glob("*--*--*"):
                if not job.is_dir():
                    continue
                task, cond = job.name.split("--")[:2]
                for t in job.glob(f"{task}__*"):
                    r, ev = t / "result.json", t / "agent" / "collab" / "events.jsonl"
                    if not r.exists():
                        yield label, task, cond, None
                        continue
                    res = json.loads(r.read_text())
                    rw = (res.get("verifier_result") or {}).get("rewards") or {}
                    tok, last_t, agents = 0, 0.0, set()
                    if ev.exists():
                        for line in ev.open():
                            try:
                                e = json.loads(line)
                            except ValueError:
                                continue
                            tok += (e.get("tokens_in") or 0) + (e.get("tokens_out") or 0)
                            last_t = max(last_t, e.get("t") or 0.0)
                            agents.add(e.get("agent"))
                    miss = sorted(k[4:] for k, v in rw.items() if k.startswith("req_") and not v)
                    nreq = sum(1 for k in rw if k.startswith("req_"))
                    yield label, task, cond, {"r": rw.get("reward"), "tok": tok, "min": last_t / 60,
                                              "agents": len(agents - {None}), "miss": miss, "nreq": nreq}


def main():
    runs, readme = Path(sys.argv[1]), Path(sys.argv[2])
    cells = {}
    for label, task, cond, x in trials(runs):
        cells.setdefault((label, task, cond), []).append(x)
    rows = ["| Model | Task | Setup | Reward | All nodes correct? | Tokens | Minutes | Agents active | Nodes not fully correct |", "|---|---|---|---|---|---|---|---|---|"]
    for label in MODELS.values():
        for task in TASKS:
            for cond, cname in COND.items():
                for x in cells.get((label, task, cond), []):
                    if x is None:
                        rows.append(f"| {label} | {task} | {cname} | *running* | | | | | |")
                    else:
                        r = "error" if x["r"] is None else f"{x['r']:.3f}"
                        ok = "yes" if not x["miss"] and x["nreq"] else "no"
                        rows.append(f"| {label} | {task} | {cname} | **{r}** | {ok} | {x['tok']/1e6:.2f}M | {x['min']:.0f} | "
                                    f"{x['agents']} | {len(x['miss'])} of {x['nreq']}: {', '.join(x['miss']) or 'none'} |")
    block = f"{START}\n" + "\n".join(rows) + f"\n{END}"
    text = readme.read_text()
    if START in text:
        text = text[:text.index(START)] + block + text[text.index(END) + len(END):]
    readme.write_text(text)
    print("\n".join(rows))


if __name__ == "__main__":
    main()
