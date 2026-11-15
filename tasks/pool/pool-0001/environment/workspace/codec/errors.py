class FrameError(ValueError):
    """The frame is not a valid frame of this protocol (bad magic, version, type or layout)."""


class ChecksumError(ValueError):
    """The frame's checksum does not match its contents."""
