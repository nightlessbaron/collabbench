import json
from pathlib import Path

import pytest

from collabbench.harness.config import TeamSettings
from collabbench.runner.conditions import CONDITIONS, condition_kwargs
from collabbench.runner.grid import load_grid
from collabbench.runner.harbor import harbor_command, harbor_env, trial_sandbox_seconds
from collabbench.runner.ledger import BudgetExceeded, Ledger, choose_pool
from collabbench.runner.pools import POOL_ORDER, POOLS, trial_cost


def test_condition_table_matches_spec():
    assert condition_kwargs("pool", "solo_2B", 1000) == {"team_size": "1", "budget": "1000", "budget_total": "2000",
                                                         "facts": "shared"}
    assert condition_kwargs("pool", "nocomm", 1000) == {"team_size": "2", "budget": "1000", "channel": "closed",
                                                        "workspace": "isolated"}
    assert condition_kwargs("inspire", "placebo", 1000) == {"team_size": "2", "budget": "1000", "placebo": "expert"}
    assert condition_kwargs("inspire", "solo_2B", 1000) == {"team_size": "1", "budget": "1000", "budget_total": "2000"}
    assert condition_kwargs("inspire", "oracle", 1000)["facts"] == "shared"
    assert condition_kwargs("swarm", "team_k4", 1000) == {"team_size": "4", "budget": "1000", "topology": "lead"}
    assert condition_kwargs("swarm", "solo_k8", 1000)["budget_total"] == "8000"
    with pytest.raises(KeyError):
        condition_kwargs("pool", "team_k4", 1000)


def test_every_condition_is_valid_team_settings():
    for track, conds in CONDITIONS.items():
        for cond in conds:
            TeamSettings.from_kwargs(condition_kwargs(track, cond, 5000))


def test_trial_cost_matches_rates():
    assert trial_cost(3600, 0) == pytest.approx(0.1419 + 0.0480, abs=1e-3)
    assert trial_cost(0, 1800, cpus=2, mem_gib=4) == pytest.approx(1800 * (2 * 0.00003942 + 4 * 0.00000667))


def test_pools_are_separate_and_ordered(tmp_path):
    assert POOL_ORDER == ["personal", "ifm"]
    assert POOLS["personal"].profile == "nightlessbaron" and POOLS["personal"].environment == "main"
    assert POOLS["ifm"].environment == "rl-graph-taskmaker" and POOLS["ifm"].cap_usd == 45.0
    ledger = Ledger(tmp_path / "ledger.jsonl")
    ledger.record("personal", "j", "t1", 10.0)
    ledger.record("ifm", "j", "t2", 1.5)
    assert ledger.spent("personal") == 10.0 and ledger.spent("ifm") == 1.5
    assert Ledger(tmp_path / "ledger.jsonl").spent("personal") == 10.0  # persisted


def test_ledger_refuses_over_cap(tmp_path):
    ledger = Ledger(tmp_path / "ledger.jsonl")
    ledger.record("ifm", "j", "t", 44.9)
    with pytest.raises(BudgetExceeded):
        ledger.check("ifm", 0.2)
    ledger.check("ifm", 0.05)


def test_choose_pool_falls_back_in_order(tmp_path):
    ledger = Ledger(tmp_path / "ledger.jsonl")
    assert choose_pool(ledger, "personal", 1.0).name == "personal"
    ledger.record("personal", "j", "t", 179.5)
    assert choose_pool(ledger, "personal", 1.0).name == "ifm"
    ledger.record("ifm", "j", "t", 44.5)
    with pytest.raises(BudgetExceeded):
        choose_pool(ledger, "personal", 1.0)


def write_grid(tmp_path: Path) -> Path:
    for i in (1, 2):
        (tmp_path / "tasks" / "pool" / f"pool-000{i}").mkdir(parents=True)
    grid = tmp_path / "g.yaml"
    grid.write_text("pool: personal\nmodel: deepseek-v4-1-flash-1017\neffort: high\nconcurrency: 8\n"
                    "tracks:\n  pool:\n    budget: 1000\n    instances: [tasks/pool/*]\n"
                    "    conditions: {team: 3, solo_B: 4}\n")
    return grid


def test_grid_expands_runs(tmp_path):
    g = load_grid(write_grid(tmp_path))
    cells = g.cells()
    assert len(cells) == 4 and g.pool == "personal" and g.concurrency == 8
    team = [c for c in cells if c.condition == "team"]
    assert team[0].runs == 3 and team[0].kwargs["effort"] == "high" and team[0].task_dir.name == "pool-0001"


def test_command_has_no_key(tmp_path, monkeypatch):
    monkeypatch.setenv("COLLAB_LLM_BASE_URL", "http://stale/v1")
    cell = load_grid(write_grid(tmp_path)).cells()[0]
    cmd = harbor_command(cell, tmp_path / "jobs", "job1", "deepseek-v4-1-flash-1017", 8)
    env = harbor_env(POOLS["personal"], key="sk-NOT-ON-ARGV")
    assert not any("sk-NOT-ON-ARGV" in part for part in cmd)
    assert env["COLLAB_LLM_API_KEY"] == "sk-NOT-ON-ARGV"
    assert env["MODAL_PROFILE"] == "nightlessbaron" and env["MODAL_ENVIRONMENT"] == "main"
    assert "COLLAB_LLM_BASE_URL" not in env  # the harness re-reads Comet's live gateway URL itself
    assert cmd[cmd.index("-a") + 1] == "collabbench.harness.team:TeamAgent"
    assert cmd[cmd.index("-e") + 1] == "modal" and cmd[cmd.index("-k") + 1] == "3"
    assert "--ak" in cmd and "team_size=2" in cmd


def test_trial_sandbox_seconds(tmp_path):
    (tmp_path / "result.json").write_text(json.dumps({
        "started_at": "2026-11-15T01:00:00Z", "finished_at": "2026-11-15T01:31:00Z",
        "verifier": {"started_at": "2026-11-15T01:25:00Z", "finished_at": "2026-11-15T01:30:30Z"}}))
    assert trial_sandbox_seconds(tmp_path) == (1500.0, 330.0)
