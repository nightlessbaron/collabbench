"""The per-track profile: every metric with a bootstrap interval, written as profile.json and profile.md."""

import json
import math
import random
import tomllib
from collections import defaultdict
from collections.abc import Callable
from pathlib import Path
from statistics import fmean

from collabbench.metrics import integrity, outcome, process
from collabbench.metrics.trial import TrialRecord

# (team condition, solo condition at equal total budget, k)
PAIRS = {"pool": [("team", "solo_2B", 2)], "inspire": [("team", "solo_2B", 2)],
         "swarm": [(f"team_k{k}", f"solo_k{k}", k) for k in (2, 4, 8)]}


def bootstrap_ci(values_by_instance: dict[str, list], stat: Callable[[list], float], n: int = 2000,
                 seed: int = 0, grouped: bool = False) -> tuple[float, float, float]:
    """(point estimate, 2.5th, 97.5th percentile). Each replicate resamples instances with replacement, then the
    runs within each drawn instance. `stat` gets the flat list of resampled items (with `grouped`, one list per drawn
    instance, so a statistic can be computed per instance); resamples where it raises
    ValueError or ZeroDivisionError or returns NaN are dropped."""
    nan = math.nan
    groups = [v for v in values_by_instance.values() if v]
    if not groups:
        return nan, nan, nan
    try:
        point = stat([list(g) for g in groups] if grouped else [x for g in groups for x in g])
    except (ValueError, ZeroDivisionError):
        point = nan
    rng = random.Random(seed)
    draws = []
    for _ in range(n):
        try:
            drawn = [[rng.choice(g) for _ in g] for g in rng.choices(groups, k=len(groups))]
            value = stat(drawn if grouped else [x for g in drawn for x in g])
        except (ValueError, ZeroDivisionError):
            continue
        if not math.isnan(value):
            draws.append(value)
    if not draws:
        return point, nan, nan
    draws.sort()
    return point, draws[int(0.025 * (len(draws) - 1))], draws[math.ceil(0.975 * (len(draws) - 1))]


def _mean(values: list) -> float:
    return fmean(values)


def _split(items: list[tuple[str, float]], *conditions: str) -> list[list[float]]:
    arms = [[v for c, v in items if c == cond] for cond in conditions]
    if not all(arms):
        raise ValueError("an arm is empty")
    return arms


def _arms(groups: list[list[tuple[str, float]]], *conditions: str) -> list[tuple[list[float], ...]]:
    """Per instance, the scores of each condition."""
    return [tuple([v for c, v in g if c == cond] for cond in conditions) for g in groups]


def _row(values_by_instance: dict[str, list], stat, n: int, grouped: bool = False) -> dict:
    point, lo, hi = bootstrap_ci(values_by_instance, stat, n, grouped=grouped)
    return {"value": point, "lo": lo, "hi": hi, "n": sum(len(v) for v in values_by_instance.values())}


def _facts(tasks_dir: Path, record: TrialRecord) -> list[dict] | None:
    path = Path(tasks_dir) / record.track / record.instance / "tests" / "facts.json"
    return json.loads(path.read_text()) if path.is_file() else None


def _reserved(tasks_dir: Path, record: TrialRecord) -> str | None:
    path = Path(tasks_dir) / record.track / record.instance / "task.toml"
    if not path.is_file():
        return None
    return tomllib.loads(path.read_text()).get("metadata", {}).get("collab", {}).get("reserved_script")


def _per_record(records: list[TrialRecord], fn) -> dict[str, list[float]]:
    out: dict[str, list[float]] = defaultdict(list)
    for r in records:
        value = fn(r)
        if value is not None:
            out[r.instance].append(float(value))
    return out


