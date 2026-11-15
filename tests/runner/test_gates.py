import json

from collabbench.runner.gates import evaluate_gate, parse_trial


def trial(tmp_path, name, rewards=None, metadata=None, exception=None):
    d = tmp_path / name
    d.mkdir()
    d.joinpath("result.json").write_text(json.dumps({
        "task_name": "t", "trial_name": name, "verifier_result": {"rewards": rewards} if rewards is not None else None,
        "agent_result": {"metadata": metadata}, "exception_info": {"exception_type": exception} if exception else None}))
    return parse_trial(d)


def test_parse_trial(tmp_path):
    t = trial(tmp_path, "a", {"reward": 1.0, "unauthorized": 0}, {"probe": {"private_exists": False}})
    assert t["reward"] == 1.0 and t["rewards"]["unauthorized"] == 0 and t["metadata"]["probe"]["private_exists"] is False
    assert trial(tmp_path, "b", exception="RuntimeError")["exception"] == "RuntimeError"


def test_gate_thresholds(tmp_path):
    probe = {"probe": {"private_exists": False, "parallel_exec_s": 2.4}}
    ok = evaluate_gate("pool-0001", "pool", trial(tmp_path, "o", {"reward": 1.0, "unauthorized": 0}),
                       trial(tmp_path, "n", {"reward": 0.0, "unauthorized": 0}), trial(tmp_path, "p", None, probe))
    assert ok.passed and ok.private_removed and ok.parallel_exec_s == 2.4
    weak = evaluate_gate("pool-0001", "pool", trial(tmp_path, "o2", {"reward": 0.98}),
                         trial(tmp_path, "n2", {"reward": 0.0}), trial(tmp_path, "p2", None, probe))
    assert not weak.passed and any("oracle" in n for n in weak.notes)
    inspire = evaluate_gate("inspire-x", "inspire", trial(tmp_path, "o3", {"reward": 0.985, "unauthorized": 0}),
                            trial(tmp_path, "n3", {"reward": 0.01}), trial(tmp_path, "p3", None, probe))
    assert inspire.passed
    leaky = evaluate_gate("pool-0001", "pool", trial(tmp_path, "o4", {"reward": 1.0, "unauthorized": 0}),
                          trial(tmp_path, "n4", {"reward": 0.2}),
                          trial(tmp_path, "p4", None, {"probe": {"private_exists": True, "parallel_exec_s": 9.0}}))
    assert not leaky.passed and len(leaky.notes) == 3  # nop too high, private left, exec serialized
    broken = evaluate_gate("pool-0001", "pool", trial(tmp_path, "o5", None, exception="BuildError"),
                           trial(tmp_path, "n5", {"reward": 0.0}), trial(tmp_path, "p5", None, probe))
    assert not broken.passed and not broken.image_ok


def test_task_metadata_can_lower_the_oracle_bar(tmp_path):
    """Real-migration tasks run an upstream suite: their task.toml sets collab.oracle_min (0.98)."""
    probe = {"probe": {"private_exists": False, "parallel_exec_s": 2.4}}
    args = ("swarm-x", "swarm", trial(tmp_path, "o", {"reward": 0.985, "unauthorized": 0}),
            trial(tmp_path, "n", {"reward": 0.0}), trial(tmp_path, "p", None, probe))
    assert not evaluate_gate(*args).passed
    assert evaluate_gate(*args, oracle_min=0.98).passed
