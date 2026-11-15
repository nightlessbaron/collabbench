from collabbench.harness.compaction import compact
from collabbench.harness.llm import ScriptedClient
from tests.harness.fakes import result


def history(turns: int) -> list[dict]:
    msgs = [{"role": "system", "content": "sys"}, {"role": "user", "content": "brief"}]
    for i in range(turns):
        msgs.append({"role": "assistant", "content": "", "tool_calls": [
            {"id": f"t{i}a", "type": "function", "function": {"name": "bash", "arguments": "{}"}},
            {"id": f"t{i}b", "type": "function", "function": {"name": "bash", "arguments": "{}"}}]})
        msgs.append({"role": "tool", "tool_call_id": f"t{i}a", "content": f"out {i}a"})
        msgs.append({"role": "tool", "tool_call_id": f"t{i}b", "content": f"out {i}b"})
        if i % 3 == 0:
            msgs.append({"role": "user", "content": f"[from agent-1] note {i}"})
    return msgs


def assert_pairs(msgs):
    open_ids: set[str] = set()
    for m in msgs:
        if m["role"] == "assistant":
            open_ids = {c["id"] for c in m.get("tool_calls", [])}
        elif m["role"] == "tool":
            assert m["tool_call_id"] in open_ids, m


async def test_compaction_keeps_tool_pairs():
    client = ScriptedClient([result("did steps 0-3")])
    msgs, res = await compact(history(10), client, keep_last_turns=6)
    assert msgs[0]["content"] == "sys" and msgs[1]["content"] == "brief"
    assert msgs[2]["role"] == "user" and msgs[2]["content"].startswith("[Summary of your earlier work]")
    assert "did steps 0-3" in msgs[2]["content"]
    assert sum(m["role"] == "assistant" for m in msgs) == 6
    assert_pairs(msgs)
    assert res.content == "did steps 0-3"
    assert "out 0a" in client.calls[0][-1]["content"]  # the summarizer saw the dropped turns


async def test_compaction_noop_when_short():
    client = ScriptedClient([])
    msgs, res = await compact(history(4), client, keep_last_turns=6)
    assert msgs == history(4) and res is None
