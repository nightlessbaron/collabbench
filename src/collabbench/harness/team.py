"""The team harness as one Harbor agent (design 6).

`Team` runs k agent loops that share one sandbox, one channel and one event log, and implements the `Services` the loops
call. `TeamAgent` is the Harbor wrapper: it pops the team settings out of Harbor's agent kwargs, takes the private
context out of the sandbox in `setup`, builds the model client from the environment, runs a `Team`, and fills Harbor's
AgentContext. Every control in design 8.1 is a TeamSettings value; nothing else differs between a team and a control.
"""

import asyncio
import importlib
import json
import os
import re
import shlex
import shutil
import tempfile
import time
from collections.abc import Callable
from dataclasses import asdict, fields
from pathlib import Path

from harbor.agents.base import BaseAgent

from collabbench import settings as settings_mod
from collabbench.harness.agent_loop import AgentOutcome, AgentSpec, run_agent
from collabbench.harness.channel import Channel
from collabbench.harness.config import TeamSettings
from collabbench.harness.events import EventLog
from collabbench.harness.llm import ChatClient, ChatResult, OpenAIChatClient
from collabbench.harness.sandbox import (PRIVATE_DIR, WORKSPACE, Private, Snapshotter, assemble_isolated,
                                         prepare_workspace, take_private)
from collabbench.harness.tools import run_command

TEAM_KEYS = {f.name for f in fields(TeamSettings)}

SOLO_SYSTEM = ("You are an agent working on a task in a Linux sandbox. Your working directory is {cwd}. Use your tools "
               "to do the work. When you are done, call finish once with your report.")
PEER_SYSTEM = ("You are {name}. You share a Linux sandbox with {others}. Your working directory is {cwd}. Use your "
               "tools to do the work. {channel} {reporter} When you are done, call finish once with your report.")
CHANNEL_OPEN = "Messages from teammates arrive as user messages that start with [from <name>]."
CHANNEL_CLOSED = "There is no message channel in this run: you cannot message your teammates."
REPORTER = "You submit the team's final report: call finish only when the task is done or nothing more can be done."
NON_REPORTER = "agent-0 submits the team's final report."
LEAD_SYSTEM = ("You are lead, working on a task in a Linux sandbox. Your working directory is {cwd}. You can start up "
               "to {n} helpers with spawn. Each helper gets its own token budget and {where}, and sees only your "
               "instructions and messages, never the task brief. {merge}You submit the final report: call finish once, "
               "when the task is done.")
SUB_SYSTEM = ("You are {name}, a helper started by lead in a Linux sandbox. Your working directory is {cwd}{git}. "
              "lead's instructions follow. Message lead with send when you have results or questions. When your part "
              "is done, call finish once with your report.")


class _Counting:
    """Wraps a client to keep the team's running token totals (for snapshots and Harbor's context)."""

    def __init__(self, inner: ChatClient, team: "Team"):
        self.inner, self.team = inner, team

    async def chat(self, messages, tools) -> ChatResult:
        res = await self.inner.chat(messages, tools)
        self.team.tokens_in += res.prompt_tokens
        self.team.tokens_out += res.completion_tokens
        return res


