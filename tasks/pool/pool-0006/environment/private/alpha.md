# Peregrine protocol notes: the frame envelope

You maintain codec/encoder.py.

- Every frame starts with the two magic bytes 0xE7 0x81.
- The next byte is the protocol version, 0x51. A frame with any other version must be rejected.
- The byte after the version is the message type code:
  - fill: 0x59
  - status: 0x32
  - cancel: 0x46
- Checksum: one byte, CRC-8 with polynomial 0x1D and initial value 0xFF (MSB first, no
  reflection, no final XOR). It is computed over every byte from the version byte through the last payload byte, taken
  before escaping, and it is written right after the payload.
- Peregrine brokers listen on TCP port 7845.
- The protocol was designed by the Virtanen group, who still own the broker configuration.
