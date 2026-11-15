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
    return importlib.import_module("acme.rooms_stock")


def test_R27_registry():
    from acme import registry
    assert registry.BACKENDS["rooms_stock"] == "storex"


def test_R27_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.rooms_stock to storex." in unreleased


def test_R27_restock_from_zero():
    m = _mod()
    m.restock("a", 3)
    m.restock("a", 4)
    assert m.total() == 7 and m.items() == ["a"]


def test_R27_total_across_pages():
    m = _mod()
    for i in range(130):
        m.restock(f"item{i:03d}", i)
    assert m.total() == sum(range(130)) and len(m.items()) == 130 and m.items() == sorted(m.items())
