# Lanner protocol notes: the frame envelope

You maintain codec/encoder.py.

- Every frame starts with the two magic bytes 0xEA 0xE4.
- The next byte is the protocol version, 0x5C. A frame with any other version must be rejected.
- The byte after the version is the message type code:
  - status: 0x57
  - ping: 0x1C
  - quote: 0x2E
- Checksum: one byte, CRC-8 with polynomial 0xD5 and initial value 0xFF (MSB first, no
  reflection, no final XOR). It is computed over every byte from the version byte through the last payload byte, taken
  before escaping, and it is written right after the payload.
- Lanner brokers listen on TCP port 7515.
- The protocol was designed by the Virtanen group, who still own the broker configuration.
