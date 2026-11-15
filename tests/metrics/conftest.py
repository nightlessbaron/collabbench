import json
from pathlib import Path

import pytest


def ev(agent, type, t=0.0, tokens_in=0, tokens_out=0, **payload):
    return {"t": t, "agent": agent, "type": type, "tokens_in": tokens_in, "tokens_out": tokens_out,
            "payload": payload}


@pytest.fixture
def make_trial(tmp_path):
    """Build `<runs>/<instance>--<condition>--<stamp>/<trial>/` the way Harbor and the harness lay it out."""
    def make(instance="pool-0001", condition="team", trial="t1", reward=1.0, requirements=None, extras=None,
             events=(), trace=(), report=None, status="finished", tokens=(100, 20), runs=None, outcome=True):
        runs = Path(runs or tmp_path / "runs")
        job = runs / f"{instance}--{condition}--20261115-020727"
        d = job / trial
        (d / "verifier").mkdir(parents=True)
        (d / "agent" / "collab").mkdir(parents=True)
        (job / "result.json").write_text("{}")
        (d / "result.json").write_text(json.dumps({"agent_execution": {
            "started_at": "2026-11-15T02:07:31.000000Z", "finished_at": "2026-11-15T02:09:31.500000Z"}}))
        if reward is not None:
            rj = {"reward": reward, **{f"req_{k}": int(v) for k, v in (requirements or {}).items()},
                  "unauthorized": 0, **(extras or {})}
            (d / "verifier" / "reward.json").write_text(json.dumps(rj))
        (d / "verifier" / "details.json").write_text(json.dumps({"final": {}, "trace": list(trace)}))
        (d / "agent" / "collab" / "events.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events))
        if outcome:
            (d / "agent" / "collab" / "outcome.json").write_text(json.dumps({
                "status": status, "report": report, "tokens_in": tokens[0], "tokens_out": tokens[1]}))
        return runs
    return make
