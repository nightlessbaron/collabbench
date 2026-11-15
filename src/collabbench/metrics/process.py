"""Process metrics from the event log and the per-agent snapshot traces."""

from collections import Counter

from collabbench.metrics.trial import TrialRecord


def _commands(record: TrialRecord) -> list[tuple[str, str]]:
    return [(e["agent"], " ".join(e["payload"].get("command", "").split())) for e in record.events
            if e["type"] == "action"]


def redundancy(record: TrialRecord) -> float | None:
    """Share of commands that a different agent had already run (None without commands)."""
    ran_by: dict[str, set[str]] = {}
    repeats = 0
    commands = _commands(record)
    for agent, command in commands:
        seen = ran_by.setdefault(command, set())
        repeats += bool(seen - {agent})
        seen.add(agent)
    return repeats / len(commands) if commands else None


def effective_contributors(record: TrialRecord) -> int | None:
    """Agents whose own final snapshot (a trace row labelled with the agent's name) meets a requirement.
    None when the run kept no per-agent snapshots (shared workspace)."""
    agents = {e["agent"] for e in record.events if e["type"] == "llm_call"}
    last: dict[str, dict] = {}
    for row in sorted(record.trace, key=lambda p: p["t"]):
        if row.get("label") in agents:
            last[row["label"]] = row
    if not last:
        return None
    return sum(any(row.get("requirements", {}).values()) for row in last.values())


def uptake(record: TrialRecord) -> float | None:
    """Imports of a peer's finding per published finding (None when nothing was published)."""
    published = sum(e["type"] == "publish" for e in record.events)
    imported = sum(e["type"] == "import" and e["payload"].get("author") != e["agent"] for e in record.events)
    return imported / published if published else None


def critical_path_ratio(record: TrialRecord) -> float | None:
    """The most turns taken by any one agent over all turns (1 means one agent did everything)."""
    turns = Counter(e["agent"] for e in record.events if e["type"] == "llm_call")
    return max(turns.values()) / sum(turns.values()) if turns else None
