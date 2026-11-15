# Peregrine protocol notes: the frame envelope

You maintain codec/encoder.py.

- Every frame starts with the two magic bytes 0xEE 0xB7.
- The next byte is the protocol version, 0x59. A frame with any other version must be rejected.
- The byte after the version is the message type code:
  - status: 0x68
  - reject: 0x5A
  - order: 0x46
- Checksum: one byte, CRC-8 with polynomial 0x9B and initial value 0xA5 (MSB first, no
  reflection, no final XOR). It is computed over every byte from the version byte through the last payload byte, taken
  before escaping, and it is written right after the payload.
- Peregrine brokers listen on TCP port 7314.
- The protocol was designed by the Lindqvist group, who still own the broker configuration.
