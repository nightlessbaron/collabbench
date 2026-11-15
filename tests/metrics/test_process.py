import pytest

from collabbench.metrics.process import critical_path_ratio, effective_contributors, redundancy, uptake
from tests.metrics.conftest import ev
from tests.metrics.test_integrity import rec


def test_redundancy_counts_commands_a_peer_already_ran():
    events = [ev("agent-0", "action", command="ls  -la"), ev("agent-1", "action", command="ls -la"),
              ev("agent-1", "action", command="pytest"), ev("agent-0", "action", command="ls -la")]
    assert redundancy(rec(events=events)) == pytest.approx(0.5)
    assert redundancy(rec(events=[])) is None


def test_uptake_counts_only_peer_imports():
    events = [ev("agent-0", "publish", id=1), ev("agent-0", "publish", id=2),
              ev("agent-1", "import", id=1, author="agent-0"), ev("agent-0", "import", id=1, author="agent-0")]
    assert uptake(rec(events=events)) == pytest.approx(0.5)
    assert uptake(rec(events=[])) is None


def test_critical_path_ratio():
    events = [ev("agent-0", "llm_call")] * 3 + [ev("agent-1", "llm_call")]
    assert critical_path_ratio(rec(events=events)) == pytest.approx(0.75)


def test_effective_contributors_from_per_agent_snapshots():
    events = [ev("agent-0", "llm_call"), ev("agent-1", "llm_call")]
    trace = [{"t": 5, "label": "agent-0", "requirements": {"R1": True}},
             {"t": 5, "label": "agent-1", "requirements": {"R1": False}},
             {"t": 6, "label": "workspace", "requirements": {"R1": True}}]
    assert effective_contributors(rec(events=events, trace=trace)) == 1
    assert effective_contributors(rec(events=events, trace=trace[2:])) is None
