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
    return importlib.import_module("acme.reviews_sessions")


def test_R27_registry():
    from acme import registry
    assert registry.BACKENDS["reviews_sessions"] == "storex"


def test_R27_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.reviews_sessions to storex." in unreleased


def test_R27_load_missing_is_none():
    assert _mod().load("nope") is None


def test_R27_save_then_load():
    m = _mod()
    m.save("s1", {"user": 7})
    assert m.load("s1") == {"user": 7}


def test_R27_drop():
    m = _mod()
    m.save("s1", 1)
    assert m.drop("s1") is True and m.drop("s1") is False and m.load("s1") is None


def test_R27_ttl():
    m = _mod()
    m.save("s1", 1)
    assert store.ttl_of("session/reviews/s1") == timedelta(seconds=900)
