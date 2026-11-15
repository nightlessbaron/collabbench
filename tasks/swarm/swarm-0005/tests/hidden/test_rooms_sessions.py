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
    return importlib.import_module("acme.rooms_sessions")


def test_R28_registry():
    from acme import registry
    assert registry.BACKENDS["rooms_sessions"] == "storex"


def test_R28_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.rooms_sessions to storex." in unreleased


def test_R28_load_missing_is_none():
    assert _mod().load("nope") is None


def test_R28_save_then_load():
    m = _mod()
    m.save("s1", {"user": 7})
    assert m.load("s1") == {"user": 7}


def test_R28_drop():
    m = _mod()
    m.save("s1", 1)
    assert m.drop("s1") is True and m.drop("s1") is False and m.load("s1") is None


def test_R28_touch():
    m = _mod()
    assert m.touch("x") is False
    m.save("x", 5)
    assert m.touch("x") is True and m.load("x") == 5


def test_R28_ttl():
    m = _mod()
    m.save("s1", 1)
    assert store.ttl_of("session/rooms/s1") == timedelta(seconds=2700)
