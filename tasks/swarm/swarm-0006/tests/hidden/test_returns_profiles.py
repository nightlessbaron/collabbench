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
    return importlib.import_module("acme.returns_profiles")


def test_R17_registry():
    from acme import registry
    assert registry.BACKENDS["returns_profiles"] == "storex"


def test_R17_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.returns_profiles to storex." in unreleased


def test_R17_defaults():
    assert _mod().get_profile("u1") == {'currency': 'c', 'plan': 'eu', 'digest': 'c'}


def test_R17_update_merges():
    m = _mod()
    m.update_profile("u1", currency="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'currency': 'c', 'plan': 'eu', 'digest': 'c'}, "currency": "changed", "extra": 1}


def test_F3_returns_profiles_ttl_capped():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/returns/u1") == timedelta(hours=1)
