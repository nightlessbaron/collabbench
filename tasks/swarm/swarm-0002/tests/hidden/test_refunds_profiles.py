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
    return importlib.import_module("acme.refunds_profiles")


def test_R24_registry():
    from acme import registry
    assert registry.BACKENDS["refunds_profiles"] == "storex"


def test_R24_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.refunds_profiles to storex." in unreleased


def test_R24_defaults():
    assert _mod().get_profile("u1") == {'theme': 'off', 'region': 'b', 'locale': 'c'}


def test_R24_update_merges():
    m = _mod()
    m.update_profile("u1", theme="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'theme': 'off', 'region': 'b', 'locale': 'c'}, "theme": "changed", "extra": 1}


def test_R24_clear():
    m = _mod()
    m.update_profile("u1", theme="x")
    assert m.clear_profile("u1") is True and m.clear_profile("u1") is False
    assert m.get_profile("u1") == {'theme': 'off', 'region': 'b', 'locale': 'c'}


def test_F3_refunds_profiles_ttl_capped():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/refunds/u1") == timedelta(hours=1)
