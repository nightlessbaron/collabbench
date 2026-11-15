"""The team's message channel, findings board and claims (design 6.3, 6.4).

Every agent of a run shares one Channel on one event loop. A message reaches its recipient at the start of the
recipient's next turn (drain) or wakes it from `wait`. When every live agent is waiting and nothing is in flight the
team is deadlocked: the first time each waiter gets a notice, the second time the run ends.
"""

import asyncio

from collabbench.harness.events import EventLog

Message = tuple[str, str]  # (sender, text)


class Channel:
    NOTICE = "Every teammate is waiting. Nobody will message you until someone acts."

    def __init__(self, log: EventLog, open: bool = True):
        self.log, self.open = log, open
        self.ended = False
        self.deadlocks = 0
        self._known: list[str] = []
        self._live: set[str] = set()
        self._inbox: dict[str, list[Message]] = {}
        self._waiting: dict[str, asyncio.Future] = {}
        self._findings: list[tuple[str, str, str]] = []  # (author, title, body); id = index + 1
        self._claims: dict[str, str] = {}

    # membership -------------------------------------------------------------------------------------------------
    def add(self, agent: str) -> None:
        if agent not in self._known:
            self._known.append(agent)
        self._live.add(agent)
        self._inbox.setdefault(agent, [])

    def remove(self, agent: str) -> None:
        """The agent finished or was stopped: it no longer counts as live, and its wait (if any) returns."""
        self._live.discard(agent)
        fut = self._waiting.pop(agent, None)
        if fut is not None and not fut.done():
            fut.set_result([])
        self._check_deadlock()

    @property
    def live(self) -> set[str]:
        return set(self._live)

    # messages ---------------------------------------------------------------------------------------------------
    def send(self, sender: str, to: str, text: str) -> str:
        if not self.open:
            return "The message channel is closed in this run; nobody can receive messages."
        if to == "all":
            recipients = sorted(self._live - {sender})
        elif to in self._live and to != sender:
            recipients = [to]
        else:
            others = sorted(self._live - {sender})
            why = "has finished" if to in self._known and to != sender else "is not a teammate"
            return f"Not sent: {to!r} {why}. Live teammates: {', '.join(others) or 'none'}."
        self.log.emit(sender, "message", to=to, text=text, recipients=recipients)
        for r in recipients:
            self._deliver(r, (sender, text))
        return f"Sent to {', '.join(recipients) or 'nobody (no live teammates)'}."

    def drain(self, agent: str) -> list[Message]:
        msgs, self._inbox[agent] = self._inbox.get(agent, []), []
        return msgs

    async def wait(self, agent: str, timeout_s: float) -> list[Message]:
        if self.ended:
            return []
        pending = self.drain(agent)
        if pending:
            return pending
        fut = asyncio.get_running_loop().create_future()
        self._waiting[agent] = fut
        self.log.emit(agent, "wait", timeout_s=timeout_s)
        self._check_deadlock()
        try:
            got = await asyncio.wait_for(asyncio.shield(fut), timeout_s)
        except TimeoutError:
            got = []
        finally:
            if self._waiting.get(agent) is fut:
                del self._waiting[agent]
        got = got + self.drain(agent)
        self.log.emit(agent, "wake", messages=len(got), ended=self.ended)
        return got

    def _deliver(self, agent: str, msg: Message) -> None:
        fut = self._waiting.pop(agent, None)
        if fut is not None and not fut.done():
            fut.set_result([msg])
        else:
            self._inbox.setdefault(agent, []).append(msg)

    def _check_deadlock(self) -> None:
        if self.ended or not self._live or not self._live <= set(self._waiting):
            return
        if any(self._inbox.get(a) for a in self._live):
            return
        self.deadlocks += 1
        final = self.deadlocks >= 2
        self.log.emit("harness", "deadlock", final=final, agents=sorted(self._live))
        if final:
            self.ended = True
        waiters, self._waiting = self._waiting, {}
        for fut in waiters.values():
            if not fut.done():
                fut.set_result([] if final else [("harness", self.NOTICE)])

    # findings ---------------------------------------------------------------------------------------------------
    def publish(self, agent: str, title: str, body: str) -> int:
        if not self.open:
            raise RuntimeError("publish needs an open channel")
        self._findings.append((agent, title, body))
        fid = len(self._findings)
        self.log.emit(agent, "publish", id=fid, title=title, body=body)
        note = f"{agent} published finding #{fid}: {title}. Call read_finding({fid}) to read it."
        for r in sorted(self._live - {agent}):
            self._deliver(r, ("harness", note))
        return fid

    def read_finding(self, agent: str, fid: int) -> str:
        if not 1 <= int(fid) <= len(self._findings):
            return f"There is no finding #{fid}. Findings: 1..{len(self._findings)}."
        author, title, body = self._findings[int(fid) - 1]
        self.log.emit(agent, "import", id=int(fid), author=author, title=title)
        return body

    # claims -----------------------------------------------------------------------------------------------------
    def claim(self, agent: str, unit: str) -> str:
        owner = self._claims.get(unit)
        if owner == agent:
            return f"You already hold {unit}."
        if owner is not None:
            return f"{unit} is already claimed by {owner}."
        self._claims[unit] = agent
        self.log.emit(agent, "claim", unit=unit)
        return f"You claimed {unit}."

    def release(self, agent: str, unit: str) -> str:
        if self._claims.get(unit) != agent:
            return f"You do not hold {unit}."
        del self._claims[unit]
        self.log.emit(agent, "release", unit=unit)
        return f"You released {unit}."

    def claims(self) -> dict[str, str]:
        return dict(self._claims)
