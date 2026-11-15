"""`collabbench gen | run | gate | metrics`."""

import argparse
import sys
from pathlib import Path

from collabbench import settings


def parse_seeds(text: str) -> list[int]:
    out: list[int] = []
    for part in text.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            out += list(range(int(lo), int(hi) + 1))
        else:
            out.append(int(part))
    return out


def _gen(a) -> None:
    out = Path(a.out or settings.REPO / "tasks" / a.track)
    if a.track == "pool":
        from collabbench.tracks.pool.generator import generate
        dirs = [generate(s, out) for s in parse_seeds(a.seeds)]
    elif a.track == "swarm":
        from collabbench.tracks.swarm.generator import generate
        dirs = [generate(s, out) for s in parse_seeds(a.seeds)]
    else:
        from collabbench.tracks.inspire.generator import generate_all
        dirs = generate_all(out)
    for d in dirs:
        print(d)


def _run(a) -> None:
    from collabbench.runner.grid import load_grid
    from collabbench.runner.harbor import run_cell
    from collabbench.runner.ledger import BudgetExceeded, Ledger
    grid = load_grid(Path(a.grid))
    ledger = Ledger(settings.REPO / "runs" / "ledger.jsonl")
    cells = [c for c in grid.cells() if not a.only or any(s in f"{c.task_dir.name}/{c.condition}" for s in a.only)]
    for i, cell in enumerate(cells, 1):
        try:
            trials = run_cell(cell, grid, ledger, settings.REPO / "runs")
        except BudgetExceeded as e:
            print(f"stopping: {e}", file=sys.stderr)
            return
        print(f"[{i}/{len(cells)}] {cell.task_dir.name} {cell.condition}: {len(trials)} trials; "
              f"spent personal ${ledger.spent('personal'):.2f}, ifm ${ledger.spent('ifm'):.2f}")


def _gate(a) -> None:
    from collabbench.runner.gates import gate_instance
    for d in a.tasks:
        report = gate_instance(Path(d), a.pool)
        print(f"{'PASS' if report.passed else 'FAIL'} {report.task}: {report}")


def _metrics(a) -> None:
    from collabbench.metrics.profile import build_profile, write_profile
    from collabbench.metrics.trial import load_trials
    records = load_trials(Path(a.runs))
    write_profile(build_profile(records, settings.REPO / "tasks"), Path(a.out))


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="collabbench")
    sub = p.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen")
    g.add_argument("track", choices=["pool", "swarm", "inspire"])
    g.add_argument("--seeds", default="1-6")
    g.add_argument("--out")
    g.set_defaults(fn=_gen)
    r = sub.add_parser("run")
    r.add_argument("grid")
    r.add_argument("--only", nargs="*", help="substrings of '<instance>/<condition>' to run")
    r.set_defaults(fn=_run)
    t = sub.add_parser("gate")
    t.add_argument("tasks", nargs="+")
    t.add_argument("--pool", default="personal")
    t.set_defaults(fn=_gate)
    m = sub.add_parser("metrics")
    m.add_argument("runs")
    m.add_argument("--out", required=True)
    m.set_defaults(fn=_metrics)
    a = p.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
