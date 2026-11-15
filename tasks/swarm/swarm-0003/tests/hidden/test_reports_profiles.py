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
    return importlib.import_module("acme.reports_profiles")


def test_R24_registry():
    from acme import registry
    assert registry.BACKENDS["reports_profiles"] == "storex"


def test_R24_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.reports_profiles to storex." in unreleased


def test_R24_defaults():
    assert _mod().get_profile("u1") == {'timezone': 'eu', 'digest': 'b', 'currency': 'b'}


def test_R24_update_merges():
    m = _mod()
    m.update_profile("u1", timezone="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**{'timezone': 'eu', 'digest': 'b', 'currency': 'b'}, "timezone": "changed", "extra": 1}


def test_R24_ttl():
    m = _mod()
    m.update_profile("u1", a=1)
    assert store.ttl_of("profile/reports/u1") == timedelta(seconds=900)
