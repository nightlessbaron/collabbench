import json
import subprocess
import time

import pytest
from harbor.models.agent.context import AgentContext

from collabbench.harness.config import TeamSettings
from collabbench.harness.events import EventLog
from collabbench.harness.llm import OpenAIChatClient, ScriptedClient
from collabbench.harness.sandbox import Private
from collabbench.harness.team import Team, TeamAgent
from tests.harness.fakes import REPORT, LocalEnvironment, call, result
from tests.harness.test_sandbox import git_workspace, write_private

BRIEF = "Implement the codec. Requirements: R1, R2. Do not run scripts/release.sh."


def tool_texts(msgs):
    return [m["content"] for m in msgs if m["role"] == "tool"]


def private(roles=("alpha", "beta"), **manifest):
    return Private(list(roles), {r: f"{r} secret notes" for r in roles}, {r: f"{r} placebo notes" for r in roles},
                   {"roles": list(roles), "workspace": "shared", **manifest})


async def run_team(tmp_path, scripts: dict, settings: TeamSettings, priv: Private | None = None, git=False,
                   simulators=None):
    env = LocalEnvironment(tmp_path / "box")
    if git:
        git_workspace(env.root)
    clients = {name: ScriptedClient(steps) for name, steps in scripts.items()}
    team = Team(settings, env, lambda name: clients[name], tmp_path / "logs", priv or private(), BRIEF,
                simulators=simulators)
    outcome = await team.run()
    return env, team, outcome


def finish_if(check):
    def step(msgs):
        check(msgs)
        return result(calls=[call("finish", report=REPORT)])
    return step


async def test_report_is_agent0s(tmp_path):
    r1 = {"done": False, "requirements": {"R1": "not_met"}, "notes": "b"}
    _, _, out = await run_team(tmp_path, {"agent-0": [result(calls=[call("finish", report=REPORT)])],
                                          "agent-1": [result(calls=[call("finish", report=r1)])]},
                               TeamSettings(team_size=2))
    assert out["report"]["requirements"] == REPORT["requirements"] and out["status"] == "finished"
    assert {a["status"] for a in out["agents"].values()} == {"finished"}


async def test_facts_private_and_shared(tmp_path):
    def only(role, other):
        return finish_if(lambda m: (f"{role} secret notes" in m[1]["content"] and f"{other} secret" not in
                                    m[1]["content"] and BRIEF in m[1]["content"]) or pytest.fail(m[1]["content"]))

    await run_team(tmp_path / "p", {"agent-0": [only("alpha", "beta")], "agent-1": [only("beta", "alpha")]},
                   TeamSettings(team_size=2))


async def test_facts_shared_merges_roles(tmp_path):
    def both(m):
        text = m[1]["content"]
        assert "## Notes from alpha" in text and "## Notes from beta" in text and "beta secret notes" in text

    await run_team(tmp_path, {"agent-0": [finish_if(both)]}, TeamSettings(team_size=1, facts="shared"))


async def test_placebo_replaces_role_text(tmp_path):
    def placebo(m):
        assert "beta placebo notes" in m[1]["content"] and "beta secret" not in m[1]["content"]

    await run_team(tmp_path, {"agent-0": [finish_if(lambda m: None)], "agent-1": [finish_if(placebo)]},
                   TeamSettings(team_size=2, placebo="beta"))


async def test_lead_spawn_creates_worktree_and_hides_brief(tmp_path):
    def w1_first(msgs):
        assert msgs[1]["content"] == "Migrate module A." and BRIEF not in json.dumps(msgs)
        return result(calls=[call("bash", command="git branch --show-current")])

    def w1_second(msgs):
        assert "w1" in tool_texts(msgs)[-1]
        return result(calls=[call("send", to="lead", text="module A done"), call("finish", report=REPORT)])

    def lead_last(msgs):
        assert "module A done" in json.dumps(msgs)
        return result(calls=[call("finish", report=REPORT)])

    env, _, out = await run_team(
        tmp_path, {"lead": [result(calls=[call("spawn", name="w1", instructions="Migrate module A.")]),
                            result(calls=[call("wait", timeout_s=10)]), lead_last],
                   "w1": [w1_first, w1_second]},
        TeamSettings(team_size=2, topology="lead", workspace="worktrees"), priv=private(roles=()), git=True)
    assert (env.root / "work" / "w1").is_dir()
    assert out["agents"]["w1"]["status"] == "finished" and out["status"] == "finished"
    assert "spawn" in [e["type"] for e in EventLog.read(tmp_path / "logs" / "collab" / "events.jsonl")]


async def test_spawn_limit_is_team_size_minus_one(tmp_path):
    def check(msgs):
        texts = tool_texts(msgs)
        assert texts[0].startswith("Started w1") and "limit" in texts[1]
        return result(calls=[call("finish", report=REPORT)])

    await run_team(tmp_path, {"lead": [result(calls=[call("spawn", name="w1", instructions="a"),
                                                    call("spawn", name="w2", instructions="b")]), check],
                              "w1": [result(calls=[call("finish", report=REPORT)])]},
                   TeamSettings(team_size=2, topology="lead", workspace="worktrees"), priv=private(roles=()),
                   git=True)


async def test_isolated_assembly_copies_owned_files_only(tmp_path):
    priv = private(owners={"alpha": ["encoder.py"], "beta": ["decoder.py"]})
    env, _, _ = await run_team(
        tmp_path, {"agent-0": [result(calls=[call("bash", command="echo A > encoder.py; echo A > decoder.py")]),
                               result(calls=[call("finish", report=REPORT)])],
                   "agent-1": [result(calls=[call("bash", command="echo B > decoder.py; echo B > encoder.py")]),
                               result(calls=[call("finish", report=REPORT)])]},
        TeamSettings(team_size=2, channel="closed", workspace="isolated"), priv=priv)
    ws = env.root / "workspace"
    assert (ws / "encoder.py").read_text() == "A\n" and (ws / "decoder.py").read_text() == "B\n"


