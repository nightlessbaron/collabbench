"""The generic grader of a graph task (plain Python, standard library only; write_task's emitter ships it as
tests/grade_graph.py and the task's tests/score.py calls `score`).

For each node of the stage:
- propagated score, the reward: the node's output file, read through the frontier harness's read_regular, is compared
  with the reference output, check by check (taskgraph.expand_checks / evaluate); score = the mean of its family scores weighted by each family's declared count (a family's score is the fraction of its items that match). A
  missing, unreadable or malformed file scores 0;
- conditional score, an extra: the reference function is re-run on the agent's OWN parsed upstream outputs and the agent's
  node output compared with that, so a node's error is told apart from what its upstream fed it. A node whose upstream
  output is missing or malformed gets 0, and so does one whose reference function raises on that data. Only parsed
  JSON or CSV data reaches the reference functions; no agent program is ever run.

reward = mean over the stage's nodes of the propagated score. Reported: requirements {node: all checks pass} (grade.py
writes them as req_<node>), extras score_<node>, cond_<node>, fam_<node>_<family> (the family's pass rate) and the totals.

Layout of tests/ (written by kit.emit): grade_graph.py and taskgraph.py here; hidden/graph.json, hidden/config.json
({"stage": S}), hidden/reference.py, hidden/harness.py and hidden/src/ (the sources, as laid out in the workspace).
"""

import importlib.util
import json
import os
import sys
from pathlib import Path

READ_LIMIT = 8 << 20


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def score(workspace: Path, tests: Path | None = None) -> dict:
    tests = Path(tests) if tests else Path(__file__).resolve().parent
    hidden = tests / "hidden"
    if str(tests) not in sys.path:
        sys.path.insert(0, str(tests))
    import taskgraph as tg
    os.environ["COLLAB_WORKSPACE"] = str(workspace)
    harness = _load("collab_harness", hidden / "harness.py")
    harness.setup_work()  # the graded copy of the workspace; every read below goes through it
    g = tg.load_graph(hidden / "graph.json")
    stage = int(json.loads((hidden / "config.json").read_text())["stage"])
    ref = _load("graph_reference", hidden / "reference.py")
    src = hidden / "src"
    names = g.order(stage)
    expected = tg.run_reference(g, ref, src, stage)
    checks = {n: tg.expand_checks(g.nodes[n], tg.keyed(g.nodes[n], expected[n])) for n in names}

    parsed, view = {}, {}
    for n in names:
        node = g.nodes[n]
        try:
            parsed[n] = tg.parse_output(node, harness.read_regular(harness.ws(node["output"]["path"]), READ_LIMIT))
            view[n] = tg.keyed(node, parsed[n])
        except Exception:  # noqa: BLE001 - no file, a link, a directory, malformed: the node scores 0
            parsed.pop(n, None)
            view.pop(n, None)

    prop, cond, fams = {}, {}, {}
    for n in names:
        node, cs = g.nodes[n], checks[n]
        total = len(cs)
        if n not in view:
            prop[n] = cond[n] = 0.0
            continue
        res = tg.evaluate(cs, view[n])
        prop[n] = tg.node_score(node, res)
        fams[n] = {f: p / t for f, (p, t) in res["families"].items()}
        ups = g.upstream_nodes(n)
        if any(u not in parsed for u in ups):
            cond[n] = 0.0
            continue
        try:
            alt = tg.roundtrip(node, getattr(ref, f"node_{n}")({u: parsed[u] for u in ups}, src))
            cond[n] = tg.node_score(node, tg.evaluate(cs, view[n], against=tg.keyed(node, alt)))
        except Exception:  # noqa: BLE001 - the reference cannot run on what the team fed it
            cond[n] = 0.0
    reward = sum(prop.values()) / len(names)
    extras = {"stage": float(stage), "nodes": float(len(names)), "checks_total": float(sum(map(len, checks.values()))),
              "cond_reward": sum(cond.values()) / len(names)}
    for n in names:
        extras[f"score_{n}"], extras[f"cond_{n}"] = prop[n], cond[n]
        for f, rate in fams.get(n, {}).items():
            extras[f"fam_{n}_{f}"] = rate
    return {"reward": reward, "requirements": {n: prop[n] >= 1.0 for n in names}, "extras": extras}
