"""A token budget: prompt + completion tokens over all of an agent's calls (design 6.1)."""

from typing import Literal


class Budget:
    def __init__(self, limit: int, warn_at: float = 0.9):
        self.limit, self.warn_at = int(limit), warn_at
        self.used = 0
        self._warned = False

    @property
    def exhausted(self) -> bool:
        return self.used >= self.limit

    def charge(self, tokens: int) -> Literal["ok", "warn", "exhausted"]:
        self.used += int(tokens)
        if self.exhausted:
            return "exhausted"
        if not self._warned and self.used >= self.warn_at * self.limit:
            self._warned = True
            return "warn"
        return "ok"
