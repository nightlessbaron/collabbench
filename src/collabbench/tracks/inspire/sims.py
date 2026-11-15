"""Hidden simulators of the Inspire track (design 7.4). Imported by the harness's `evaluate` tool (on the host) and
copied into each task's tests/ for the verifier; it never enters the agents' sandbox.

Each simulator scores a plan (a JSON object) for one instance (`params`). Its `optimum` comes from a concept of
another field and is the exact optimum of `objective`, except for the trap, whose optimum is found numerically because
the concept no longer applies. The brief shows `observables` and describes the system qualitatively; the functional
form stays hidden. Only stdlib and numpy.
"""

import heapq
import math
import random

import numpy as np

NOISE_FRAC = 0.03  # std of the training noise, as a fraction of the gap between the optimum and the baseline


class Simulator:
    key = ""  # the plan's top-level field

    def params(self, seed: int) -> dict:
        raise NotImplementedError

    def observables(self, params: dict) -> list[dict]:
        raise NotImplementedError

    def _vector(self, plan: dict, params: dict) -> np.ndarray:
        raise NotImplementedError

    def _value(self, x: np.ndarray, params: dict) -> float:
        raise NotImplementedError

    def optimum(self, params: dict) -> dict:
        raise NotImplementedError

    def baseline(self, params: dict) -> dict:
        raise NotImplementedError

    def hint_capture(self, plan: dict, params: dict) -> float:
        raise NotImplementedError

    # shared ------------------------------------------------------------------------------------------------------
    def validate(self, plan: dict, params: dict) -> str | None:
        if not isinstance(plan, dict) or not isinstance(plan.get(self.key), dict):
            return f'the plan must be a JSON object with a "{self.key}" object'
        items, given = params["items"], plan[self.key]
        unknown = sorted(set(given) - set(items))
        if unknown:
            return f"unknown names {unknown}; expected some of {items}"
        for k, v in given.items():
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0:
                return f"{k}: {v!r} is not a non-negative number"
        return self._validate_more(given, params)

    def _validate_more(self, given: dict, params: dict) -> str | None:
        return None

    def objective(self, plan: dict, params: dict, noise_seed: int | None = None) -> float:
        value = self._value(self._vector(plan, params), params)
        if noise_seed is not None:
            gap = self._gap(params)
            value += float(np.random.default_rng(noise_seed).normal(0.0, NOISE_FRAC * gap))
        return value

    def _gap(self, params: dict) -> float:
        return (self._value(self._vector(self.optimum(params), params), params)
                - self._value(self._vector(self.baseline(params), params), params))

    def normalized(self, plan: dict, params: dict) -> float:
        lo = self._value(self._vector(self.baseline(params), params), params)
        hi = self._value(self._vector(self.optimum(params), params), params)
        return (self._value(self._vector(plan, params), params) - lo) / (hi - lo)

    def _raw(self, plan: dict, params: dict) -> np.ndarray:
        given = plan[self.key]
        return np.array([float(given.get(k, 0.0)) for k in params["items"]])

    @staticmethod
    def _plan(key: str, items: list[str], x) -> dict:
        return {key: {k: round(float(v), 6) for k, v in zip(items, x)}}


def _rescale(x: np.ndarray, total: float) -> np.ndarray:
    s = x.sum()
    return x * (total / s) if s > 0 else np.full_like(x, total / len(x))


def _l1_capture(x: np.ndarray, best: np.ndarray, scale: float) -> float:
    return float(max(0.0, 1.0 - np.abs(x - best).sum() / scale))


# --- 1. water-filling (information theory) -------------------------------------------------------------------------
SOURCES = ["web", "code", "books", "papers", "forums", "news", "dialog", "math", "legal", "patents", "wiki", "qa"]


