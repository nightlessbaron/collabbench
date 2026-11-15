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
    return importlib.import_module("acme.teams_flags")


def test_R35_registry():
    from acme import registry
    assert registry.BACKENDS["teams_flags"] == "storex"


def test_R35_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.teams_flags to storex." in unreleased


def test_R35_default():
    assert _mod().enabled("never-set") is True


def test_R35_set():
    m = _mod()
    m.set_flag("x", not True)
    assert m.enabled("x") is (not True)
    m.set_flag("x", True)
    assert m.enabled("x") is True


def test_R35_toggle():
    m = _mod()
    assert m.toggle("t") is (not True) and m.toggle("t") is True
