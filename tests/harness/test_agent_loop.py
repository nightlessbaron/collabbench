import json

from collabbench.harness.agent_loop import AgentSpec, run_agent
from collabbench.harness.config import TeamSettings
from collabbench.harness.events import EventLog
from collabbench.harness.llm import LLMUnavailable, ScriptedClient, ToolCall
from tests.harness.fakes import REPORT, FakeServices, LocalEnvironment, call, result


def setup(tmp_path, budget=100_000):
    env, log = LocalEnvironment(tmp_path), EventLog(tmp_path / "ev.jsonl")
    services = FakeServices(env, log)
    services.channel.add("agent-0")
    spec = AgentSpec("agent-0", "You are agent-0.", "Do the task.", budget, "/workspace", False, False)
    return env, log, services, spec


def types(tmp_path):
    return [e["type"] for e in EventLog.read(tmp_path / "ev.jsonl")]


async def test_finish_ends_with_report(tmp_path):
    _, log, services, spec = setup(tmp_path)
    client = ScriptedClient([result(calls=[call("bash", command="echo hi > /workspace/a")]),
                             result(calls=[call("finish", report=REPORT)])])
    out = await run_agent(spec, client, services, log, TeamSettings())
    assert out.status == "finished" and out.report == REPORT and out.turns == 2 and out.tokens == 30
    assert services.reports["agent-0"] == REPORT
    assert (tmp_path / "workspace" / "a").exists()
    assert types(tmp_path) == ["llm_call", "action", "llm_call", "status"]


async def test_unknown_tool_and_bad_json_return_errors(tmp_path):
    _, log, services, spec = setup(tmp_path)

    def second(msgs):
        tool_texts = [m["content"] for m in msgs if m["role"] == "tool"]
        assert "Unknown tool" in tool_texts[0] and "Invalid JSON" in tool_texts[1] and "Missing" in tool_texts[2]
        return result(calls=[call("finish", report=REPORT)])

    client = ScriptedClient([result(calls=[ToolCall("x1", "teleport", {}, "{}"), ToolCall("x2", "bash", None, "{bad"),
                                           ToolCall("x3", "bash", {}, "{}")]), second])
    out = await run_agent(spec, client, services, log, TeamSettings())
    assert out.status == "finished"


async def test_budget_exhausted_honours_finish_only(tmp_path):
    _, log, services, spec = setup(tmp_path, budget=100)
    client = ScriptedClient([result(calls=[call("bash", command="touch /workspace/no"), call("finish", report=REPORT)],
                                    p=60, c=50)])
    out = await run_agent(spec, client, services, log, TeamSettings())
    assert out.status == "finished" and out.report == REPORT
    assert not (tmp_path / "workspace" / "no").exists()


async def test_budget_exhausted_without_finish(tmp_path):
    _, log, services, spec = setup(tmp_path, budget=100)
    client = ScriptedClient([result(calls=[call("bash", command="touch /workspace/no")], p=60, c=50)])
    out = await run_agent(spec, client, services, log, TeamSettings())
    assert out.status == "budget_exhausted" and out.report is None
    assert "stopped" in types(tmp_path)


async def test_warning_injected_at_90_percent(tmp_path):
    _, log, services, spec = setup(tmp_path, budget=1000)

    def second(msgs):
        assert any(m["role"] == "user" and "10%" in m["content"] for m in msgs)
        return result(calls=[call("finish", report=REPORT)])

    client = ScriptedClient([result(calls=[call("bash", command="true")], p=900, c=5), second])
    await run_agent(spec, client, services, log, TeamSettings())
    assert "budget_warning" in types(tmp_path)


async def test_reasoning_not_sent_back(tmp_path):
    _, log, services, spec = setup(tmp_path)

    def second(msgs):
        assert "PRIVATE-CHAIN" not in json.dumps(msgs)
        return result(calls=[call("finish", report=REPORT)])

    client = ScriptedClient([result(calls=[call("bash", command="true")], reasoning="PRIVATE-CHAIN"), second])
    await run_agent(spec, client, services, log, TeamSettings())
    llm_calls = [e for e in EventLog.read(tmp_path / "ev.jsonl") if e["type"] == "llm_call"]
    assert llm_calls[0]["payload"]["reasoning"] == "PRIVATE-CHAIN"


async def test_loop_compacts_past_cap(tmp_path):
    _, log, services, spec = setup(tmp_path)
    steps = [result(calls=[call("bash", command=f"echo {i}")], p=100) for i in range(7)]
    steps.append(result(calls=[call("bash", command="echo big")], p=2000))
    steps.append(result("summary of steps"))  # the compaction call

    def after(msgs):
        assert any(m["role"] == "user" and m["content"].startswith("[Summary of your earlier work]") for m in msgs)
        return result(calls=[call("finish", report=REPORT)])

    steps.append(after)
    out = await run_agent(spec, ScriptedClient(steps), services, log, TeamSettings(context_cap=1000))
    assert out.status == "finished" and "compaction" in types(tmp_path)


async def test_three_silent_replies_stop(tmp_path):
    _, log, services, spec = setup(tmp_path)
    client = ScriptedClient([result("thinking"), result("still thinking"), result("hmm")])
    out = await run_agent(spec, client, services, log, TeamSettings())
    assert out.status == "stopped" and out.turns == 3


async def test_repeated_command_emits_loop(tmp_path):
    _, log, services, spec = setup(tmp_path)
    steps = [result(calls=[call("bash", id=f"r{i}", command="echo x")]) for i in range(5)]
    steps.append(result(calls=[call("finish", report=REPORT)]))
    await run_agent(spec, ScriptedClient(steps), services, log, TeamSettings())
    assert types(tmp_path).count("loop") == 1


async def test_messages_delivered_as_user_message(tmp_path):
    _, log, services, spec = setup(tmp_path)
    services.channel.add("agent-1")

    def first(msgs):
        services.channel.send("agent-1", "agent-0", "hello there")
        return result(calls=[call("bash", command="true")])

    def second(msgs):
        assert msgs[-1] == {"role": "user", "content": "[from agent-1] hello there"}
        return result(calls=[call("finish", report=REPORT)])

    await run_agent(spec, ScriptedClient([first, second]), services, log, TeamSettings())


async def test_stop_event_stops_agent(tmp_path):
    _, log, services, spec = setup(tmp_path)
    services.stop.set()
    out = await run_agent(spec, ScriptedClient([]), services, log, TeamSettings())
    assert out.status == "stopped" and out.turns == 0


async def test_llm_unavailable_marks_error(tmp_path):
    _, log, services, spec = setup(tmp_path)

    def boom(msgs):
        raise LLMUnavailable("gateway down")

    out = await run_agent(spec, ScriptedClient([boom]), services, log, TeamSettings())
    assert out.status == "error" and "error" in types(tmp_path)
