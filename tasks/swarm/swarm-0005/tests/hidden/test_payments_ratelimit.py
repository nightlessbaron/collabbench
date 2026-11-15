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
    return importlib.import_module("acme.payments_ratelimit")


def test_R19_registry():
    from acme import registry
    assert registry.BACKENDS["payments_ratelimit"] == "storex"


def test_R19_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.payments_ratelimit to storex." in unreleased


def test_R19_limit():
    m = _mod()
    assert [m.hit("u") for _ in range(3 + 1)] == [True] * 3 + [False]


def test_R19_reset():
    m = _mod()
    m.reset("ghost")
    m.hit("u")
    m.reset("u")
    assert m.hit("u") is True


def test_F2_payments_ratelimit_counter_namespace():
    _mod().hit("u")
    assert store.fetch("counter/rate/payments/u").value == 1
    with pytest.raises(KeyError):
        store.fetch("count/rate/payments/u")


def test_R19_remaining():
    m = _mod()
    assert m.remaining("u") == 3
    m.hit("u")
    assert m.remaining("u") == 3 - 1
