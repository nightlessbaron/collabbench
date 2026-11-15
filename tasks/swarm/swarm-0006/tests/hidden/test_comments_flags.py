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
    return importlib.import_module("acme.comments_flags")


def test_R4_registry():
    from acme import registry
    assert registry.BACKENDS["comments_flags"] == "storex"


def test_R4_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\n## ", 1)[0]
    assert "- Migrated acme.comments_flags to storex." in unreleased


def test_R4_default():
    assert _mod().enabled("never-set") is True


def test_R4_set():
    m = _mod()
    m.set_flag("x", not True)
    assert m.enabled("x") is (not True)
    m.set_flag("x", True)
    assert m.enabled("x") is True
