# Hobby protocol notes: the frame envelope

You maintain codec/encoder.py.

- Every frame starts with the two magic bytes 0x83 0xE6.
- The next byte is the protocol version, 0x45. A frame with any other version must be rejected.
- The byte after the version is the message type code:
  - order: 0x3D
  - fill: 0x56
  - status: 0x58
- Checksum: one byte, CRC-8 with polynomial 0x1D and initial value 0xA5 (MSB first, no
  reflection, no final XOR). It is computed over every byte from the version byte through the last payload byte, taken
  before escaping, and it is written right after the payload.
- Hobby brokers listen on TCP port 7692.
- The protocol was designed by the Lindqvist group, who still own the broker configuration.
