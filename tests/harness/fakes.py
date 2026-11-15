"""Test doubles: a local stand-in for a Harbor environment, scripted-result helpers and fake Services."""

import asyncio
import os
import re
import signal
import shutil
from dataclasses import dataclass
from pathlib import Path

from collabbench.harness.channel import Channel
from collabbench.harness.llm import ChatResult, ToolCall
from collabbench.harness.tools import run_command

_SANDBOX_PATHS = re.compile(r"(?<![\w.~-])/(workspace|work|opt/collab|snapshots|var/log)(?![\w-])")


@dataclass
class ExecResult:
    stdout: str
    stderr: str
    return_code: int


class LocalEnvironment:
    """The subset of Harbor's BaseEnvironment the harness uses, over a temp dir: sandbox paths live under `root`."""

    def __init__(self, root: Path):
        self.root = Path(root)
        for d in ("workspace", "work", "opt/collab", "snapshots", "var/log"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        self.commands: list[str] = []

    def path(self, sandbox_path: str) -> Path:
        return Path(self._rewrite(sandbox_path))

    def _rewrite(self, text: str) -> str:
        return _SANDBOX_PATHS.sub(lambda m: f"{self.root}/{m.group(1)}", text)

    async def exec(self, command, cwd=None, env=None, timeout_sec=None, user=None):
        self.commands.append(command)
        proc = await asyncio.create_subprocess_exec(
            "bash", "-c", self._rewrite(command), cwd=self._rewrite(cwd) if cwd else str(self.root),
            env={"PATH": os.environ["PATH"], "HOME": str(self.root), "LANG": "C.UTF-8", **(env or {})},  # a sandbox does not inherit the harness env
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, start_new_session=True)
        try:
            out, err = await asyncio.wait_for(proc.communicate(), timeout_sec)
        except (TimeoutError, asyncio.CancelledError):
            try:
                os.killpg(proc.pid, signal.SIGKILL)  # the command's children too, like a sandbox teardown
            except ProcessLookupError:
                pass
            await proc.communicate()
            raise
        return ExecResult(out.decode(errors="replace"), err.decode(errors="replace"), proc.returncode)

    async def download_dir(self, source_dir, target_dir):
        shutil.copytree(self.path(source_dir), target_dir, dirs_exist_ok=True)

    async def download_file(self, source_path, target_path):
        Path(target_path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(self.path(source_path), target_path)

    async def upload_file(self, source_path, target_path):
        dst = self.path(target_path)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(source_path, dst)


def call(tool: str, /, _id: str | None = None, **args) -> ToolCall:
    import json
    raw = json.dumps(args)
    return ToolCall(_id or f"c-{tool}-{abs(hash(raw)) % 10**6}", tool, args, raw)


def result(content: str = "", calls=(), reasoning: str = "", p: int = 10, c: int = 5) -> ChatResult:
    return ChatResult(content, reasoning, list(calls), p, c, "tool_calls" if calls else "stop")


REPORT = {"done": True, "requirements": {"R1": "met"}, "notes": "ok"}


class FakeServices:
    def __init__(self, env: LocalEnvironment, log, channel: Channel | None = None):
        self.env, self.log = env, log
        self.channel = channel or Channel(log)
        self.stop = asyncio.Event()
        self.reports: dict[str, dict] = {}
        self.spawned: list[tuple[str, str, str]] = []

    async def bash(self, agent, command, timeout_s, cwd):
        return await run_command(self.env, self.log, agent, command, timeout_s, cwd)

    async def spawn(self, lead, name, instructions):
        self.spawned.append((lead, name, instructions))
        return f"Started {name}."

    async def evaluate(self, agent, path):
        return "score 0.5"

    def finish(self, agent, report):
        self.reports[agent] = report
        return "Report received."
