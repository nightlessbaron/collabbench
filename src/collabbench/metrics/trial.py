"""Load Harbor trial directories into TrialRecords."""

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from collabbench.harness.events import EventLog


@dataclass
class TrialRecord:
    track: str
    instance: str
    condition: str
    trial_id: str
    reward: float | None
    requirements: dict[str, bool]
    extras: dict
    report: dict | None
    status: str
    events: list[dict] = field(default_factory=list)
    trace: list[dict] = field(default_factory=list)
    tokens: int = 0
    wall_s: float = 0.0
    infra_error: bool = False


def _json(path: Path):
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def _wall_s(result: dict | None) -> float:
    span = ((result or {}).get("agent_execution") or {})
    try:
        start, end = (datetime.fromisoformat(span[k].replace("Z", "+00:00")) for k in ("started_at", "finished_at"))
    except (KeyError, AttributeError, ValueError):
        return 0.0
    return (end - start).total_seconds()


def load_trial(trial: Path, instance: str, condition: str) -> TrialRecord:
    reward_json = _json(trial / "verifier" / "reward.json")
    details = _json(trial / "verifier" / "details.json") or {}
    outcome = _json(trial / "agent" / "collab" / "outcome.json") or {}
    events_path = trial / "agent" / "collab" / "events.jsonl"
    events = EventLog.read(events_path) if events_path.is_file() else []
    reward, requirements, extras = None, {}, {}
    if reward_json is not None:
        for key, value in reward_json.items():
            if key == "reward":
                reward = float(value)
            elif key.startswith("req_"):
                requirements[key[4:]] = bool(value)
            else:
                extras[key] = value
    tokens = int(outcome.get("tokens_in", 0)) + int(outcome.get("tokens_out", 0))
    if not tokens:
        tokens = sum(e["tokens_in"] + e["tokens_out"] for e in events)
    unavailable = any(e["type"] == "error" and e["payload"].get("kind") == "LLMUnavailable" for e in events)
    return TrialRecord(
        track=instance.split("-")[0], instance=instance, condition=condition, trial_id=trial.name, reward=reward,
        requirements=requirements, extras=extras, report=outcome.get("report"),
        status=outcome.get("status", "no_outcome"), events=events, trace=details.get("trace", []), tokens=tokens,
        wall_s=_wall_s(_json(trial / "result.json")),
        infra_error=reward is None or bool(extras.get("verifier_error")) or unavailable)


def load_trials(runs_dir: Path) -> list[TrialRecord]:
    """Every trial under `runs_dir`. Job directories are named `<instance>--<condition>--<timestamp>`."""
    records = []
    for job in sorted(p for p in Path(runs_dir).rglob("*") if p.is_dir() and p.name.count("--") == 2):
        instance, condition, _ = job.name.split("--")
        for result in sorted(job.glob("*/result.json")):
            records.append(load_trial(result.parent, instance, condition))
    return records