def _track_profile(track: str, records: list[TrialRecord], infra: int, tasks_dir: Path, n: int) -> dict[str, dict]:
    metrics: dict[str, dict] = {}
    by_cond: dict[str, list[TrialRecord]] = defaultdict(list)
    for r in records:
        by_cond[r.condition].append(r)
    for cond, rs in sorted(by_cond.items()):
        metrics[f"score[{cond}]"] = _row(_per_record(rs, lambda r: r.reward), _mean, n)

    def paired(*conds: str) -> dict[str, list[tuple[str, float]]]:
        out: dict[str, list] = defaultdict(list)
        for c in conds:
            for r in by_cond.get(c, []):
                out[r.instance].append((c, r.reward))
        return out

    for team, solo, k in PAIRS.get(track, []):
        metrics[f"collaboration_gain[{team}/{solo}]"] = _row(
            paired(team, solo), lambda x: outcome.collaboration_gain(*_split(x, team, solo)), n)
        metrics[f"interaction_gain[{team}]"] = _row(
            paired(team, "solo_B"),
            lambda gs: outcome.interaction_gain_by_instance(_arms(gs, team, "solo_B"), k), n, grouped=True)
        metrics[f"multiplier[{team}]"] = _row(
            paired(team, "solo_B"),
            lambda gs: outcome.multiplier_by_instance(_arms(gs, team, "solo_B"), k), n, grouped=True)
    if track != "swarm":
        def cvc(x):
            value = outcome.comm_value_captured(*_split(x, "team", "nocomm", "oracle"))
            return math.nan if value is None else value
        metrics["comm_value_captured"] = _row(paired("team", "nocomm", "oracle"), cvc, n)

    for name, fn in [("overrun", lambda r: integrity.liveness(r)["overrun"]),
                     ("deadlock", lambda r: integrity.liveness(r)["deadlock"]),
                     ("loops", lambda r: integrity.liveness(r)["loops"]),
                     ("say_do", integrity.say_do), ("fact_retention", integrity.fact_retention),
                     ("time_to_score[0.5]", lambda r: outcome.time_to_score(r.trace, 0.5)),
                     ("unauthorized", lambda r: integrity.unauthorized(r, _reserved(tasks_dir, r) or "\0")),
                     ("disclosure_precision",
                      lambda r: (integrity.disclosure_precision(r, f) if (f := _facts(tasks_dir, r)) else None)),
                     ("redundancy", process.redundancy), ("effective_contributors", process.effective_contributors),
                     ("uptake", process.uptake), ("critical_path_ratio", process.critical_path_ratio)]:
        for cond, rs in sorted(by_cond.items()):  # per condition: solo and team arms must not be averaged together
            rows = _per_record(rs, fn)
            if rows:
                metrics[f"{name}[{cond}]"] = _row(rows, _mean, n)
    for name in ("false_success", "no_report", "claim_accuracy"):
        def stat(rs, name=name):
            value = integrity.report_fidelity(rs)[name]
            if value is None:
                raise ValueError("no data")
            return value
        for cond, rs in sorted(by_cond.items()):
            metrics[f"{name}[{cond}]"] = _row(_by_instance(rs), stat, n)
    metrics["infra_error_trials"] = {"value": float(infra), "lo": math.nan, "hi": math.nan,
                                     "n": infra + len(records)}
    return metrics


def _by_instance(records: list[TrialRecord]) -> dict[str, list[TrialRecord]]:
    out: dict[str, list[TrialRecord]] = defaultdict(list)
    for r in records:
        out[r.instance].append(r)
    return out


def build_profile(records: list[TrialRecord], tasks_dir: Path, n: int = 2000) -> dict:
    """Per-track metrics over the trials that graded cleanly; infra-error trials are only counted."""
    by_track: dict[str, list[TrialRecord]] = defaultdict(list)
    for r in records:
        by_track[r.track].append(r)
    profile: dict = {}
    for track, all_records in sorted(by_track.items()):
        clean = [r for r in all_records if not r.infra_error]
        profile[track] = _track_profile(track, clean, len(all_records) - len(clean), Path(tasks_dir), n)
    return profile


def _fmt(x: float | None, digits: int = 3) -> str:
    if x is None or math.isnan(x):
        return "-"
    return ("-" if x < 0 else "") + "∞" if math.isinf(x) else f"{x:.{digits}f}"


def _strict(obj):
    """NaN -> null, +/-inf -> "inf"/"-inf", so the JSON is valid for any parser."""
    if isinstance(obj, dict):
        return {k: _strict(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_strict(v) for v in obj]
    if isinstance(obj, float):
        if math.isnan(obj):
            return None
        if math.isinf(obj):
            return "inf" if obj > 0 else "-inf"
    return obj


def write_profile(profile: dict, out: Path) -> None:
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "profile.json").write_text(json.dumps(_strict(profile), indent=1, allow_nan=False))
    lines = ["# CollabBench profile", ""]
    for track, metrics in profile.items():
        lines += [f"## {track}", "", "| metric | value | 95% interval | n |", "|---|---|---|---|"]
        for name, m in metrics.items():
            lines.append(f"| {name} | {_fmt(m['value'])} | [{_fmt(m['lo'])}, {_fmt(m['hi'])}] | {m['n']} |")
        lines.append("")
    (out / "profile.md").write_text("\n".join(lines))
