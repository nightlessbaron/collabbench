"""Helpers shared by the generators and the metrics."""

import re


def words(text: str) -> set[str]:
    """Lowercase words, with hex prefixes dropped: "Magic 0xC7 0x3A" -> {"magic", "c7", "3a"}."""
    text = re.sub(r"\b0x", "", text.lower())
    return set(re.findall(r"[a-z0-9]+", text))


def fact_disclosed(fact: dict, text: str) -> bool:
    """A fact is disclosed by `text` when every word of any one of its `match` alternatives occurs in it."""
    w = words(text)
    return any(all(k in w for k in alt) for alt in fact["match"])