async def test_finish_waits_for_teammate_then_cancels(tmp_path):
    start = time.monotonic()
    env, _, out = await run_team(
        tmp_path, {"agent-0": [result(calls=[call("finish", report=REPORT)])],
                   "agent-1": [result(calls=[call("bash", command="sleep 30", timeout_s=60)])]},
        TeamSettings(team_size=2, idle_grace_s=1))
    assert time.monotonic() - start < 6
    assert out["agents"]["agent-1"]["status"] == "stopped" and out["status"] == "finished"
    index = json.loads((env.root / "snapshots" / "index.json").read_text())
    assert index[-1]["reason"] == "final" and index[-1]["t"] >= 1.0


async def test_snapshot_index_written(tmp_path):
    env, _, _ = await run_team(tmp_path, {"agent-0": [result(calls=[call("bash", command="echo hi > a.txt")]),
                                                      result(calls=[call("finish", report=REPORT)])]},
                               TeamSettings())
    index = json.loads((env.root / "snapshots" / "index.json").read_text())
    assert [e["reason"] for e in index] == ["status:agent-0", "final"]
    assert all((env.root / "snapshots" / e["file"]).exists() for e in index)


async def test_outcome_files_written(tmp_path):
    await run_team(tmp_path, {"agent-0": [result(calls=[call("finish", report=REPORT)], p=40, c=2)]}, TeamSettings())
    collab = tmp_path / "logs" / "collab"
    outcome = json.loads((collab / "outcome.json").read_text())
    assert outcome["tokens_in"] == 40 and outcome["tokens_out"] == 2 and outcome["settings"]["team_size"] == 1
    assert json.loads((collab / "transcripts" / "agent-0.json").read_text())[0]["role"] == "system"


class StubSim:
    def validate(self, plan, params):
        return None if "w" in plan else "missing w"

    def objective(self, plan, params, noise_seed=None):
        return plan["w"][0]

    def optimum(self, params):
        return {"w": [1.0, 0.0]}

    def baseline(self, params):
        return {"w": [0.0, 1.0]}


async def test_evaluate_cap_shared(tmp_path):
    priv = private(roles=("solver", "expert"), evaluate={"concept": "stub", "params": {}, "train_noise_seed": 3})

    def check(msgs):
        texts = tool_texts(msgs)
        assert "0.500" in texts[1] and "0.500" in texts[2] and "used up" in texts[3]
        return result(calls=[call("finish", report=REPORT)])

    await run_team(tmp_path, {"agent-0": [result(calls=[call("bash", command="echo '{\"w\": [0.5, 0.5]}' > plan.json"),
                                                       call("evaluate"), call("evaluate"), call("evaluate")]),
                                          check]},
                   TeamSettings(evaluate_cap=2), priv=priv, simulators={"stub": StubSim()})


def make_agent(tmp_path, **kw):
    return TeamAgent(logs_dir=tmp_path / "logs", model_name="deepseek-v4-1-flash-1017", **kw)


async def test_private_dir_removed_before_first_command(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    write_private(env.root)
    agent = make_agent(tmp_path)
    await agent.setup(env)

    def check(msgs):
        assert "No such file" in tool_texts(msgs)[0]
        return result(calls=[call("finish", report=REPORT)])

    scripted = ScriptedClient([result(calls=[call("bash", command="ls /opt/collab/private")]), check])
    agent.client_factory = lambda name: scripted
    ctx = AgentContext()
    await agent.run(BRIEF, env, ctx)
    assert ctx.metadata["status"] == "finished" and ctx.n_input_tokens == 20


async def test_key_never_written(tmp_path, monkeypatch):
    monkeypatch.setenv("COLLAB_LLM_API_KEY", "sk-LEAKCHECK")
    monkeypatch.setenv("COLLAB_LLM_BASE_URL", "http://unused/v1")
    env = LocalEnvironment(tmp_path / "box")
    write_private(env.root)
    agent = make_agent(tmp_path, team_size="2")
    assert isinstance(agent._make_client_factory()("agent-0"), OpenAIChatClient)
    await agent.setup(env)
    clients = {n: ScriptedClient([result(calls=[call("bash", command="env | sort | head -50; echo $COLLAB_LLM_API_KEY")]),
                                  result(calls=[call("finish", report=REPORT)])]) for n in ("agent-0", "agent-1")}
    agent.client_factory = lambda name: clients[name]
    ctx = AgentContext()
    await agent.run(BRIEF, env, ctx)
    assert "sk-LEAKCHECK" not in json.dumps(ctx.metadata)
    leaks = [str(f) for f in tmp_path.rglob("*") if f.is_file() and b"sk-LEAKCHECK" in f.read_bytes()]
    assert leaks == []


async def test_probe_records_private_and_parallel_exec(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    write_private(env.root)
    agent = make_agent(tmp_path, probe="true")
    await agent.setup(env)
    ctx = AgentContext()
    await agent.run(BRIEF, env, ctx)
    assert ctx.metadata["probe"]["private_exists"] is False
    assert ctx.metadata["probe"]["parallel_exec_s"] < 6


def test_team_agent_rejects_bad_settings(tmp_path):
    with pytest.raises(ValueError):
        make_agent(tmp_path, topology="lead")
