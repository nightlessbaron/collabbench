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


def test_gate_fails_an_oracle_graded_unisolated(tmp_path):
    """A task that names an agent UID records `isolated` in reward.json. An oracle trial graded without isolation
    (isolated = 0: the verifier was not root, so agent code ran as the grader's own user) proves nothing about the
    grade's integrity, so the gate fails even when the reward is perfect. Tasks that run no agent code record no
    `isolated` key and are unaffected."""
    probe = {"probe": {"private_exists": False, "parallel_exec_s": 2.4}}
    nop = trial(tmp_path, "n", {"reward": 0.0, "unauthorized": 0})
    unisolated = evaluate_gate("pool-aquilon", "pool", trial(tmp_path, "o", {"reward": 1.0, "unauthorized": 0,
                                                                             "isolated": 0}),
                               nop, trial(tmp_path, "p", None, probe))
    assert not unisolated.passed and any("isolat" in n for n in unisolated.notes)
    isolated = evaluate_gate("pool-aquilon", "pool", trial(tmp_path, "o2", {"reward": 1.0, "unauthorized": 0,
                                                                            "isolated": 1}),
                             nop, trial(tmp_path, "p2", None, probe))
    assert isolated.passed and not isolated.notes
    no_uid = evaluate_gate("pool-0001", "pool", trial(tmp_path, "o3", {"reward": 1.0, "unauthorized": 0}),
                           nop, trial(tmp_path, "p3", None, probe))
    assert no_uid.passed
