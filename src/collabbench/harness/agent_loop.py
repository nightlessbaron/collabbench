"""One agent's tool-calling loop (design 6.2 to 6.5). Solo and team agents run exactly this loop."""

import asyncio
import json
from collections import Counter
from dataclasses import dataclass, field
from typing import Literal, Protocol

from collabbench.harness.budget import Budget
from collabbench.harness.channel import Channel
from collabbench.harness.compaction import compact
from collabbench.harness.config import TeamSettings
from collabbench.harness.events import EventLog
from collabbench.harness.llm import ChatClient, LLMError, LLMUnavailable, ToolCall
from collabbench.harness.tools import tool_specs

MODEL_LIMIT = 1_000_000  # compaction threshold when context_cap is None
SILENT_LIMIT = 3  # replies in a row without a tool call before the agent is stopped
COMMAND_REPEATS = 5  # the same command this many times in a row is a loop
MESSAGE_REPEATS = 3  # the same message text this many times is a loop
WARNING = ("[harness] Your token budget is nearly used: about {turns} more turns at your current context size. "
           "Wrap up now and call finish with your report.")
NUDGE = "[harness] Reply with a tool call. When you are done, call finish with your report."
REQUIREMENT_STATES = {"met", "not_met", "unsure"}

Status = Literal["finished", "budget_exhausted", "stopped", "error"]


@dataclass
class AgentSpec:
    name: str
    system: str
    first_user: str
    budget: int
    cwd: str
    can_spawn: bool = False
    can_evaluate: bool = False


@dataclass
class AgentOutcome:
    name: str
    status: Status
    report: dict | None
    tokens: int
    turns: int
    transcript: list[dict] = field(default_factory=list)


class Services(Protocol):
    channel: Channel
    stop: asyncio.Event

    async def bash(self, agent: str, command: str, timeout_s: int, cwd: str) -> str: ...
    async def spawn(self, lead: str, name: str, instructions: str) -> str: ...
    async def evaluate(self, agent: str, path: str) -> str: ...
    def finish(self, agent: str, report: dict) -> str: ...


async def run_agent(spec: AgentSpec, client: ChatClient, services: Services, log: EventLog,
                    settings: TeamSettings) -> AgentOutcome:
    budget = Budget(spec.budget)
    tools = tool_specs(channel_open=services.channel.open, can_spawn=spec.can_spawn, can_evaluate=spec.can_evaluate)
    allowed = [t["function"]["name"] for t in tools]
    messages = [{"role": "system", "content": spec.system}, {"role": "user", "content": spec.first_user}]
    cap = settings.context_cap or MODEL_LIMIT
    last_prompt, new_chars = 0, len(spec.system) + len(spec.first_user)
    turns, silent = 0, 0
    status: Status | None = None
    reason, report = "", None
    last_command, streak, sent = None, 0, Counter()

    try:
        while status is None:
            if services.stop.is_set() or services.channel.ended:
                status, reason = "stopped", "the team run ended"
                break
            if turns >= settings.max_turns:
                status, reason = "stopped", f"max_turns={settings.max_turns}"
                break
            inbox = services.channel.drain(spec.name)
            if inbox:
                text = "\n".join(f"[from {sender}] {body}" for sender, body in inbox)
                messages.append({"role": "user", "content": text})
                new_chars += len(text)
            if last_prompt + new_chars / 3 > cap:
                messages, summary = await compact(messages, client)
                if summary is not None:
                    used = summary.prompt_tokens + summary.completion_tokens
                    log.emit(spec.name, "compaction", tokens_in=summary.prompt_tokens,
                             tokens_out=summary.completion_tokens, messages_after=len(messages))
                    last_prompt, new_chars = 0, sum(len(json.dumps(m)) for m in messages)
                    if budget.charge(used) == "exhausted":
                        status, reason = "budget_exhausted", "budget used up by compaction"
                        break
            try:
                res = await client.chat(messages, tools)
            except (LLMUnavailable, LLMError) as e:
                log.emit(spec.name, "error", kind=type(e).__name__, error=str(e)[:500])
                status, reason = "error", type(e).__name__
                break
            turns += 1
            last_prompt, new_chars = res.prompt_tokens, len(res.content)
            state = budget.charge(res.prompt_tokens + res.completion_tokens)
            log.emit(spec.name, "llm_call", tokens_in=res.prompt_tokens, tokens_out=res.completion_tokens, turn=turns,
                     reasoning=res.reasoning, content=res.content, finish_reason=res.finish_reason,
                     tool_calls=[{"name": c.name, "raw": c.raw} for c in res.tool_calls])
            messages.append(res.as_message())

            if state == "exhausted":
                fin = next((c for c in res.tool_calls if c.name == "finish"), None)
                text, report = await _dispatch(fin, spec, services, log, allowed) if fin else ("", None)
                status, reason = ("finished", "") if report is not None else ("budget_exhausted", "token budget used up")
                break
            if not res.tool_calls:
                silent += 1
                if silent >= SILENT_LIMIT:
                    status, reason = "stopped", f"{SILENT_LIMIT} replies without a tool call"
                    break
                messages.append({"role": "user", "content": NUDGE})
                continue
            silent = 0

            for c in res.tool_calls:
                text, report = await _dispatch(c, spec, services, log, allowed)
                messages.append({"role": "tool", "tool_call_id": c.id, "content": text})
                new_chars += len(text)
                if c.name == "bash" and c.arguments:
                    command = str(c.arguments.get("command"))
                    streak = streak + 1 if command == last_command else 1
                    last_command = command
                    if streak % COMMAND_REPEATS == 0:
                        log.emit(spec.name, "loop", kind="command", command=command, repeats=streak)
                if c.name == "send" and c.arguments:
                    key = str(c.arguments.get("text"))
                    sent[key] += 1
                    if sent[key] == MESSAGE_REPEATS:
                        log.emit(spec.name, "loop", kind="message", text=key[:500], repeats=sent[key])
                if report is not None:
                    status = "finished"
                    break
            if status is None and state == "warn":
                per_call = res.prompt_tokens + res.completion_tokens
                messages.append({"role": "user", "content": WARNING.format(turns=budget.turns_left(per_call))})
                log.emit(spec.name, "budget_warning", used=budget.used, limit=budget.limit)

    except asyncio.CancelledError:  # the team stopped this agent (idle grace, deadlock, timeout)
        status, reason = "stopped", "cancelled"
    if status != "finished":
        log.emit(spec.name, "stopped", status=status, reason=reason)
    return AgentOutcome(spec.name, status, report, budget.used, turns, messages)


