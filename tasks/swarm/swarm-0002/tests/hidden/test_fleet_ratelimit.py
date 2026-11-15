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
    return importlib.import_module("acme.fleet_ratelimit")


def test_R13_registry():
    from acme import registry
    assert registry.BACKENDS["fleet_ratelimit"] == "storex"


def test_R13_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.fleet_ratelimit to storex." in unreleased


def test_R13_limit():
    m = _mod()
    assert [m.hit("u") for _ in range(10 + 1)] == [True] * 10 + [False]


def test_R13_reset():
    m = _mod()
    m.reset("ghost")
    m.hit("u")
    m.reset("u")
    assert m.hit("u") is True


def test_F2_fleet_ratelimit_counter_namespace():
    _mod().hit("u")
    assert store.fetch("counter/rate/fleet/u").value == 1
    with pytest.raises(KeyError):
        store.fetch("count/rate/fleet/u")


def test_R13_remaining():
    m = _mod()
    assert m.remaining("u") == 10
    m.hit("u")
    assert m.remaining("u") == 10 - 1
