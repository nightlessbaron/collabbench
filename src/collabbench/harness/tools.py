"""The agents' tools (design 6.3): OpenAI function specs, output truncation, and the sandbox command runner."""

import shlex
import time

from collabbench.harness.events import EventLog

_REQ = {"type": "string", "enum": ["met", "not_met", "unsure"]}


def _fn(name: str, description: str, properties: dict, required: list[str]) -> dict:
    return {"type": "function", "function": {"name": name, "description": description, "parameters": {
        "type": "object", "properties": properties, "required": required}}}


BASH = _fn("bash", "Run a shell command in the shared sandbox, in your working directory. Returns the exit code and "
                   "output (long output is cut in the middle).",
           {"command": {"type": "string"},
            "timeout_s": {"type": "integer", "description": "Seconds before the command is killed (default 600)."}},
           ["command"])
SEND = _fn("send", "Send a message to one teammate, or to everyone with to='all'. It arrives at the start of their "
                   "next turn.",
           {"to": {"type": "string"}, "text": {"type": "string"}}, ["to", "text"])
WAIT = _fn("wait", "Wait until a teammate messages you, or until the timeout. Returns the messages that arrived.",
           {"timeout_s": {"type": "integer", "description": "Seconds to wait (default 120)."}}, [])
PUBLISH = _fn("publish", "Post a finding (a fact, a result, a decision) to a board every teammate can read.",
              {"title": {"type": "string"}, "body": {"type": "string"}}, ["title", "body"])
READ_FINDING = _fn("read_finding", "Read a published finding by its number.", {"id": {"type": "integer"}}, ["id"])
CLAIM = _fn("claim", "Mark a unit of work (a file, a module, a test) as yours, so teammates can see it is taken.",
            {"unit": {"type": "string"}}, ["unit"])
RELEASE = _fn("release", "Give back a unit you claimed.", {"unit": {"type": "string"}}, ["unit"])
SPAWN = _fn("spawn", "Start a teammate with its own budget and its own git worktree. It sees only these "
                     "instructions and your messages, not the task brief.",
            {"name": {"type": "string", "description": "A short name, letters, digits and dashes."},
             "instructions": {"type": "string"}}, ["name", "instructions"])
EVALUATE = _fn("evaluate", "Score a plan file with the task's simulator on a training seed (noisy). The number of "
                           "calls is capped for the whole team.",
               {"path": {"type": "string", "description": "Default /workspace/plan.json."}}, [])
FINISH = _fn("finish", "End your work and submit your final report. Call it once, when you are done.",
             {"report": {"type": "object", "properties": {
                 "done": {"type": "boolean", "description": "True if the task is complete."},
                 "requirements": {"type": "object", "additionalProperties": _REQ,
                                  "description": "For each requirement id in the brief: met, not_met or unsure."},
                 "notes": {"type": "string"}}, "required": ["done", "requirements"]}},
             ["report"])

CHANNEL_TOOLS = ("send", "wait", "publish", "read_finding")


def tool_specs(*, channel_open: bool, can_spawn: bool, can_evaluate: bool) -> list[dict]:
    specs = [BASH]
    if channel_open:
        specs += [SEND, WAIT, PUBLISH, READ_FINDING]
    specs += [CLAIM, RELEASE]
    if can_spawn:
        specs.append(SPAWN)
    if can_evaluate:
        specs.append(EVALUATE)
    return specs + [FINISH]


def truncate_output(text: str, head: int = 12000, tail: int = 8000) -> str:
    if len(text) <= head + tail:
        return text
    cut = len(text) - head - tail
    return f"{text[:head]}\n[... {cut} characters cut ...]\n{text[-tail:]}"


async def run_command(env, log: EventLog, agent: str, command: str, timeout_s: int, cwd: str) -> str:
    """Run `command` under bash and coreutils' timeout in the sandbox; log an `action` event; return the tool text."""
    timeout_s = max(1, int(timeout_s))
    wrapped = f"timeout -k 5 {timeout_s} bash -c {shlex.quote(command)}"
    start = time.monotonic()
    try:
        r = await env.exec(wrapped, cwd=cwd, timeout_sec=timeout_s + 30)
        output, code = (r.stdout or "") + (r.stderr or ""), r.return_code
    except Exception as e:  # the sandbox's own deadline or a transport error: the agent sees it
        output, code = f"{type(e).__name__}: {e}", -1
    timed_out = code in (124, 137)
    log.emit(agent, "action", command=command, cwd=cwd, exit_code=code, timed_out=timed_out,
             duration_s=round(time.monotonic() - start, 3), output_chars=len(output))
    head = f"[timed out after {timeout_s}s]" if timed_out else f"[exit {code}]"
    return f"{head}\n{truncate_output(output)}"
