import json
import math

import pytest

from collabbench.metrics.profile import bootstrap_ci, build_profile, write_profile
from collabbench.metrics.trial import load_trials


def _runs(make_trial, tmp_path):
    runs = tmp_path / "r"
    for inst in ("pool-0001", "pool-0002"):
        for cond, rewards in {"team": [1.0, 0.5], "solo_2B": [0.5, 0.5], "solo_B": [0.0, 1.0],
                              "nocomm": [0.0, 0.0], "oracle": [1.0, 1.0]}.items():
            for i, r in enumerate(rewards):
                make_trial(instance=inst, condition=cond, trial=f"{cond}{i}", reward=r, runs=runs)
    make_trial(instance="pool-0001", condition="team", trial="infra", reward=None, runs=runs)
    make_trial(instance="swarm-0001", condition="solo_B", trial="s", reward=0.4, runs=runs)
    return runs


def test_bootstrap_ci_brackets_point():
    point, lo, hi = bootstrap_ci({"a": [0.0, 0.2], "b": [0.8, 1.0], "c": [0.4]}, lambda v: sum(v) / len(v), n=300)
    assert point == pytest.approx(0.48) and lo <= point <= hi
    assert bootstrap_ci({"a": [0.5]}, lambda v: sum(v) / len(v), n=50) == (0.5, 0.5, 0.5)
    assert all(math.isnan(x) for x in bootstrap_ci({}, len, n=5))


def test_infra_errors_excluded_from_scores(make_trial, tmp_path):
    records = load_trials(_runs(make_trial, tmp_path))
    prof = build_profile(records, tmp_path / "tasks", n=50)
    assert prof["pool"]["score[team]"]["n"] == 4  # the infra-error team trial is not scored
    assert prof["pool"]["score[team]"]["value"] == pytest.approx(0.75)
    assert prof["pool"]["infra_error_trials"]["value"] == 1


def test_profile_metrics_values(make_trial, tmp_path):
    prof = build_profile(load_trials(_runs(make_trial, tmp_path)), tmp_path / "tasks", n=50)["pool"]
    assert prof["collaboration_gain[team/solo_2B]"]["value"] == pytest.approx(1.5)
    assert prof["comm_value_captured"]["value"] == pytest.approx(0.75)
    assert prof["multiplier[team]"]["value"] == pytest.approx(1.0)  # solo_B pooled [0,0,1,1]: best of 2 = 5/6 >= 0.75, k'=2


def test_profile_md_has_one_table_per_track(make_trial, tmp_path):
    prof = build_profile(load_trials(_runs(make_trial, tmp_path)), tmp_path / "tasks", n=50)
    out = tmp_path / "out"
    write_profile(prof, out)
    md = (out / "profile.md").read_text()
    assert md.count("| metric | value | 95% interval | n |") == 2
    assert "## pool" in md and "## swarm" in md
    assert set(json.loads((out / "profile.json").read_text())) == {"pool", "swarm"}


def test_profile_json_is_strict(make_trial, tmp_path):
    runs = tmp_path / "r"
    for i in range(3):
        make_trial(condition="team", trial=f"t{i}", reward=1.0, runs=runs)
        make_trial(condition="solo_B", trial=f"s{i}", reward=0.0, runs=runs)
    prof = build_profile(load_trials(runs), tmp_path / "tasks", n=20)["pool"]
    assert prof["multiplier[team]"]["value"] == math.inf  # unreached
    assert math.isnan(prof["infra_error_trials"]["lo"])  # an empty interval
    write_profile({"pool": prof}, tmp_path / "out")

    def reject(constant):
        raise ValueError(constant)
    data = json.loads((tmp_path / "out" / "profile.json").read_text(), parse_constant=reject)
    assert data["pool"]["multiplier[team]"]["value"] == "inf"
    assert data["pool"]["infra_error_trials"]["lo"] is None
    assert "∞" in (tmp_path / "out" / "profile.md").read_text()


def test_best_of_k_is_per_instance(make_trial, tmp_path):
    runs = tmp_path / "r"
    for inst, team, solo in (("pool-0001", 1.0, 1.0), ("pool-0002", 0.2, 0.0)):
        make_trial(instance=inst, condition="team", trial="t", reward=team, runs=runs)
        for i in range(2):
            make_trial(instance=inst, condition="solo_B", trial=f"s{i}", reward=solo, runs=runs)
    prof = build_profile(load_trials(runs), tmp_path / "tasks", n=20)["pool"]
    # per instance: (1.0 - 1.0) and (0.2 - 0.0) average to 0.1; pooled solo scores [0,0,1,1] would give -0.233
    assert prof["interaction_gain[team]"]["value"] == pytest.approx(0.1)
    # team mean 0.6 is above every per-instance best-of-k' mean (0.5), though pooled best-of-2 is 5/6
    assert prof["multiplier[team]"]["value"] == math.inf


def test_process_metrics_are_keyed_by_condition(make_trial, tmp_path):
    from tests.metrics.conftest import ev
    runs = tmp_path / "r"
    both = [ev("agent-0", "llm_call"), ev("agent-1", "llm_call")]
    make_trial(condition="team", trial="t", events=both, runs=runs)
    make_trial(condition="solo_2B", trial="s", events=[ev("agent-0", "llm_call")], runs=runs)
    prof = build_profile(load_trials(runs), tmp_path / "tasks", n=20)["pool"]
    assert prof["critical_path_ratio[team]"]["value"] == 0.5
    assert prof["critical_path_ratio[solo_2B]"]["value"] == 1.0
    assert "critical_path_ratio" not in prof and "false_success[team]" in prof
