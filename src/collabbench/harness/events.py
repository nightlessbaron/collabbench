"""The typed event log (design 6.6): one JSON object per line. Metrics read only this file and the verifier's output."""

import json
import time
from collections.abc import Callable
from pathlib import Path

EVENT_TYPES = frozenset(
    "llm_call action message wait wake publish import claim release spawn evaluate compaction budget_warning "
    "stopped status deadlock loop error".split())


class EventLog:
    def __init__(self, path: Path, clock: Callable[[], float] = time.monotonic):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._clock = clock
        self._start = clock()
        self._file = self.path.open("a", encoding="utf-8")

    def now(self) -> float:
        return round(self._clock() - self._start, 3)

    def emit(self, agent: str, type: str, *, tokens_in: int = 0, tokens_out: int = 0, **payload) -> dict:
        if type not in EVENT_TYPES:
            raise ValueError(f"unknown event type {type!r}")
        event = {"t": self.now(), "agent": agent, "type": type, "tokens_in": int(tokens_in),
                 "tokens_out": int(tokens_out), "payload": payload}
        self._file.write(json.dumps(event, default=str) + "\n")
        self._file.flush()
        return event

    def close(self) -> None:
        self._file.close()

    @staticmethod
    def read(path: Path) -> list[dict]:
        return [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]
