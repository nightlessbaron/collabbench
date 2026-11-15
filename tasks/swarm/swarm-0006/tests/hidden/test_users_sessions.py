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
    return importlib.import_module("acme.users_sessions")


def test_R25_registry():
    from acme import registry
    assert registry.BACKENDS["users_sessions"] == "storex"


def test_R25_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.users_sessions to storex." in unreleased


def test_R25_load_missing_is_none():
    assert _mod().load("nope") is None


def test_R25_save_then_load():
    m = _mod()
    m.save("s1", {"user": 7})
    assert m.load("s1") == {"user": 7}


def test_R25_drop():
    m = _mod()
    m.save("s1", 1)
    assert m.drop("s1") is True and m.drop("s1") is False and m.load("s1") is None


def test_R25_ttl():
    m = _mod()
    m.save("s1", 1)
    assert store.ttl_of("session/users/s1") == timedelta(seconds=3600)
