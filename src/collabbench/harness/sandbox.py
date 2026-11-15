"""Sandbox-side operations of the team harness (design 6.6, 6.7): private context, workspaces, snapshots.

Every operation goes through the Harbor environment API (`exec`, `download_dir`, `upload_file`), so the same code runs
against Modal in production and against a local stand-in in tests.
"""

import asyncio
import json
import shlex
import tempfile
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from collabbench.harness.events import EventLog

PRIVATE_DIR = "/opt/collab/private"
SNAP_DIR = "/snapshots"
WORKSPACE = "/workspace"
WORK = "/work"
TRIPWIRE = "/var/log/collab-tripwire"


@dataclass
class Private:
    roles: list[str] = field(default_factory=list)
    texts: dict[str, str] = field(default_factory=dict)
    placebos: dict[str, str] = field(default_factory=dict)
    manifest: dict = field(default_factory=dict)


async def _run(env, command: str, timeout: int = 120):
    return await env.exec(command, timeout_sec=timeout)


async def take_private(env, local_dir: Path) -> Private:
    """Copy the private context out of the sandbox, delete it there, and make sure it is gone."""
    probe = await _run(env, f"test -d {PRIVATE_DIR}")
    if probe.return_code != 0:
        return Private()
    local_dir = Path(local_dir)
    local_dir.mkdir(parents=True, exist_ok=True)
    await env.download_dir(PRIVATE_DIR, local_dir)
    await _run(env, f"rm -rf {PRIVATE_DIR}")
    if (await _run(env, f"test -e {PRIVATE_DIR}")).return_code == 0:
        raise RuntimeError(f"{PRIVATE_DIR} still exists after deletion")
    manifest_path = local_dir / "_harness" / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    roles = list(manifest.get("roles", []))

    def read(name: str) -> str | None:
        p = local_dir / name
        return p.read_text() if p.exists() else None

    texts = {r: t for r in roles if (t := read(f"{r}.md")) is not None}
    placebos = {r: t for r in roles if (t := read(f"{r}.placebo.md")) is not None}
    return Private(roles, texts, placebos, manifest)


async def prepare_workspace(env, mode: str, agent: str, is_lead: bool) -> str:
    """Give an agent its working directory and return it."""
    if mode == "shared" or (mode == "worktrees" and is_lead):
        return WORKSPACE
    target = f"{WORK}/{agent}"
    if mode == "worktrees":
        cmd = f"mkdir -p {WORK} && git -C {WORKSPACE} worktree add -q {target} -b {shlex.quote(agent)}"
    elif mode == "isolated":
        cmd = f"rm -rf {target} && mkdir -p {WORK} && cp -a {WORKSPACE} {target}"
    else:
        raise ValueError(f"unknown workspace mode {mode!r}")
    r = await _run(env, cmd)
    if r.return_code != 0:
        raise RuntimeError(f"could not prepare {mode} workspace for {agent}: {(r.stdout or '') + (r.stderr or '')}")
    return target


async def assemble_isolated(env, owners_by_agent: dict[str, list[str]]) -> None:
    """No-communication control: copy each agent's owned paths from its own copy into /workspace."""
    for agent, paths in owners_by_agent.items():
        for rel in paths:
            src, dst = f"{WORK}/{agent}/{rel}", f"{WORKSPACE}/{rel}"
            await _run(env, f"if [ -e {shlex.quote(src)} ]; then mkdir -p \"$(dirname {shlex.quote(dst)})\" && "
                            f"rm -rf {shlex.quote(dst)} && cp -a {shlex.quote(src)} {shlex.quote(dst)}; fi")


class Snapshotter:
    """Tars each source directory (without .git) into /snapshots and keeps /snapshots/index.json current."""

    def __init__(self, env, log: EventLog, every_s: float, max_n: int, sources: Callable[[], dict[str, str]],
                 tokens: Callable[[], int] = lambda: 0):
        self.env, self.log, self.every_s, self.max_n = env, log, every_s, max_n
        self.sources, self.tokens = sources, tokens
        self.index: list[dict] = []
        self.taken = 0
        self._lock = asyncio.Lock()

    async def take(self, reason: str) -> None:
        async with self._lock:
            t = self.log.now()
            for label, directory in self.sources().items():
                name = f"{t:07.1f}-{label}.tar.gz"
                r = await _run(self.env, f"mkdir -p {SNAP_DIR} && tar -czf {SNAP_DIR}/{name} --exclude=.git "
                                         f"-C {shlex.quote(directory)} .", timeout=300)
                if r.return_code == 0:
                    self.index.append({"file": name, "t": t, "label": label, "reason": reason,
                                       "tokens_so_far": self.tokens()})
            self.taken += 1
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
                json.dump(self.index, f, indent=1)
            await self.env.upload_file(f.name, f"{SNAP_DIR}/index.json")
            Path(f.name).unlink(missing_ok=True)

    async def run(self, stop: asyncio.Event) -> None:
        interval = self.every_s
        while not stop.is_set():
            try:
                await asyncio.wait_for(stop.wait(), timeout=interval)
                return
            except TimeoutError:
                pass
            await self.take("periodic")
            if self.taken >= self.max_n:
                interval *= 2
