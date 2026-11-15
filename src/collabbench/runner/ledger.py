"""The spend ledger: one JSON line per trial, per pool. The runner checks it before every job."""

import json
import time
from pathlib import Path

from collabbench.runner.pools import POOL_ORDER, POOLS, Pool


class BudgetExceeded(Exception):
    pass


class Ledger:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.rows = [json.loads(l) for l in self.path.read_text().splitlines() if l.strip()] if self.path.exists() else []

    def record(self, pool: str, job: str, trial: str, usd: float, **extra) -> None:
        row = {"time": time.time(), "pool": pool, "job": job, "trial": trial, "usd": round(float(usd), 6), **extra}
        self.rows.append(row)
        with self.path.open("a") as f:
            f.write(json.dumps(row) + "\n")

    def spent(self, pool: str) -> float:
        return sum(r["usd"] for r in self.rows if r["pool"] == pool)

    def mean_cost(self) -> float | None:
        costs = [r["usd"] for r in self.rows if r.get("kind", "trial") == "trial"]
        return sum(costs) / len(costs) if costs else None

    def check(self, pool: str, projected_usd: float) -> None:
        cap = POOLS[pool].cap_usd
        if self.spent(pool) + projected_usd > cap:
            raise BudgetExceeded(f"pool {pool}: spent ${self.spent(pool):.2f} + projected ${projected_usd:.2f} "
                                 f"would pass its cap ${cap:.2f}")


def choose_pool(ledger: Ledger, preferred: str, projected_usd: float) -> Pool:
    """The preferred pool if it has room, else the next one in POOL_ORDER that does."""
    order = [preferred] + [p for p in POOL_ORDER if p != preferred]
    for name in order:
        try:
            ledger.check(name, projected_usd)
            return POOLS[name]
        except BudgetExceeded:
            continue
    raise BudgetExceeded(f"every pool would pass its cap with ${projected_usd:.2f} more")
