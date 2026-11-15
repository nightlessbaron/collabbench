import time

from collabbench.harness.events import EventLog
from collabbench.harness.tools import run_command, tool_specs, truncate_output
from tests.harness.fakes import LocalEnvironment


def names(specs):
    return {s["function"]["name"] for s in specs}


def test_truncate_marks_cut():
    text = "a" * 12000 + "b" * 10000 + "c" * 8000
    out = truncate_output(text)
    assert out.startswith("a" * 12000) and out.endswith("c" * 8000)
    assert "[... 10000 characters cut ...]" in out and "b" not in out


def test_short_output_untouched():
    assert truncate_output("hello") == "hello"


def test_tool_specs_hide_channel_tools_when_closed():
    closed = names(tool_specs(channel_open=False, can_spawn=False, can_evaluate=False))
    assert closed == {"bash", "claim", "release", "finish"}
    full = names(tool_specs(channel_open=True, can_spawn=True, can_evaluate=True))
    assert full == {"bash", "send", "wait", "publish", "read_finding", "claim", "release", "spawn", "evaluate", "finish"}


def test_finish_schema_has_report_fields():
    spec = next(s for s in tool_specs(channel_open=True, can_spawn=False, can_evaluate=False)
                if s["function"]["name"] == "finish")
    report = spec["function"]["parameters"]["properties"]["report"]
    assert set(report["properties"]) == {"done", "requirements", "notes"}
    assert report["properties"]["requirements"]["additionalProperties"]["enum"] == ["met", "not_met", "unsure"]


async def test_local_env_rewrites_paths(tmp_path):
    env = LocalEnvironment(tmp_path)
    r = await env.exec("echo hi > /workspace/x.txt && cat /workspace/x.txt")
    assert r.stdout == "hi\n" and (tmp_path / "workspace" / "x.txt").exists()


async def test_bash_exit_code_and_action_event(tmp_path):
    env, log = LocalEnvironment(tmp_path), EventLog(tmp_path / "ev.jsonl")
    out = await run_command(env, log, "agent-0", "echo out; echo err >&2; exit 3", 30, "/workspace")
    assert out.startswith("[exit 3]") and "out" in out and "err" in out
    ev = EventLog.read(tmp_path / "ev.jsonl")[0]
    assert ev["type"] == "action" and ev["payload"]["exit_code"] == 3 and ev["payload"]["cwd"] == "/workspace"


async def test_bash_timeout_returns_notice(tmp_path):
    env, log = LocalEnvironment(tmp_path), EventLog(tmp_path / "ev.jsonl")
    start = time.monotonic()
    out = await run_command(env, log, "agent-0", "echo before; sleep 5", 1, "/workspace")
    assert time.monotonic() - start < 3
    assert "timed out" in out and "before" in out
    assert EventLog.read(tmp_path / "ev.jsonl")[0]["payload"]["timed_out"] is True