class WaterFilling(Simulator):
    key = "allocation"

    def params(self, seed: int) -> dict:
        rng = random.Random(seed * 7741 + 11)
        items = rng.sample(SOURCES, 8)
        floors = sorted(round(rng.uniform(0.4, 9.0), 2) for _ in items)
        level = (floors[4] + floors[5]) / 2  # five sources get compute, three get none
        budget = round(sum(level - f for f in floors[:5]), 1)
        rng.shuffle(floors)
        return {"items": items, "floors": floors, "budget": budget}

    def observables(self, p: dict) -> list[dict]:
        return [{"source": k, "floor": f} for k, f in zip(p["items"], p["floors"])]

    def _vector(self, plan: dict, p: dict) -> np.ndarray:
        return _rescale(self._raw(plan, p), p["budget"])

    def _value(self, x: np.ndarray, p: dict) -> float:
        return float(np.log1p(x / np.array(p["floors"])).sum())

    def optimum(self, p: dict) -> dict:
        n = np.array(p["floors"])
        lo, hi = 0.0, n.max() + p["budget"]
        for _ in range(200):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if np.maximum(0, mid - n).sum() < p["budget"] else (lo, mid)
        return self._plan(self.key, p["items"], np.maximum(0, lo - n))

    def baseline(self, p: dict) -> dict:
        return self._plan(self.key, p["items"], np.full(len(p["items"]), p["budget"] / len(p["items"])))

    def hint_capture(self, plan: dict, p: dict) -> float:
        return _l1_capture(self._vector(plan, p), self._vector(self.optimum(p), p), 2 * p["budget"])


class WaterFillingTrap(WaterFilling):
    """Paired sources overlap: compute on both partly duplicates. Water-filling over-feeds the clean pairs."""

    def params(self, seed: int) -> dict:
        p = super().params(seed)
        order = sorted(range(len(p["items"])), key=lambda i: p["floors"][i])
        p["pairs"] = [[p["items"][order[0]], p["items"][order[1]]], [p["items"][order[2]], p["items"][order[3]]]]
        p["overlap"] = 0.9
        return p

    def _value(self, x: np.ndarray, p: dict) -> float:
        idx = {k: i for i, k in enumerate(p["items"])}
        penalty = sum(x[idx[a]] * x[idx[b]] for a, b in p["pairs"]) * p["overlap"] / p["budget"]
        return float(np.log1p(x / np.array(p["floors"])).sum() - penalty)

    def concept_plan(self, p: dict) -> dict:
        return super().optimum(p)

    def optimum(self, p: dict) -> dict:
        key = ("trap", tuple(p["floors"]), p["budget"])
        if key not in _CACHE:
            x = self._vector(self.concept_plan(p), p)
            idx = {k: i for i, k in enumerate(p["items"])}
            partner = np.zeros(len(x), dtype=int) - 1
            for a, b in p["pairs"]:
                partner[idx[a]], partner[idx[b]] = idx[b], idx[a]
            n = np.array(p["floors"])
            for _ in range(20000):  # projected gradient ascent on the scaled simplex
                grad = 1 / (n + x) - np.where(partner >= 0, p["overlap"] / p["budget"] * x[partner], 0.0)
                nxt = _project(x + 0.05 * grad, p["budget"])
                done = np.abs(nxt - x).max() < 1e-13
                x = nxt
                if done:
                    break
            _CACHE[key] = self._plan(self.key, p["items"], x)
        return _CACHE[key]

    def hint_capture(self, plan: dict, p: dict) -> float:
        """How closely the plan follows the (here misleading) concept: high means it deferred to the notes."""
        return _l1_capture(self._vector(plan, p), self._vector(self.concept_plan(p), p), 2 * p["budget"])


_CACHE: dict = {}


def _project(v: np.ndarray, total: float) -> np.ndarray:
    """Euclidean projection onto {x >= 0, sum x = total}."""
    u = np.sort(v)[::-1]
    css = np.cumsum(u) - total
    rho = np.nonzero(u - css / (np.arange(len(v)) + 1) > 0)[0][-1]
    return np.maximum(v - css[rho] / (rho + 1), 0)


