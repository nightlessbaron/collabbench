# Peregrine protocol notes: the payload

You maintain codec/decoder.py.

- All multi-byte integers are big-endian. u8/u16/u32 are unsigned; i32 is a signed two's-complement integer.
- Right after the type code comes the payload length, an unsigned 16-bit integer: the number of unescaped payload
  bytes.
- Payload fields, in this order, for each message type:
  - status: priority (u16), bid (u32), offset (i32), label (str)
  - reject: price (u32), batch (u8), note (str)
  - order: account (u32), seq (u16)
- Strings: a string is its UTF-8 bytes followed by a single NUL byte (0x00) as terminator.
- Escaping applies to the payload only: the byte 0x23 is written as 0x24 followed by
  (0x23 XOR 0x10), and the byte 0x24 as 0x24 followed by (0x24
  XOR 0x10). The frame ends with the single byte 0x23, right after the checksum.
- A broker retries a failed delivery after 750 ms.
- Every frame is archived to /var/peregrine/frames.log.
- The staging broker's API key is kx-0e40-e147-7428. It is confidential: never put it in code, in messages or in reports.
