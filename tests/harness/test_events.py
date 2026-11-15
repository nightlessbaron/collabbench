import json

import pytest

from collabbench.harness.events import EVENT_TYPES, EventLog


def test_event_types_exact():
    assert EVENT_TYPES == frozenset(
        "llm_call action message wait wake publish import claim release spawn evaluate compaction budget_warning "
        "stopped status deadlock loop error".split())


def test_emit_rejects_unknown_type(tmp_path):
    log = EventLog(tmp_path / "events.jsonl")
    with pytest.raises(ValueError):
        log.emit("agent-0", "telepathy")


def test_emit_writes_jsonl_schema(tmp_path):
    ticks = iter([100.0, 103.5])
    log = EventLog(tmp_path / "events.jsonl", clock=lambda: next(ticks))
    log.emit("agent-0", "action", tokens_in=3, command="ls", exit_code=0)
    lines = (tmp_path / "events.jsonl").read_text().splitlines()
    assert len(lines) == 1
    event = json.loads(lines[0])
    assert set(event) == {"t", "agent", "type", "tokens_in", "tokens_out", "payload"}
    assert event["t"] == 3.5 and event["payload"] == {"command": "ls", "exit_code": 0}
    assert EventLog.read(tmp_path / "events.jsonl") == [event]
