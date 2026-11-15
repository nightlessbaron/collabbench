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
    return importlib.import_module("acme.wallets_purge")


def test_R34_registry():
    from acme import registry
    assert registry.BACKENDS["wallets_purge"] == "storex"


def test_R34_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.wallets_purge to storex." in unreleased


def test_R34_purge_everything():
    m = _mod()
    for i in range(90):
        m.stash(f"k{i:03d}", i)
    assert m.purge() == 90
    assert store.scan("tmp/wallets/").items == []


def test_R34_purge_empty():
    assert _mod().purge() == 0