# --- 2. marginal value theorem (ecology) ---------------------------------------------------------------------------
SITES = ["forum.example", "docs.example", "shop.example", "blog.example", "news.example", "wiki.example",
         "jobs.example", "maps.example"]


class MarginalValue(Simulator):
    key = "dwell_minutes"

    def params(self, seed: int) -> dict:
        rng = random.Random(seed * 3301 + 5)
        items = rng.sample(SITES, 6)
        tau = [round(rng.uniform(3, 30), 1) for _ in items]
        rate = [round(rng.uniform(2, 40), 1) for _ in items]  # pages per minute on arrival
        return {"items": items, "tau": tau, "rate": rate, "switch": round(rng.uniform(2, 8), 1)}

    def observables(self, p: dict) -> list[dict]:
        return [{"site": k, "pages_per_minute_on_arrival": r, "half_life_minutes": round(t * math.log(2), 1)}
                for k, r, t in zip(p["items"], p["rate"], p["tau"])]

    def _vector(self, plan: dict, p: dict) -> np.ndarray:
        return self._raw(plan, p)

    def _value(self, t: np.ndarray, p: dict) -> float:
        tau, rate = np.array(p["tau"]), np.array(p["rate"])
        pages = (rate * tau * (1 - np.exp(-t / tau))).sum()
        return float(pages / (t.sum() + p["switch"] * len(t)))

    def _times(self, r: float, p: dict) -> np.ndarray:
        tau, rate = np.array(p["tau"]), np.array(p["rate"])
        return np.where(rate > r, tau * np.log(np.maximum(rate / r, 1.0)), 0.0)

    def optimum(self, p: dict) -> dict:
        lo, hi = 1e-9, max(p["rate"])
        for _ in range(200):  # leave each site when its rate falls to the best long-run rate
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if self._value(self._times(mid, p), p) > mid else (lo, mid)
        return self._plan(self.key, p["items"], self._times(lo, p))

    def baseline(self, p: dict) -> dict:
        return self._plan(self.key, p["items"], np.full(len(p["items"]), float(np.median(p["tau"]))))

    def hint_capture(self, plan: dict, p: dict) -> float:
        best = self._vector(self.optimum(p), p)
        return _l1_capture(self._vector(plan, p), best, best.sum())


# --- 3. Kelly criterion (gambling / information theory) -----------------------------------------------------------
TEAMS = ["search", "checkout", "mobile", "ads", "onboarding", "pricing", "growth", "infra", "support"]


class Kelly(Simulator):
    key = "stake_share"

    def params(self, seed: int) -> dict:
        rng = random.Random(seed * 9133 + 3)
        items = rng.sample(TEAMS, 6)
        p_win, payoff = [], []
        for i in range(6):
            b = round(rng.uniform(0.8, 4.0), 2)
            if i < 4:  # a positive edge: the Kelly stake f* = p - (1 - p) / b lies between 0.15 and 0.6
                q = (rng.uniform(0.15, 0.6) * b + 1) / (b + 1)
            else:  # a negative edge: stake nothing
                q = (1 - rng.uniform(0.03, 0.15)) / (1 + b)
            p_win.append(round(min(0.95, max(0.05, q)), 3))
            payoff.append(b)
        return {"items": items, "p": p_win, "b": payoff}

    def observables(self, p: dict) -> list[dict]:
        return [{"team": k, "success_chance": q, "payoff_multiple": b} for k, q, b in zip(p["items"], p["p"], p["b"])]

    def _validate_more(self, given: dict, p: dict) -> str | None:
        bad = {k: v for k, v in given.items() if v >= 1}
        return f"stake shares must be below 1: {bad}" if bad else None

    def _vector(self, plan: dict, p: dict) -> np.ndarray:
        return np.clip(self._raw(plan, p), 0.0, 0.999)

    def _value(self, f: np.ndarray, p: dict) -> float:
        q, b = np.array(p["p"]), np.array(p["b"])
        return float((q * np.log1p(f * b) + (1 - q) * np.log1p(-f)).sum())

    def optimum(self, p: dict) -> dict:
        q, b = np.array(p["p"]), np.array(p["b"])
        return self._plan(self.key, p["items"], np.maximum(0.0, q - (1 - q) / b))

    def baseline(self, p: dict) -> dict:
        return self._plan(self.key, p["items"], np.full(len(p["items"]), 0.25))

    def hint_capture(self, plan: dict, p: dict) -> float:
        return _l1_capture(self._vector(plan, p), self._vector(self.optimum(p), p), 0.5 * len(p["items"]))


