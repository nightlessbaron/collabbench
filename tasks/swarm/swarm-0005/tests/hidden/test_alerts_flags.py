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
    return importlib.import_module("acme.alerts_flags")


def test_R1_registry():
    from acme import registry
    assert registry.BACKENDS["alerts_flags"] == "storex"


def test_R1_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.alerts_flags to storex." in unreleased


def test_R1_default():
    assert _mod().enabled("never-set") is False


def test_R1_set():
    m = _mod()
    m.set_flag("x", not False)
    assert m.enabled("x") is (not False)
    m.set_flag("x", False)
    assert m.enabled("x") is False


def test_R1_toggle():
    m = _mod()
    assert m.toggle("t") is (not False) and m.toggle("t") is False
