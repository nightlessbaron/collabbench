"""A token budget: prompt + completion tokens over all of an agent's calls (design 6.1).

The warning comes once, when what is left falls below 10% of the budget or below three calls of the size just made,
whichever comes first: at a 20k-token context a 10% warning on a 400k budget left the spike's agents two turns, too
few to finish and report.
"""

from typing import Literal


class Budget:
    def __init__(self, limit: int, warn_at: float = 0.9, warn_calls: int = 3):
        self.limit, self.warn_at, self.warn_calls = int(limit), warn_at, warn_calls
        self.used = 0
        self._warned = False

    @property
    def exhausted(self) -> bool:
        return self.used >= self.limit

    @property
    def remaining(self) -> int:
        return max(0, self.limit - self.used)

    def turns_left(self, per_call: int) -> int:
        return self.remaining // max(1, int(per_call))

    def charge(self, tokens: int) -> Literal["ok", "warn", "exhausted"]:
        self.used += int(tokens)
        if self.exhausted:
            return "exhausted"
        floor = max((1 - self.warn_at) * self.limit, self.warn_calls * int(tokens))
        if not self._warned and self.remaining < floor:
            self._warned = True
            return "warn"
        return "ok"
