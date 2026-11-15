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
    return importlib.import_module("acme.catalog_audit")


def test_R3_registry():
    from acme import registry
    assert registry.BACKENDS["catalog_audit"] == "storex"


def test_R3_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.catalog_audit to storex." in unreleased


def test_R3_history_in_order():
    m = _mod()
    m.record("e2", {"n": 2})
    m.record("e1", {"n": 1})
    assert m.history() == [{"n": 1}, {"n": 2}]


def test_R3_history_across_pages():
    m = _mod()
    for i in range(75):
        m.record(f"e{i:03d}", i)
    assert m.history() == list(range(75))


def test_F1_catalog_audit_never_expires():
    _mod().record("e1", "x")
    assert store.ttl_of("audit/catalog/e1") is None


def test_R3_count():
    m = _mod()
    for i in range(55):
        m.record(f"e{i:03d}", i)
    assert m.count() == 55