# --- 4. square-root staffing (queueing theory) --------------------------------------------------------------------
QUEUES = ["billing", "returns", "tech", "accounts", "shipping", "sales", "fraud", "vip"]


class SqrtStaffing(Simulator):
    key = "agents"

    def params(self, seed: int) -> dict:
        rng = random.Random(seed * 4421 + 7)
        items = rng.sample(QUEUES, 6)
        load = [round(math.exp(rng.uniform(math.log(2), math.log(90))), 1) for _ in items]
        beta = rng.uniform(0.9, 1.6)
        total = round(sum(load) + beta * sum(math.sqrt(r) for r in load), 1)
        return {"items": items, "load": load, "staff": total}

    def observables(self, p: dict) -> list[dict]:
        return [{"line": k, "workload": r} for k, r in zip(p["items"], p["load"])]

    def _vector(self, plan: dict, p: dict) -> np.ndarray:
        return _rescale(self._raw(plan, p), p["staff"])

    def _value(self, s: np.ndarray, p: dict) -> float:
        r = np.array(p["load"])
        return float(-(np.sqrt(r) * np.exp(-(s - r) / np.sqrt(r))).sum())

    def optimum(self, p: dict) -> dict:
        r = np.array(p["load"])
        beta = (p["staff"] - r.sum()) / np.sqrt(r).sum()
        return self._plan(self.key, p["items"], r + beta * np.sqrt(r))

    def baseline(self, p: dict) -> dict:
        """The usual plan without the concept: agents in proportion to load."""
        r = np.array(p["load"])
        return self._plan(self.key, p["items"], r * p["staff"] / r.sum())

    def hint_capture(self, plan: dict, p: dict) -> float:
        """Distance to the concept's plan, relative to the baseline's distance (the plans differ only slightly)."""
        best = self._vector(self.optimum(p), p)
        return _l1_capture(self._vector(plan, p), best, np.abs(self._vector(self.baseline(p), p) - best).sum())


# --- 5. inverse-elasticity (Ramsey) rule (public economics) -------------------------------------------------------
PRODUCTS = ["storage", "seats", "api_calls", "exports", "support", "backups", "domains", "analytics", "sso"]


class InverseElasticity(Simulator):
    key = "markup"

    def params(self, seed: int) -> dict:
        rng = random.Random(seed * 6271 + 13)
        items = rng.sample(PRODUCTS, 7)
        eps = [round(math.exp(rng.uniform(math.log(0.3), math.log(4.0))), 2) for _ in items]
        volume = [int(math.exp(rng.uniform(math.log(80), math.log(3000)))) for _ in items]
        return {"items": items, "sensitivity": eps, "volume": volume, "target": round(0.08 * sum(volume), 1)}

    def observables(self, p: dict) -> list[dict]:
        return [{"product": k, "monthly_volume": v, "sensitivity": e}
                for k, v, e in zip(p["items"], p["volume"], p["sensitivity"])]

    def _vector(self, plan: dict, p: dict) -> np.ndarray:
        m, q = self._raw(plan, p), np.array(p["volume"], dtype=float)
        s = (q * m).sum()
        return m * (p["target"] / s) if s > 0 else np.full(len(m), p["target"] / q.sum())

    def _value(self, m: np.ndarray, p: dict) -> float:
        return float(-0.5 * (np.array(p["sensitivity"]) * np.array(p["volume"]) * m ** 2).sum())

    def optimum(self, p: dict) -> dict:
        eps, q = np.array(p["sensitivity"]), np.array(p["volume"], dtype=float)
        lam = p["target"] / (q / eps).sum()
        return self._plan(self.key, p["items"], lam / eps)

    def baseline(self, p: dict) -> dict:
        q = np.array(p["volume"], dtype=float)
        return self._plan(self.key, p["items"], np.full(len(q), p["target"] / q.sum()))

    def hint_capture(self, plan: dict, p: dict) -> float:
        q = np.array(p["volume"], dtype=float)
        x, best = self._vector(plan, p), self._vector(self.optimum(p), p)
        return float(max(0.0, 1.0 - (q * np.abs(x - best)).sum() / (2 * p["target"])))


