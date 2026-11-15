"""Public title normalisation helpers shipped to partners."""


def normalise_title(title):
    """Lower-case, punctuation to spaces, collapse whitespace."""
    text = "".join(ch.lower() if ch.isalnum() else " " for ch in str(title))
    return " ".join(text.split())


def block_key(title):
    """The first four characters of the space-free normalised title."""
    return normalise_title(title).replace(" ", "")[:4]