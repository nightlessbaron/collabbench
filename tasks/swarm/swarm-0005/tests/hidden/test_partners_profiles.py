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
    return importlib.import_module("acme.partners_profiles")


def test_R18_registry():
    from acme import registry
    assert registry.BACKENDS["partners_profiles"] == "storex"


def test_R18_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.partners_profiles to storex." in unreleased


def test_R18_defaults():
    assert _mod().get_profile("u1") == {'plan': 'c', 'digest': 'c', 'timezone': 'a'}


def test_R18_update_merges():
    m = _mod()
    m.update_profile("u1", plan="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'plan': 'c', 'digest': 'c', 'timezone': 'a'}, "plan": "changed", "extra": 1}


def test_F3_partners_profiles_ttl_capped():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/partners/u1") == timedelta(hours=1)