class Team:
    def __init__(self, settings: TeamSettings, env, clients: Callable[[str], ChatClient], logs_dir: Path,
                 private: Private, instruction: str, simulators: dict | None = None):
        self.settings, self.env, self.private, self.instruction = settings, env, private, instruction
        self._clients, self._simulators = clients, simulators
        self.dir = Path(logs_dir) / "collab"
        self.log = EventLog(self.dir / "events.jsonl")
        self.channel = Channel(self.log, open=settings.channel == "open")
        self.stop = asyncio.Event()
        self.mode = settings.workspace or private.manifest.get("workspace") or "shared"
        self.tasks: dict[str, asyncio.Task] = {}
        self.outcomes: dict[str, AgentOutcome] = {}
        self.cwds: dict[str, str] = {}
        self.reports: dict[str, dict] = {}
        self.reporter = "lead" if settings.topology == "lead" else "agent-0"
        self.helpers = 0
        self.evaluations = 0
        self.tokens_in = self.tokens_out = 0
        self.timed_out = False
        self._snaps: list[asyncio.Task] = []
        self.snap = Snapshotter(env, self.log, settings.snapshot_every_s, settings.max_snapshots, self._sources,
                                lambda: self.tokens_in + self.tokens_out)

    # setup ------------------------------------------------------------------------------------------------------
    def _notes(self, index: int) -> str:
        roles, p, s = self.private.roles, self.private, self.settings

        def text(role: str) -> str | None:
            return p.placebos.get(role) if s.placebo == role else p.texts.get(role)

        if s.facts == "shared":
            parts = [f"## Notes from {r}\n{t}" for r in roles if (t := text(r))]
            return "\n\n" + "\n\n".join(parts) if parts else ""
        if index < len(roles) and (t := text(roles[index])):
            return f"\n\n## Your notes\n{t}"
        return ""

    async def _initial_specs(self) -> list[AgentSpec]:
        s, ev = self.settings, bool(self.private.manifest.get("evaluate"))
        if s.topology == "lead":
            cwd = await self._workspace("lead", True)
            where = ("its own git worktree /work/<name> on a branch named after it" if self.mode == "worktrees"
                     else "works in the same directory as you")
            merge = f"Merging their branches into {cwd} is your job. " if self.mode == "worktrees" else ""
            system = LEAD_SYSTEM.format(cwd=cwd, n=s.team_size - 1, where=where, merge=merge)
            return [AgentSpec("lead", system, self.instruction + self._notes(0), s.budget, cwd, True, ev)]
        if s.team_size == 1:
            cwd = await self._workspace("agent-0", True)
            return [AgentSpec("agent-0", SOLO_SYSTEM.format(cwd=cwd), self.instruction + self._notes(0),
                              s.solo_budget(), cwd, False, ev)]
        names = [f"agent-{i}" for i in range(s.team_size)]
        specs = []
        for i, name in enumerate(names):
            cwd = await self._workspace(name, i == 0)
            system = PEER_SYSTEM.format(name=name, others=", ".join(n for n in names if n != name), cwd=cwd,
                                        channel=CHANNEL_OPEN if self.channel.open else CHANNEL_CLOSED,
                                        reporter=REPORTER if i == 0 else NON_REPORTER)
            specs.append(AgentSpec(name, system, self.instruction + self._notes(i), s.budget, cwd, False, ev))
        return specs

    async def _workspace(self, name: str, is_lead: bool) -> str:
        cwd = await prepare_workspace(self.env, self.mode, name, is_lead)
        self.cwds[name] = cwd
        return cwd

    def _sources(self) -> dict[str, str]:
        out = {"workspace": WORKSPACE}
        out.update({name: cwd for name, cwd in self.cwds.items() if cwd != WORKSPACE})
        return out

    # running ----------------------------------------------------------------------------------------------------
    def _start(self, spec: AgentSpec) -> None:
        self.channel.add(spec.name)
        self.tasks[spec.name] = asyncio.create_task(self._agent(spec))

    async def _agent(self, spec: AgentSpec) -> AgentOutcome:
        out = await run_agent(spec, _Counting(self._clients(spec.name), self), self, self.log, self.settings)
        self.outcomes[spec.name] = out
        self.channel.remove(spec.name)
        return out

    async def run(self) -> dict:
        snap_stop = asyncio.Event()
        snap_task = None
        try:
            for spec in await self._initial_specs():
                self._start(spec)
            snap_task = asyncio.create_task(self.snap.run(snap_stop))
            await self._supervise()
        except asyncio.CancelledError:
            self.timed_out = True
            raise
        finally:
            self.stop.set()
            await self._cancel([t for t in self.tasks.values() if not t.done()])
            snap_stop.set()
            if snap_task:
                await asyncio.gather(snap_task, return_exceptions=True)
            outcome = self._outcome()  # written even when Harbor cancels the run (the agent timeout)
        await asyncio.gather(*self._snaps, return_exceptions=True)
        if self.mode == "isolated":
            owners = self.private.manifest.get("owners", {})
            await assemble_isolated(self.env, {f"agent-{i}": owners.get(role, [])
                                               for i, role in enumerate(self.private.roles)})
        await self.snap.take("final")
        return outcome

    async def _supervise(self) -> None:
        while True:
            live = [t for t in self.tasks.values() if not t.done()]
            if not live:
                return
            if self.tasks[self.reporter].done():
                _, pending = await asyncio.wait(live, timeout=self.settings.idle_grace_s)
                await self._cancel(list(pending) + [t for t in self.tasks.values() if not t.done()])
                return
            await asyncio.wait(live, return_when=asyncio.FIRST_COMPLETED)

    async def _cancel(self, tasks: list[asyncio.Task]) -> None:
        if tasks:
            self.stop.set()
            for t in tasks:
                t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    # services (called by the agent loops) -----------------------------------------------------------------------
    async def bash(self, agent: str, command: str, timeout_s: int, cwd: str) -> str:
        return await run_command(self.env, self.log, agent, command, timeout_s, cwd)

    async def spawn(self, lead: str, name: str, instructions: str) -> str:
        limit = self.settings.team_size - 1
        if self.helpers >= limit:
            return f"Spawn limit reached: this run allows {limit} helper(s)."
        base = re.sub(r"[^a-z0-9-]+", "-", name.lower()).strip("-")[:24] or "helper"
        name, n = base, 2
        while name in self.tasks or name in {"lead", "main", "workspace"}:
            name, n = f"{base}-{n}", n + 1
        cwd = await self._workspace(name, False)
        self.helpers += 1
        git = f" (a git worktree on branch {name}; {WORKSPACE} holds lead's branch)" if self.mode == "worktrees" else ""
        spec = AgentSpec(name, SUB_SYSTEM.format(name=name, cwd=cwd, git=git), instructions, self.settings.budget,
                         cwd, False, bool(self.private.manifest.get("evaluate")))
        self.log.emit(lead, "spawn", name=name, cwd=cwd, instructions=instructions)
        self._start(spec)
        return f"Started {name} in {cwd}."

    async def evaluate(self, agent: str, path: str) -> str:
        ev = self.private.manifest.get("evaluate")
        if not ev:
            return "This task has no evaluator."
        if self.evaluations >= self.settings.evaluate_cap:
            return f"The evaluation budget is used up ({self.settings.evaluate_cap} calls for the whole team)."
        self.evaluations += 1
        n = self.evaluations
        if not path.startswith("/"):
            path = f"{self.cwds.get(agent, WORKSPACE)}/{path}"
        r = await self.env.exec(f"cat {shlex.quote(path)}", timeout_sec=60)
        try:
            plan = json.loads(r.stdout or "")
        except json.JSONDecodeError:
            plan = None
        sims = self._simulators or importlib.import_module("collabbench.tracks.inspire.sims").SIMULATORS
        sim, params = sims[ev["concept"]], ev["params"]
        problem = "not valid JSON" if not isinstance(plan, dict) else sim.validate(plan, params)
        if problem:
            self.log.emit(agent, "evaluate", path=path, n=n, valid=False, problem=problem)
            return f"Plan rejected: {problem}. ({self.settings.evaluate_cap - n} evaluations left for the team.)"
        lo, hi = sim.objective(sim.baseline(params), params), sim.objective(sim.optimum(params), params)
        raw = sim.objective(plan, params, noise_seed=int(ev.get("train_noise_seed", 0)) * 1000 + n)
        score = (raw - lo) / (hi - lo) if hi != lo else 0.0
        self.log.emit(agent, "evaluate", path=path, n=n, valid=True, score=round(score, 4))
        return (f"Score {score:.3f} on the training seed (noisy; 0 is the uniform plan, 1 is the best possible). "
                f"{self.settings.evaluate_cap - n} evaluations left for the team.")

    def finish(self, agent: str, report: dict) -> str:
        self.reports[agent] = report
        self._snaps.append(asyncio.create_task(self.snap.take(f"status:{agent}")))
        if agent != self.reporter:
            self.channel.notify(self.reporter, f"{agent} finished (done={report['done']}): {report.get('notes', '')}"[:600])
            return "Report received. Your part is over."
        return "Team report received."

    # results ----------------------------------------------------------------------------------------------------
    def _outcome(self) -> dict:
        agents = {name: {"status": o.status, "tokens": o.tokens, "turns": o.turns} for name, o in self.outcomes.items()}
        reporter = self.outcomes.get(self.reporter)
        status = "timeout" if self.timed_out else (reporter.status if reporter else "error")
        outcome = {"status": status, "report": self.reports.get(self.reporter), "agents": agents,
                   "settings": asdict(self.settings), "workspace_mode": self.mode, "tokens_in": self.tokens_in,
                   "tokens_out": self.tokens_out, "evaluations": self.evaluations, "helpers": self.helpers,
                   "deadlocks": self.channel.deadlocks}
        (self.dir / "transcripts").mkdir(parents=True, exist_ok=True)
        for name, o in self.outcomes.items():
            (self.dir / "transcripts" / f"{name}.json").write_text(json.dumps(o.transcript, indent=1, default=str))
        (self.dir / "outcome.json").write_text(json.dumps(outcome, indent=1, default=str))
        return outcome