async def _dispatch(c: ToolCall, spec: AgentSpec, services: Services, log: EventLog,
                    allowed: list[str]) -> tuple[str, dict | None]:
    """Run one tool call. Returns the tool's text and, for a valid finish, the report."""
    if c.name not in allowed:
        return f"Unknown tool {c.name!r}. Your tools: {', '.join(allowed)}.", None
    if c.arguments is None:
        return f"Invalid JSON arguments for {c.name}: {c.raw[:300]!r}. Send one JSON object.", None
    a = c.arguments
    required = {"bash": ["command"], "send": ["to", "text"], "publish": ["title", "body"], "read_finding": ["id"],
                "claim": ["unit"], "release": ["unit"], "spawn": ["name", "instructions"], "finish": ["report"]}
    missing = [k for k in required.get(c.name, []) if a.get(k) in (None, "")]
    if missing:
        return f"Missing field(s) {missing} for {c.name}.", None
    ch = services.channel
    try:
        match c.name:
            case "bash":
                return await services.bash(spec.name, str(a["command"]), int(a.get("timeout_s") or 600), spec.cwd), None
            case "send":
                return ch.send(spec.name, str(a["to"]), str(a["text"])), None
            case "wait":
                got = await ch.wait(spec.name, min(float(a.get("timeout_s") or 120), 600.0))
                if got:
                    return "\n".join(f"[from {s}] {t}" for s, t in got), None
                return ("No messages. The team run is ending; call finish now." if ch.ended
                        else "No messages arrived before the timeout."), None
            case "publish":
                return f"Published finding #{ch.publish(spec.name, str(a['title']), str(a['body']))}.", None
            case "read_finding":
                return ch.read_finding(spec.name, int(a["id"])), None
            case "claim":
                return ch.claim(spec.name, str(a["unit"])), None
            case "release":
                return ch.release(spec.name, str(a["unit"])), None
            case "spawn":
                return await services.spawn(spec.name, str(a["name"]), str(a["instructions"])), None
            case "evaluate":
                return await services.evaluate(spec.name, str(a.get("path") or "/workspace/plan.json")), None
            case "finish":
                report, problem = _normalize_report(a["report"])
                if problem:
                    return f"Report not accepted: {problem}", None
                text = services.finish(spec.name, report)
                log.emit(spec.name, "status", report=report)
                return text, report
    except (TypeError, ValueError) as e:
        return f"Bad arguments for {c.name}: {e}", None
    return f"Unknown tool {c.name!r}.", None


def _normalize_report(report) -> tuple[dict, str | None]:
    if isinstance(report, str):
        try:
            report = json.loads(report)
        except json.JSONDecodeError:
            return {}, "report must be a JSON object with done and requirements"
    if not isinstance(report, dict) or not isinstance(report.get("requirements"), dict) or "done" not in report:
        return {}, "report must be an object with done (bool) and requirements ({id: met|not_met|unsure})"
    reqs = {str(k): str(v).lower().replace(" ", "_").replace("-", "_") for k, v in report["requirements"].items()}
    bad = {k: v for k, v in reqs.items() if v not in REQUIREMENT_STATES}
    if bad:
        return {}, f"requirement states must be met, not_met or unsure; got {bad}"
    return {"done": bool(report["done"]), "requirements": reqs, "notes": str(report.get("notes", ""))}, None
