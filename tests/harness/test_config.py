import pytest

from collabbench.harness.config import TeamSettings


def test_from_kwargs_casts_and_validates():
    s = TeamSettings.from_kwargs({"team_size": "4", "topology": "lead"})
    assert s.team_size == 4 and s.topology == "lead"
    with pytest.raises(ValueError):
        TeamSettings.from_kwargs({"topology": "lead"})  # lead needs team_size >= 2


def test_from_kwargs_none_bool_and_unknown():
    s = TeamSettings.from_kwargs({"placebo": "none", "context_cap": "none", "probe": "true", "budget_total": "800000"})
    assert s.placebo is None and s.context_cap is None and s.probe is True and s.budget_total == 800000
    with pytest.raises(ValueError):
        TeamSettings.from_kwargs({"teamsize": "2"})


def test_from_kwargs_accepts_typed_values():
    assert TeamSettings.from_kwargs({"team_size": 2, "probe": False}).team_size == 2


def test_isolated_requires_closed_channel():
    with pytest.raises(ValueError):
        TeamSettings(team_size=2, workspace="isolated")
    assert TeamSettings(team_size=2, workspace="isolated", channel="closed").workspace == "isolated"


def test_bad_enum_value_raises():
    with pytest.raises(ValueError):
        TeamSettings(facts="everything")


def test_pool_total_defaults_to_k_times_b():
    assert TeamSettings(team_size=4, budget=1000).pool_total() == 4000
    assert TeamSettings(team_size=4, budget=1000, budget_total=2500).pool_total() == 2500


def test_solo_budget():
    assert TeamSettings(budget=1000).solo_budget() == 1000
    assert TeamSettings(budget=1000, budget_total=8000).solo_budget() == 8000


def test_defaults_match_spec():
    s = TeamSettings()
    assert (s.team_size, s.topology, s.budget, s.channel, s.facts, s.context_cap, s.effort) == (
        1, "peers", 400_000, "open", "private", None, "high")
    assert (s.max_turns, s.evaluate_cap, s.snapshot_every_s, s.max_snapshots, s.idle_grace_s) == (400, 12, 180, 24, 60)