class TeamAgent(BaseAgent):
    """Harbor agent: `-a collabbench.harness.team:TeamAgent --ak team_size=2 --ak topology=peers ...`."""

    def __init__(self, *args, **kwargs):
        team_kw = {k: kwargs.pop(k) for k in list(kwargs) if k in TEAM_KEYS}
        self.settings = TeamSettings.from_kwargs(team_kw)
        super().__init__(*args, **kwargs)
        self.private = Private()
        self.client_factory: Callable[[str], ChatClient] | None = None  # tests inject scripted clients here
        self._tmp: Path | None = None

    @staticmethod
    def name() -> str:
        return "collabbench-team"

    def version(self) -> str:
        return "0.1.0"

    def _make_client_factory(self) -> Callable[[str], ChatClient]:
        base = os.environ.get("COLLAB_LLM_BASE_URL")
        resolve = (lambda: base) if base else settings_mod.gateway_url
        key = os.environ.get("COLLAB_LLM_API_KEY") or settings_mod.gateway_key()
        client = OpenAIChatClient(resolve, key, self.model_name or settings_mod.MODEL, self.settings.effort)
        return lambda name: client

    async def setup(self, environment) -> None:
        r = await environment.exec("for c in bash git tar timeout; do command -v $c >/dev/null 2>&1 || echo $c; done",
                                   timeout_sec=60)
        missing = (r.stdout or "").split()
        if missing:
            raise RuntimeError(f"the sandbox image lacks {missing}, which the team harness needs")
        self._tmp = Path(tempfile.mkdtemp(prefix="collab-private-"))  # never under logs_dir
        self.private = await take_private(environment, self._tmp)

    async def run(self, instruction: str, environment, context) -> None:
        try:
            if self.settings.probe:
                context.metadata = {"probe": await self._probe(environment)}
                return
            team = Team(self.settings, environment, self.client_factory or self._make_client_factory(),
                        self.logs_dir, self.private, instruction)
            try:
                outcome = await team.run()
            finally:
                context.n_input_tokens, context.n_output_tokens = team.tokens_in, team.tokens_out
                done = json.loads((team.dir / "outcome.json").read_text()) if (team.dir / "outcome.json").exists() else {}
                context.metadata = {k: done.get(k) for k in ("status", "report", "settings", "agents")}
        finally:
            if self._tmp:
                shutil.rmtree(self._tmp, ignore_errors=True)

    async def _probe(self, environment) -> dict:
        exists = (await environment.exec(f"test -e {PRIVATE_DIR}", timeout_sec=60)).return_code == 0
        start = time.monotonic()
        await asyncio.gather(*(environment.exec("sleep 2", timeout_sec=60) for _ in range(8)))
        return {"private_exists": exists, "parallel_exec_s": round(time.monotonic() - start, 2)}
