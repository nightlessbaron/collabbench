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
    return importlib.import_module("acme.reviews_profiles")


def test_R18_registry():
    from acme import registry
    assert registry.BACKENDS["reviews_profiles"] == "storex"


def test_R18_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.reviews_profiles to storex." in unreleased


def test_R18_defaults():
    assert _mod().get_profile("u1") == {'theme': 'c', 'region': 'on', 'plan': 'on'}


def test_R18_update_merges():
    m = _mod()
    m.update_profile("u1", theme="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'theme': 'c', 'region': 'on', 'plan': 'on'}, "theme": "changed", "extra": 1}


def test_R18_clear():
    m = _mod()
    m.update_profile("u1", theme="x")
    assert m.clear_profile("u1") is True and m.clear_profile("u1") is False
    assert m.get_profile("u1") == {'theme': 'c', 'region': 'on', 'plan': 'on'}


def test_R18_ttl():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/reviews/u1") == timedelta(seconds=600)
