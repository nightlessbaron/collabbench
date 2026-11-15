# Lanner protocol notes: the frame envelope

You maintain codec/encoder.py.

- Every frame starts with the two magic bytes 0xAA 0xCD.
- The next byte is the protocol version, 0x57. A frame with any other version must be rejected.
- The byte after the version is the message type code:
  - quote: 0x28
  - ping: 0x5E
  - order: 0x27
- Checksum: one byte, CRC-8 with polynomial 0x39 and initial value 0xA5 (MSB first, no
  reflection, no final XOR). It is computed over every byte from the version byte through the last payload byte, taken
  before escaping, and it is written right after the payload.
- Lanner brokers listen on TCP port 7243.
- The protocol was designed by the Virtanen group, who still own the broker configuration.
