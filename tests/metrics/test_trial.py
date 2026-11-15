from collabbench.metrics.trial import load_trials
from tests.metrics.conftest import ev


def test_loads_condition_track_and_scores(make_trial):
    runs = make_trial(condition="solo_2B", reward=0.5, requirements={"R1": True, "R2": False},
                      extras={"tests_passed": 3.0},
                      report={"done": True, "requirements": {}}, events=[ev("agent-0", "llm_call", 1, 5, 2)],
                      trace=[{"t": 1, "reward": 0.5, "tokens_so_far": 10, "requirements": {}}])
    (rec,) = load_trials(runs)
    assert (rec.track, rec.instance, rec.condition, rec.trial_id) == ("pool", "pool-0001", "solo_2B", "t1")
    assert rec.reward == 0.5 and rec.requirements == {"R1": True, "R2": False}
    assert rec.extras["tests_passed"] == 3.0 and rec.tokens == 120 and rec.wall_s == 120.5
    assert rec.status == "finished" and len(rec.events) == 1 and len(rec.trace) == 1
    assert not rec.infra_error


def test_infra_error_flags(make_trial, tmp_path):
    runs = tmp_path / "r"
    make_trial(trial="none", reward=None, runs=runs)
    make_trial(trial="verr", reward=0.0, extras={"verifier_error": 1}, runs=runs)
    make_trial(trial="llm", reward=0.0, events=[ev("agent-0", "error", kind="LLMUnavailable")], runs=runs)
    make_trial(trial="ok", reward=0.0, events=[ev("agent-0", "error", kind="ValueError")], runs=runs)
    flags = {r.trial_id: r.infra_error for r in load_trials(runs)}
    assert flags == {"none": True, "verr": True, "llm": True, "ok": False}


def test_missing_outcome_still_loads(make_trial):
    (rec,) = load_trials(make_trial(outcome=False))
    assert rec.status == "no_outcome" and rec.report is None


def test_truncated_events_line_is_skipped_and_counted(make_trial):
    runs = make_trial(events=[ev("agent-0", "llm_call", 1, 5, 2)])
    log = next(runs.rglob("events.jsonl"))
    log.write_text(log.read_text() + '{"t": 3, "agent": "agent-1", "ty')
    (rec,) = load_trials(runs)
    assert len(rec.events) == 1 and rec.bad_event_lines == 1 and rec.reward == 1.0


def test_trial_dir_without_result_json_is_infra_error(make_trial):
    runs = make_trial(trial="good")
    job = next(runs.glob("pool-0001--*"))
    (job / "dead" / "agent").mkdir(parents=True)
    by_id = {r.trial_id: r for r in load_trials(runs)}
    assert by_id["dead"].infra_error and by_id["dead"].reward is None
    assert not by_id["good"].infra_error
