#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}/codec"
cat > "${WORKSPACE:-/workspace}/codec/encoder.py" <<'PYEOF'
"""Lanner wire protocol: frame encoder (reference)."""

import struct

MAGIC = bytes(b'\xaa\xcd')
VERSION = 0x57
TYPE_CODES = {'quote': 40, 'ping': 94, 'order': 39}
FIELDS = {'quote': [('price', 'u16'), ('batch', 'u32'), ('offset', 'i32'), ('label', 'str')], 'ping': [('lot', 'u32'), ('venue', 'u8'), ('desk', 'str')], 'order': [('route', 'u32'), ('priority', 'i32')]}
ENDIAN = '>'
LENGTH_MODE = 'unescaped'
STRINGS = 'prefix'
FLAG, ESC, MASK = 0x26, 0x25, 0x20
CRC_POLY, CRC_INIT = 0x39, 0xa5
_FMT = {"u8": "B", "u16": "H", "u32": "I", "i32": "i"}


def _crc8(data: bytes) -> int:
    crc = CRC_INIT
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ CRC_POLY) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def _field(kind, value):
    if kind == "str":
        raw = value.encode("utf-8")
        return bytes([len(raw)]) + raw if STRINGS == "prefix" else raw + b"\x00"
    return struct.pack(ENDIAN + _FMT[kind], value)


def _escape(payload: bytes) -> bytes:
    out = bytearray()
    for b in payload:
        out += bytes([ESC, b ^ MASK]) if b in (FLAG, ESC) else bytes([b])
    return bytes(out)


def encode(message: dict) -> bytes:
    kind = message["type"]
    payload = b"".join(_field(t, message[name]) for name, t in FIELDS[kind])
    body = _escape(payload)
    length = len(payload) if LENGTH_MODE == "unescaped" else len(body)
    header = bytes([VERSION, TYPE_CODES[kind]]) + struct.pack(ENDIAN + "H", length)
    return MAGIC + header + body + bytes([_crc8(header + payload), FLAG])
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/codec"
cat > "${WORKSPACE:-/workspace}/codec/decoder.py" <<'PYEOF'
"""Lanner wire protocol: frame decoder (reference)."""

from codec.errors import ChecksumError, FrameError

import struct

MAGIC = bytes(b'\xaa\xcd')
VERSION = 0x57
TYPE_CODES = {'quote': 40, 'ping': 94, 'order': 39}
FIELDS = {'quote': [('price', 'u16'), ('batch', 'u32'), ('offset', 'i32'), ('label', 'str')], 'ping': [('lot', 'u32'), ('venue', 'u8'), ('desk', 'str')], 'order': [('route', 'u32'), ('priority', 'i32')]}
ENDIAN = '>'
LENGTH_MODE = 'unescaped'
STRINGS = 'prefix'
FLAG, ESC, MASK = 0x26, 0x25, 0x20
CRC_POLY, CRC_INIT = 0x39, 0xa5
_FMT = {"u8": "B", "u16": "H", "u32": "I", "i32": "i"}


def _crc8(data: bytes) -> int:
    crc = CRC_INIT
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ CRC_POLY) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def decode(frame: bytes) -> dict:
    try:
        return _decode(bytes(frame))
    except (IndexError, struct.error, UnicodeDecodeError, ValueError) as e:
        if isinstance(e, (FrameError, ChecksumError)):
            raise
        raise FrameError(f"malformed frame: {e}") from e


def _decode(frame: bytes) -> dict:
    if frame[:2] != MAGIC:
        raise FrameError("bad magic")
    if frame[2] != VERSION:
        raise FrameError("bad version")
    names = {code: name for name, code in TYPE_CODES.items()}
    if frame[3] not in names:
        raise FrameError("unknown message type")
    kind = names[frame[3]]
    (length,) = struct.unpack(ENDIAN + "H", frame[4:6])
    payload, i = bytearray(), 6
    if LENGTH_MODE == "unescaped":
        while len(payload) < length:
            b = frame[i]
            i += 1
            if b == ESC:
                b, i = frame[i] ^ MASK, i + 1
            payload.append(b)
    else:
        raw, i = frame[6:6 + length], 6 + length
        j = 0
        while j < len(raw):
            if raw[j] == ESC:
                payload.append(raw[j + 1] ^ MASK)
                j += 2
            else:
                payload.append(raw[j])
                j += 1
    crc = frame[i]
    if i + 2 != len(frame) or frame[i + 1] != FLAG:
        raise FrameError("bad terminator")
    if _crc8(frame[2:6] + bytes(payload)) != crc:
        raise ChecksumError("checksum mismatch")
    out, p = {"type": kind}, 0
    for name, t in FIELDS[kind]:
        if t == "str":
            if STRINGS == "prefix":
                n = payload[p]
                out[name], p = bytes(payload[p + 1:p + 1 + n]).decode("utf-8"), p + 1 + n
            else:
                end = payload.index(0, p)
                out[name], p = bytes(payload[p:end]).decode("utf-8"), end + 1
        else:
            (out[name],) = struct.unpack_from(ENDIAN + _FMT[t], payload, p)
            p += struct.calcsize(_FMT[t])
    return out
PYEOF
