"""Model clients behind one interface (`ChatClient`).

`OpenAIChatClient` speaks the OpenAI chat-completions wire format over httpx: the Comet gateway (DeepSeek) and GPT
models use it as is. An Anthropic Messages adapter is added behind the same interface when evaluation moves to Claude.

Retries: connection errors, 429 and 5xx back off exponentially within a time window; after a connection error the base
URL is resolved again, because Comet's gateway moves when its service job is preempted. Other 4xx errors raise
`LLMError` at once. All clients in a process share one in-flight cap per event loop (`COLLAB_LLM_MAX_INFLIGHT`).
The API key is sent in a header only and never appears in a result, an error or a log line.
"""

import asyncio
import json
import os
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Protocol

import httpx


class LLMError(Exception):
    """A request the model API rejected (not worth retrying)."""


class LLMUnavailable(Exception):
    """The API stayed unreachable or overloaded for the whole retry window."""


@dataclass(frozen=True)
class ToolCall:
    id: str
    name: str
    arguments: dict | None  # None when `raw` is not a JSON object
    raw: str


@dataclass
class ChatResult:
    content: str
    reasoning: str
    tool_calls: list[ToolCall] = field(default_factory=list)
    prompt_tokens: int = 0
    completion_tokens: int = 0
    finish_reason: str = ""

    def as_message(self) -> dict:
        """The assistant message to keep in history. Reasoning is never sent back."""
        msg: dict = {"role": "assistant", "content": self.content or ""}
        if self.tool_calls:
            msg["tool_calls"] = [{"id": c.id, "type": "function", "function": {"name": c.name, "arguments": c.raw}}
                                 for c in self.tool_calls]
        return msg


class ChatClient(Protocol):
    async def chat(self, messages: list[dict], tools: list[dict]) -> ChatResult: ...


_SEMAPHORES: dict[int, asyncio.Semaphore] = {}


def _semaphore() -> asyncio.Semaphore:
    loop = asyncio.get_running_loop()
    sem = _SEMAPHORES.get(id(loop))
    if sem is None:
        sem = _SEMAPHORES[id(loop)] = asyncio.Semaphore(int(os.environ.get("COLLAB_LLM_MAX_INFLIGHT", "64")))
    return sem


_RETRYABLE_ERRORS = (httpx.ConnectError, httpx.ConnectTimeout, httpx.RemoteProtocolError, httpx.ReadError,
                     httpx.WriteError, httpx.PoolTimeout)


class OpenAIChatClient:
    def __init__(self, resolve_base_url: Callable[[], str], api_key: str, model: str, effort: str | None,
                 max_tokens: int = 16384, retry_window_s: float = 600, http_client: httpx.AsyncClient | None = None,
                 backoff_s: float = 1.0, max_backoff_s: float = 30.0):
        self._resolve, self._key, self.model, self.effort = resolve_base_url, api_key, model, effort
        self.max_tokens, self.retry_window_s = max_tokens, retry_window_s
        self.backoff_s, self.max_backoff_s = backoff_s, max_backoff_s
        self._http = http_client or httpx.AsyncClient(
            timeout=httpx.Timeout(connect=15.0, read=1800.0, write=60.0, pool=None))

    async def aclose(self) -> None:
        await self._http.aclose()

    async def chat(self, messages: list[dict], tools: list[dict]) -> ChatResult:
        body: dict = {"model": self.model, "messages": messages, "max_tokens": self.max_tokens}
        if tools:
            body["tools"] = tools
        if self.effort:
            body["reasoning_effort"] = self.effort
        headers = {"Authorization": f"Bearer {self._key}"}
        deadline, delay, base = time.monotonic() + self.retry_window_s, self.backoff_s, self._resolve()
        while True:
            try:
                async with _semaphore():
                    r = await self._http.post(f"{base.rstrip('/')}/chat/completions", json=body, headers=headers)
                if r.status_code == 200:
                    return _parse(r.json())
                if r.status_code != 429 and r.status_code < 500:
                    raise LLMError(f"HTTP {r.status_code}: {r.text[:500]}")
                last = f"HTTP {r.status_code}"
            except _RETRYABLE_ERRORS as e:
                last = type(e).__name__
                base = self._resolve()
            except httpx.ReadTimeout:
                last = "ReadTimeout"
            if time.monotonic() + delay > deadline:
                raise LLMUnavailable(f"model API unavailable for {self.retry_window_s:.0f}s (last: {last})")
            await asyncio.sleep(delay)
            delay = min(delay * 2, self.max_backoff_s)


def _parse(data: dict) -> ChatResult:
    choice = data["choices"][0]
    msg = choice.get("message") or {}
    calls = []
    for c in msg.get("tool_calls") or []:
        fn = c.get("function") or {}
        raw = fn.get("arguments") or ""
        try:
            args = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            args = None
        calls.append(ToolCall(c.get("id", ""), fn.get("name", ""), args if isinstance(args, dict) else None, raw))
    usage = data.get("usage") or {}
    return ChatResult(content=msg.get("content") or "",
                      reasoning=msg.get("reasoning") or msg.get("reasoning_content") or "",
                      tool_calls=calls, prompt_tokens=int(usage.get("prompt_tokens") or 0),
                      completion_tokens=int(usage.get("completion_tokens") or 0),
                      finish_reason=choice.get("finish_reason") or "")


class ScriptedClient:
    """A test double: returns scripted results in order and records the messages of every call."""

    def __init__(self, steps: list[ChatResult | Callable[[list[dict]], ChatResult]]):
        self._steps = list(steps)
        self.calls: list[list[dict]] = []

    async def chat(self, messages: list[dict], tools: list[dict]) -> ChatResult:
        self.calls.append(json.loads(json.dumps(messages)))
        if not self._steps:
            raise AssertionError(f"script ran out after {len(self.calls) - 1} calls")
        step = self._steps.pop(0)
        return step(messages) if callable(step) else step
