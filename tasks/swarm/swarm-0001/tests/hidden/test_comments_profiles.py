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
    return importlib.import_module("acme.comments_profiles")


def test_R6_registry():
    from acme import registry
    assert registry.BACKENDS["comments_profiles"] == "storex"


def test_R6_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.comments_profiles to storex." in unreleased


def test_R6_defaults():
    assert _mod().get_profile("u1") == {'currency': 'on', 'plan': 'eu', 'digest': 'c'}


def test_R6_update_merges():
    m = _mod()
    m.update_profile("u1", currency="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'currency': 'on', 'plan': 'eu', 'digest': 'c'}, "currency": "changed", "extra": 1}


def test_R6_clear():
    m = _mod()
    m.update_profile("u1", currency="x")
    assert m.clear_profile("u1") is True and m.clear_profile("u1") is False
    assert m.get_profile("u1") == {'currency': 'on', 'plan': 'eu', 'digest': 'c'}


def test_F3_comments_profiles_ttl_capped():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/comments/u1") == timedelta(hours=1)
