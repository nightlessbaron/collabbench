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
    return importlib.import_module("acme.reviews_metrics")


def test_R27_registry():
    from acme import registry
    assert registry.BACKENDS["reviews_metrics"] == "storex"


def test_R27_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.reviews_metrics to storex." in unreleased


def test_R27_bump_and_read():
    m = _mod()
    assert m.read("hits") == 0
    assert [m.bump("hits"), m.bump("hits", 5)] == [1, 6]
    assert m.read("hits") == 6


def test_F2_reviews_metrics_counter_namespace():
    _mod().bump("hits", 2)
    assert store.fetch("counter/reviews/hits").value == 2
    with pytest.raises(KeyError):
        store.fetch("count/reviews/hits")


def test_R27_reset():
    m = _mod()
    m.reset("never")
    m.bump("hits")
    m.reset("hits")
    assert m.read("hits") == 0