# --- 6. Huffman prefix codes (information theory) ------------------------------------------------------------------
ACTIONS = ["weather", "timer", "music", "lights", "news", "shopping", "calendar", "calls", "messages", "traffic",
           "recipes", "translate", "reminders", "podcasts"]


class PrefixCode(Simulator):
    key = "depth"

    def params(self, seed: int) -> dict:
        rng = random.Random(seed * 5003 + 19)
        items = rng.sample(ACTIONS, 11)
        w = [rng.paretovariate(1.2) for _ in items]
        share = [round(x / sum(w), 4) for x in w]
        return {"items": items, "share": share}

    def observables(self, p: dict) -> list[dict]:
        return [{"action": k, "request_share": s} for k, s in zip(p["items"], p["share"])]

    def _validate_more(self, given: dict, p: dict) -> str | None:
        missing = sorted(set(p["items"]) - set(given))
        if missing:
            return f"every action needs a depth; missing {missing}"
        if any(v != int(v) or v < 1 for v in given.values()):
            return "depths must be whole numbers of at least 1"
        used = sum(2.0 ** -int(v) for v in given.values())
        return None if used <= 1 + 1e-9 else f"the depths need {used:.3f} of the tree; at most 1 is available"

    def _vector(self, plan: dict, p: dict) -> np.ndarray:
        return self._raw(plan, p)

    def _value(self, d: np.ndarray, p: dict) -> float:
        return float(-(np.array(p["share"]) * d).sum())

    def optimum(self, p: dict) -> dict:
        heap = [(s, i, [i]) for i, s in enumerate(p["share"])]
        heapq.heapify(heap)
        depth = [0] * len(p["share"])
        counter = len(heap)
        while len(heap) > 1:
            s1, _, a = heapq.heappop(heap)
            s2, _, b = heapq.heappop(heap)
            for i in a + b:
                depth[i] += 1
            heapq.heappush(heap, (s1 + s2, counter, a + b))
            counter += 1
        return {self.key: dict(zip(p["items"], depth))}

    def baseline(self, p: dict) -> dict:
        return {self.key: {k: math.ceil(math.log2(len(p["items"]))) for k in p["items"]}}

    def hint_capture(self, plan: dict, p: dict) -> float:
        share, best = np.array(p["share"]), self._vector(self.optimum(p), p)

        def miss(d: np.ndarray) -> float:
            return float((share * np.abs(d - best)).sum())

        return max(0.0, 1.0 - miss(self._vector(plan, p)) / miss(self._vector(self.baseline(p), p)))


SIMULATORS: dict[str, Simulator] = {
    "water_filling": WaterFilling(), "marginal_value": MarginalValue(), "kelly": Kelly(),
    "sqrt_staffing": SqrtStaffing(), "inverse_elasticity": InverseElasticity(), "prefix_code": PrefixCode(),
    "water_filling_trap": WaterFillingTrap(),
}
CONCEPTS = [c for c in SIMULATORS if not c.endswith("_trap")]
