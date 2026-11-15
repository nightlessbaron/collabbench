import asyncio
import json

import httpx
import pytest

from collabbench.harness import llm
from collabbench.harness.llm import ChatResult, LLMError, LLMUnavailable, OpenAIChatClient, ScriptedClient, ToolCall


def ok_body(message: dict, usage=(10, 5), finish="tool_calls") -> dict:
    return {"choices": [{"index": 0, "message": {"role": "assistant", **message}, "finish_reason": finish}],
            "usage": {"prompt_tokens": usage[0], "completion_tokens": usage[1]}}


def client(handler, *, resolve=lambda: "http://gw/v1", window=5.0, effort="high"):
    http = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return OpenAIChatClient(resolve, "sk-test", "m", effort, retry_window_s=window, http_client=http, backoff_s=0.01)


TOOL = {"id": "c1", "type": "function", "function": {"name": "bash", "arguments": '{"command": "ls"}'}}


async def test_parses_tool_calls_and_usage():
    c = client(lambda req: httpx.Response(200, json=ok_body({"content": "", "reasoning": "think", "tool_calls": [TOOL]})))
    r = await c.chat([{"role": "user", "content": "hi"}], [])
    assert r.tool_calls == [ToolCall("c1", "bash", {"command": "ls"}, '{"command": "ls"}')]
    assert (r.reasoning, r.prompt_tokens, r.completion_tokens, r.finish_reason) == ("think", 10, 5, "tool_calls")


async def test_reasoning_content_fallback():
    c = client(lambda req: httpx.Response(200, json=ok_body({"content": "x", "reasoning_content": "rc"}, finish="stop")))
    r = await c.chat([], [])
    assert r.reasoning == "rc" and r.tool_calls == [] and r.content == "x"


async def test_bad_json_arguments_kept_raw():
    bad = {"id": "c2", "type": "function", "function": {"name": "bash", "arguments": '{"command": "ls"'}}
    not_obj = {"id": "c3", "type": "function", "function": {"name": "bash", "arguments": '"ls"'}}
    c = client(lambda req: httpx.Response(200, json=ok_body({"content": "", "tool_calls": [bad, not_obj]})))
    r = await c.chat([], [])
    assert r.tool_calls[0].arguments is None and r.tool_calls[0].raw == '{"command": "ls"'
    assert r.tool_calls[1].arguments is None


async def test_retries_5xx_then_succeeds():
    statuses = iter([502, 429, 200])

    def handler(req):
        s = next(statuses)
        return httpx.Response(s, json=ok_body({"content": "done"}, finish="stop") if s == 200 else {"error": "x"})

    r = await client(handler).chat([], [])
    assert r.content == "done"


async def test_reresolves_url_after_connect_error():
    urls = iter(["http://dead/v1", "http://live/v1"])
    calls = []

    def resolve():
        calls.append(1)
        return next(urls)

    def handler(req):
        if req.url.host == "dead":
            raise httpx.ConnectError("refused", request=req)
        return httpx.Response(200, json=ok_body({"content": "ok"}, finish="stop"))

    r = await client(handler, resolve=resolve).chat([], [])
    assert r.content == "ok" and len(calls) == 2


async def test_gives_up_after_window():
    c = client(lambda req: httpx.Response(503, json={"error": "busy"}), window=0.5)
    with pytest.raises(LLMUnavailable):
        await c.chat([], [])


async def test_400_raises_without_retry():
    seen = []

    def handler(req):
        seen.append(1)
        return httpx.Response(400, json={"error": "context too long"})

    with pytest.raises(LLMError):
        await client(handler).chat([], [])
    assert len(seen) == 1


async def test_effort_sent_in_body():
    bodies = []

    def handler(req):
        bodies.append(json.loads(req.content))
        assert req.headers["authorization"] == "Bearer sk-test"
        return httpx.Response(200, json=ok_body({"content": "ok"}, finish="stop"))

    tools = [{"type": "function", "function": {"name": "bash", "parameters": {"type": "object"}}}]
    await client(handler).chat([{"role": "user", "content": "hi"}], tools)
    assert bodies[0]["reasoning_effort"] == "high" and bodies[0]["model"] == "m" and bodies[0]["tools"] == tools
    bodies.clear()
    await client(handler, effort=None).chat([], [])
    assert "reasoning_effort" not in bodies[0] and "tools" not in bodies[0]


async def test_inflight_cap(monkeypatch):
    monkeypatch.setenv("COLLAB_LLM_MAX_INFLIGHT", "2")
    llm._SEMAPHORES.clear()
    live, peak = 0, 0

    async def handler(req):
        nonlocal live, peak
        live += 1
        peak = max(peak, live)
        await asyncio.sleep(0.02)
        live -= 1
        return httpx.Response(200, json=ok_body({"content": "ok"}, finish="stop"))

    c = client(handler)
    await asyncio.gather(*(c.chat([], []) for _ in range(6)))
    assert peak == 2
    llm._SEMAPHORES.clear()


def test_as_message_omits_reasoning():
    r = ChatResult("text", "secret thoughts", [ToolCall("c1", "bash", {"command": "ls"}, '{"command": "ls"}')], 1, 1,
                   "tool_calls")
    m = r.as_message()
    assert m == {"role": "assistant", "content": "text", "tool_calls": [
        {"id": "c1", "type": "function", "function": {"name": "bash", "arguments": '{"command": "ls"}'}}]}
    assert "secret" not in json.dumps(m)


async def test_scripted_client_records_calls_and_runs_out():
    done = ChatResult("a", "", [], 1, 1, "stop")
    s = ScriptedClient([done, lambda msgs: ChatResult(str(len(msgs)), "", [], 1, 1, "stop")])
    assert (await s.chat([{"role": "user", "content": "x"}], [])).content == "a"
    assert (await s.chat([{}, {}], [])).content == "2"
    assert len(s.calls) == 2
    with pytest.raises(AssertionError):
        await s.chat([], [])


@pytest.mark.live
async def test_live_gateway_returns_tool_call():
    from collabbench import settings
    c = OpenAIChatClient(settings.gateway_url, settings.gateway_key(), settings.MODEL, "low")
    tools = [{"type": "function", "function": {"name": "bash", "description": "Run a shell command",
              "parameters": {"type": "object", "properties": {"command": {"type": "string"}},
                             "required": ["command"]}}}]
    r = await c.chat([{"role": "user", "content": "List /tmp using the bash tool."}], tools)
    assert r.tool_calls and r.tool_calls[0].name == "bash"
