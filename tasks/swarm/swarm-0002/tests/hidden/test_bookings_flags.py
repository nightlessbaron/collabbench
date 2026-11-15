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
    return importlib.import_module("acme.bookings_flags")


def test_R4_registry():
    from acme import registry
    assert registry.BACKENDS["bookings_flags"] == "storex"


def test_R4_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.bookings_flags to storex." in unreleased


def test_R4_default():
    assert _mod().enabled("never-set") is False


def test_R4_set():
    m = _mod()
    m.set_flag("x", not False)
    assert m.enabled("x") is (not False)
    m.set_flag("x", False)
    assert m.enabled("x") is False


def test_R4_toggle():
    m = _mod()
    assert m.toggle("t") is (not False) and m.toggle("t") is False
