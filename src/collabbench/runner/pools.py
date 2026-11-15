"""Modal pools (profile + environment + cap) and the sandbox cost model."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Pool:
    name: str
    profile: str  # ~/.modal.toml profile, selected with MODAL_PROFILE (the active profile is never changed)
    environment: str  # Modal environment, selected with MODAL_ENVIRONMENT
    cap_usd: float  # the runner stops before this; the real budget is a little higher


POOLS = {
    "personal": Pool("personal", "nightlessbaron", "main", 180.0),  # $200 credit
    "ifm": Pool("ifm", "mbzuai-ifm", "rl-graph-taskmaker", 45.0),  # $50 budget
}
POOL_ORDER = ["personal", "ifm"]  # user decision 2026-11-15: personal pays first

# Modal sandbox rates (non-preemptible), modal.com/pricing as read on 2026-11-15.
RATES = {"cpu_core_s": 0.00003942, "mem_gib_s": 0.00000667}


def trial_cost(agent_s: float, verifier_s: float, cpus: float = 1, mem_gib: float = 2) -> float:
    per_s = cpus * RATES["cpu_core_s"] + mem_gib * RATES["mem_gib_s"]
    return (max(0.0, agent_s) + max(0.0, verifier_s)) * per_s
