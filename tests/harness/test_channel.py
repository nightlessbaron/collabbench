import asyncio

from collabbench.harness.channel import Channel
from collabbench.harness.events import EventLog


def make(tmp_path, agents=("agent-0", "agent-1"), open=True):
    log = EventLog(tmp_path / "events.jsonl")
    ch = Channel(log, open=open)
    for a in agents:
        ch.add(a)
    return ch, log


def events(tmp_path, type_):
    return [e for e in EventLog.read(tmp_path / "events.jsonl") if e["type"] == type_]


def test_send_all_reaches_everyone_but_sender(tmp_path):
    ch, _ = make(tmp_path, ("a", "b", "c"))
    ch.send("a", "all", "hello")
    assert ch.drain("b") == [("a", "hello")] and ch.drain("c") == [("a", "hello")] and ch.drain("a") == []
    assert events(tmp_path, "message")[0]["payload"]["to"] == "all"


def test_send_unknown_recipient_lists_agents(tmp_path):
    ch, _ = make(tmp_path)
    reply = ch.send("agent-0", "agent-9", "hi")
    assert "agent-9" in reply and "agent-1" in reply
    assert ch.drain("agent-1") == []


async def test_wait_returns_on_message(tmp_path):
    ch, _ = make(tmp_path)
    task = asyncio.create_task(ch.wait("agent-1", 5))
    await asyncio.sleep(0.01)
    ch.send("agent-0", "agent-1", "go")
    got = await asyncio.wait_for(task, 0.1)
    assert got == [("agent-0", "go")]


async def test_wait_returns_pending_immediately(tmp_path):
    ch, _ = make(tmp_path)
    ch.send("agent-0", "agent-1", "early")
    assert await asyncio.wait_for(ch.wait("agent-1", 5), 0.1) == [("agent-0", "early")]


async def test_wait_times_out_empty(tmp_path):
    ch, _ = make(tmp_path)
    assert await ch.wait("agent-0", 0.05) == []


async def test_deadlock_notice_then_end(tmp_path):
    ch, _ = make(tmp_path)
    first = await asyncio.gather(ch.wait("agent-0", 5), ch.wait("agent-1", 5))
    assert first == [[("harness", Channel.NOTICE)]] * 2
    assert not ch.ended
    second = await asyncio.gather(ch.wait("agent-0", 5), ch.wait("agent-1", 5))
    assert second == [[], []] and ch.ended
    assert [e["payload"]["final"] for e in events(tmp_path, "deadlock")] == [False, True]


async def test_remove_last_non_waiter_triggers_deadlock(tmp_path):
    ch, _ = make(tmp_path)
    task = asyncio.create_task(ch.wait("agent-1", 5))
    await asyncio.sleep(0.01)
    ch.remove("agent-0")  # agent-0 finished; agent-1 now waits for nobody
    assert await asyncio.wait_for(task, 0.1) == [("harness", Channel.NOTICE)]


def test_claim_conflict_reports_owner(tmp_path):
    ch, _ = make(tmp_path)
    assert "claimed" in ch.claim("agent-0", "billing.py")
    reply = ch.claim("agent-1", "billing.py")
    assert "agent-0" in reply
    assert ch.claims() == {"billing.py": "agent-0"}
    assert "not" in ch.release("agent-1", "billing.py")
    ch.release("agent-0", "billing.py")
    assert ch.claims() == {}
    assert [e["type"] for e in EventLog.read(tmp_path / "events.jsonl")] == ["claim", "release"]


def test_publish_and_read_finding(tmp_path):
    ch, _ = make(tmp_path)
    fid = ch.publish("agent-0", "CRC poly", "poly=0x1D")
    inbox = ch.drain("agent-1")
    assert len(inbox) == 1 and "CRC poly" in inbox[0][1] and str(fid) in inbox[0][1]
    assert ch.read_finding("agent-1", fid) == "poly=0x1D"
    assert "no finding" in ch.read_finding("agent-1", 99)
    imp = events(tmp_path, "import")
    assert imp[0]["agent"] == "agent-1" and imp[0]["payload"]["author"] == "agent-0"


def test_closed_channel_send_errors(tmp_path):
    ch, _ = make(tmp_path, open=False)
    reply = ch.send("agent-0", "agent-1", "hi")
    assert "closed" in reply
    assert ch.drain("agent-1") == []
