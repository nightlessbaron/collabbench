"""Harrier wire protocol: frame decoder."""

from codec.errors import ChecksumError, FrameError  # noqa: F401


def decode(frame: bytes) -> dict:
    """Decode one frame into the message dict."""
    raise NotImplementedError
