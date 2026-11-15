# Harrier protocol notes: the frame envelope

You maintain codec/encoder.py.

- Every frame starts with the two magic bytes 0xF5 0xBD.
- The next byte is the protocol version, 0x46. A frame with any other version must be rejected.
- The byte after the version is the message type code:
  - status: 0x26
  - fill: 0x35
  - ping: 0x4A
- Checksum: one byte, CRC-8 with polynomial 0x07 and initial value 0x5A (MSB first, no
  reflection, no final XOR). It is computed over every byte from the version byte through the last payload byte, taken
  before escaping, and it is written right after the payload.
- Harrier brokers listen on TCP port 7031.
- The protocol was designed by the Okonkwo group, who still own the broker configuration.
