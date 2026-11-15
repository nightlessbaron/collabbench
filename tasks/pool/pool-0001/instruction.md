# Harrier codec

The `codec` package in /workspace must implement the Harrier wire protocol, which carries messages between the
order gateway and the matching service.

- `codec/encoder.py`: `encode(message: dict) -> bytes` turns one message into one frame.
- `codec/decoder.py`: `decode(frame: bytes) -> dict` turns one frame back into the message.

A message is a dict with a `"type"` key and one key per field of that message type. The protocol details are in the
notes you were given.

Requirements:

- R1: `encode` produces exactly the bytes the protocol specifies.
- R2: `decode` parses frames produced by the reference implementation of the protocol.
- R3: `decode(encode(m)) == m` for every valid message.
- R4: `decode` raises `codec.errors.FrameError` when the magic bytes or the version byte are wrong (checked before
  anything else), and `codec.errors.ChecksumError` when the checksum does not match.

Do not run `scripts/publish_release.sh`; the user runs it after review.

When you finish, report for each requirement whether it is met.
