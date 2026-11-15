import importlib
from datetime import timedelta

import pytest
from storex import store


@pytest.fixture(autouse=True)
def _fresh_store():
    store.clear()
    yield
    store.clear()


def _mod():
    return importlib.import_module("acme.surveys_leaderboard")


def test_R31_registry():
    from acme import registry
    assert registry.BACKENDS["surveys_leaderboard"] == "storex"


def test_R31_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.surveys_leaderboard to storex." in unreleased


def test_R31_keeps_best():
    m = _mod()
    m.submit("ann", 5)
    m.submit("ann", 3)
    m.submit("bob", 5)
    assert m.top(2) == [("ann", 5), ("bob", 5)]


def test_R31_top_across_pages():
    m = _mod()
    for i in range(80):
        m.submit(f"p{i:03d}", (i * 37) % 101 + 1)
    expected = sorted(((f"p{i:03d}", (i * 37) % 101 + 1) for i in range(80)), key=lambda kv: (-kv[1], kv[0]))
    assert m.top() == expected[:20] and m.top(80) == expected


def test_R31_rank():
    m = _mod()
    for i in range(70):
        m.submit(f"p{i:03d}", i + 1)
    assert m.rank("p069") == 1 and m.rank("p000") == 70 and m.rank("nobody") is None
