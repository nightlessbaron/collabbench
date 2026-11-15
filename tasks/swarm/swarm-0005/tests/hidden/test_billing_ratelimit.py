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
    return importlib.import_module("acme.billing_ratelimit")


def test_R2_registry():
    from acme import registry
    assert registry.BACKENDS["billing_ratelimit"] == "storex"


def test_R2_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.billing_ratelimit to storex." in unreleased


def test_R2_limit():
    m = _mod()
    assert [m.hit("u") for _ in range(5 + 1)] == [True] * 5 + [False]


def test_R2_reset():
    m = _mod()
    m.reset("ghost")
    m.hit("u")
    m.reset("u")
    assert m.hit("u") is True


def test_F2_billing_ratelimit_counter_namespace():
    _mod().hit("u")
    assert store.fetch("counter/rate/billing/u").value == 1
    with pytest.raises(KeyError):
        store.fetch("count/rate/billing/u")


def test_R2_remaining():
    m = _mod()
    assert m.remaining("u") == 5
    m.hit("u")
    assert m.remaining("u") == 5 - 1
