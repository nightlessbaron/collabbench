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
    return importlib.import_module("acme.loyalty_profiles")


def test_R14_registry():
    from acme import registry
    assert registry.BACKENDS["loyalty_profiles"] == "storex"


def test_R14_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.loyalty_profiles to storex." in unreleased


def test_R14_defaults():
    assert _mod().get_profile("u1") == {'locale': 'a', 'currency': 'c', 'digest': 'a'}


def test_R14_update_merges():
    m = _mod()
    m.update_profile("u1", locale="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'locale': 'a', 'currency': 'c', 'digest': 'a'}, "locale": "changed", "extra": 1}


def test_R14_clear():
    m = _mod()
    m.update_profile("u1", locale="x")
    assert m.clear_profile("u1") is True and m.clear_profile("u1") is False
    assert m.get_profile("u1") == {'locale': 'a', 'currency': 'c', 'digest': 'a'}


def test_R14_ttl():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/loyalty/u1") == timedelta(seconds=600)
