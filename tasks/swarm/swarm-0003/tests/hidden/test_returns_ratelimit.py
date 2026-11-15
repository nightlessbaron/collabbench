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
    return importlib.import_module("acme.returns_ratelimit")


def test_R25_registry():
    from acme import registry
    assert registry.BACKENDS["returns_ratelimit"] == "storex"


def test_R25_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.returns_ratelimit to storex." in unreleased


def test_R25_limit():
    m = _mod()
    assert [m.hit("u") for _ in range(7 + 1)] == [True] * 7 + [False]


def test_R25_reset():
    m = _mod()
    m.reset("ghost")
    m.hit("u")
    m.reset("u")
    assert m.hit("u") is True


def test_F2_returns_ratelimit_counter_namespace():
    _mod().hit("u")
    assert store.fetch("counter/rate/returns/u").value == 1
    with pytest.raises(KeyError):
        store.fetch("count/rate/returns/u")


def test_R25_remaining():
    m = _mod()
    assert m.remaining("u") == 7
    m.hit("u")
    assert m.remaining("u") == 7 - 1
