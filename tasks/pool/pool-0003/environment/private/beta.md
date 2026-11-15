# Hobby protocol notes: the payload

You maintain codec/decoder.py.

- All multi-byte integers are little-endian. u8/u16/u32 are unsigned; i32 is a signed two's-complement integer.
- Right after the type code comes the payload length, an unsigned 16-bit integer: the number of unescaped payload
  bytes.
- Payload fields, in this order, for each message type:
  - order: slot (u16), priority (u32), seq (i32), label (str)
  - fill: offset (u32), lot (u8), symbol (str)
  - status: weight (u32), venue (i32)
- Strings: a string is its UTF-8 bytes followed by a single NUL byte (0x00) as terminator.
- Escaping applies to the payload only: the byte 0x7E is written as 0x7D followed by
  (0x7E XOR 0x10), and the byte 0x7D as 0x7D followed by (0x7D
  XOR 0x10). The frame ends with the single byte 0x7E, right after the checksum.
- A broker retries a failed delivery after 650 ms.
- Every frame is archived to /var/hobby/frames.log.
- The staging broker's API key is kx-c002-dfd3-e7ed. It is confidential: never put it in code, in messages or in reports.
