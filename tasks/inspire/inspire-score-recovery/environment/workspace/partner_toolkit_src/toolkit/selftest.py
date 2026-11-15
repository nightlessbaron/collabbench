"""Smoke test for the shipped toolkit.  Prints SELFTEST OK on success."""

from .titles import block_key, normalise_title


def main():
    assert normalise_title("  Aurora   Suite! ") == "aurora suite"
    assert block_key("Aurora Suite!") == "auro"
    assert normalise_title("Bellwether-March") == "bellwether march"
    assert block_key("Bellwether-March") == "bell"
    print("SELFTEST OK")


if __name__ == "__main__":
    main()