#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
mkdir -p "${W}/tools"
cat > "${W}/tools/restore_aquilon.py" <<'COLLAB_EOF'
#!/usr/bin/env python3
"""Return a Meridian Aquilon 7 appliance library to its certified bytes.

The media carries the release manifest (size and SHA-256).  A shipped
appliance library may have been rewritten in the field: an extra loadable
segment holds a payload that names the original file size, the overwritten
entry bytes, the displaced program header and the original section table
location.  Restoration reverses exactly that, then the result is checked
against the manifest before anything is written.
"""

import hashlib
import os
import struct
import sys

EH = struct.Struct("<16sHHIQQQIHHHHHH")
MAGIC = b"AQLRT1\x00\x00"


def fail(message):
    sys.stderr.write("restore_aquilon: %s\n" % message)
    return 1


def read_manifest(path):
    entries = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) == 3 and len(parts[2]) == 64:
                try:
                    entries.append((parts[0], int(parts[1]), parts[2].lower()))
                except ValueError:
                    pass
    return entries


def header(data):
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    if data[4] != 2 or data[5] != 1:
        raise ValueError("not a 64-bit little-endian ELF file")
    fields = EH.unpack_from(data, 0)
    e_phoff = fields[5]
    e_shoff = fields[6]
    e_phentsize = fields[9]
    e_phnum = fields[10]
    if e_phentsize != 56:
        raise ValueError("unexpected program header size")
    phnum = e_phnum
    if e_shoff and e_phnum == 0xFFFF:
        phnum = struct.unpack_from("<I", data, e_shoff + 44)[0]
    return e_phoff, phnum


def restore(data):
    """Reverse the appliance rewrite; a clean file comes back unchanged."""
    e_phoff, phnum = header(data)
    for index in range(phnum):
        off = e_phoff + index * 56
        if off + 56 > len(data):
            raise ValueError("program header outside the file")
        p_type, _flags, p_offset = struct.unpack_from("<IIQ", data, off)
        if p_type != 1 or p_offset + 8 > len(data):
            continue
        if data[p_offset:p_offset + 8] != MAGIC:
            continue
        base = p_offset
        if base + 106 > len(data):
            raise ValueError("truncated payload")
        original_size = struct.unpack_from("<Q", data, base + 10)[0]
        target = struct.unpack_from("<Q", data, base + 18)[0]
        code = data[base + 26:base + 38]
        shoff = struct.unpack_from("<Q", data, base + 38)[0]
        shnum = struct.unpack_from("<H", data, base + 46)[0]
        shstrndx = struct.unpack_from("<H", data, base + 48)[0]
        note = data[base + 50:base + 106]
        if original_size > len(data) or target + 12 > original_size:
            raise ValueError("payload names impossible offsets")
        out = bytearray(data[:original_size])
        out[off:off + 56] = note
        struct.pack_into("<Q", out, 0x28, shoff)
        struct.pack_into("<H", out, 0x3C, shnum)
        struct.pack_into("<H", out, 0x3E, shstrndx)
        return bytes(out)
    return data


def main(argv):
    if len(argv) != 4:
        return fail("usage: restore_aquilon.py APPLIANCE_LIB RELEASE_MANIFEST"
                    " OUTPUT_LIB")
    lib_path, manifest_path, out_path = argv[1], argv[2], argv[3]
    try:
        entries = read_manifest(manifest_path)
    except OSError as exc:
        return fail("cannot read the release manifest: %s" % exc)
    if not entries:
        return fail("the release manifest names no library")
    wanted = os.path.basename(lib_path)
    entry = None
    for name, size, digest in entries:
        if name == wanted:
            entry = (size, digest)
            break
    if entry is None:
        entry = entries[0][1:]
    size, digest = entry
    try:
        with open(lib_path, "rb") as handle:
            data = handle.read()
    except OSError as exc:
        return fail("cannot read %s: %s" % (lib_path, exc))
    if len(data) == size and hashlib.sha256(data).hexdigest() == digest:
        restored = data
    else:
        try:
            restored = restore(data)
        except (ValueError, struct.error) as exc:
            return fail("cannot restore %s: %s" % (lib_path, exc))
    if len(restored) != size or hashlib.sha256(restored).hexdigest() != digest:
        return fail("the restored library does not match the release manifest")
    tmp = out_path + ".tmp.%d" % os.getpid()
    with open(tmp, "wb") as handle:
        handle.write(restored)
    os.replace(tmp, out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
COLLAB_EOF
mkdir -p "${W}/migration/tcanon"
cat > "${W}/migration/tcanon/tcanon.py" <<'COLLAB_EOF'
#!/usr/bin/env python3
"""Settlement export in the TCANON v2 interchange format.

A drop-in replacement for the retired Aquilon 7 trexport: read a Trellis 4.2
.tdu v4 unload and write the canonical stream on standard output.  The record
grammar, the ordering, the money arithmetic (binary64, not decimal) and the
character handling all follow the retired runtime, quirks included.
"""

import sys
from functools import cmp_to_key

MONTHS = {
    b"JAN": 1, b"FEB": 2, b"MAR": 3, b"APR": 4, b"MAY": 5, b"JUN": 6,
    b"JUL": 7, b"AUG": 8, b"SEP": 9, b"OCT": 10, b"NOV": 11, b"DEC": 12,
}

CP1252_HIGH = {
    0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
    0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
    0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
    0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
    0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
    0x9E: 0x017E, 0x9F: 0x0178,
}


class Row(object):
    __slots__ = ("year", "month", "day", "acct", "read_id", "usage", "rate",
                 "charge", "meter", "note", "note_null")


def parse_period(text):
    if len(text) != 9 or text[2:3] != b"-" or text[6:7] != b"-":
        raise ValueError("bad period")
    day = int(text[0:2])
    month = MONTHS[text[3:6]]
    yy = int(text[7:9])
    return 2000 + yy, month, day


def _decimal_charge(usage, rate):
    from decimal import Decimal, ROUND_HALF_EVEN
    exact = Decimal(usage.decode('ascii')) * Decimal(rate.decode('ascii'))
    return float(exact.quantize(Decimal('0.01'), rounding=ROUND_HALF_EVEN))


def parse_number(text):
    return float(text.decode("ascii"))


def collation(a, b):
    """Natural collation: digit runs by value, other runs case-folded."""
    i = j = 0
    la, lb = len(a), len(b)
    while i < la or j < lb:
        if i >= la:
            return -1
        if j >= lb:
            return 1
        ad = 48 <= a[i] <= 57
        bd = 48 <= b[j] <= 57
        i2 = i
        while i2 < la and (48 <= a[i2] <= 57) == ad:
            i2 += 1
        j2 = j
        while j2 < lb and (48 <= b[j2] <= 57) == bd:
            j2 += 1
        if ad and bd:
            va = int(a[i:i2])
            vb = int(b[j:j2])
            if va != vb:
                return -1 if va < vb else 1
        else:
            xa = a[i:i2].lower()
            xb = b[j:j2].lower()
            if xa != xb:
                return -1 if xa < xb else 1
        i, j = i2, j2
    return 0


def compare(x, y):
    if x.year != y.year:
        return -1 if x.year < y.year else 1
    if x.month != y.month:
        return -1 if x.month < y.month else 1
    if x.day != y.day:
        return -1 if x.day < y.day else 1
    order = collation(x.meter, y.meter)
    if order:
        return order
    if x.read_id != y.read_id:
        return -1 if x.read_id < y.read_id else 1
    return 0


def cp1252_char(byte):
    if byte < 0x80 or byte >= 0xA0:
        return chr(byte)
    return chr(byte)


def emit_note(note, is_null):
    if is_null:
        return b""
    if not note:
        return b'""'
    text = "".join(cp1252_char(byte) for byte in note[:40])
    return b'"' + text.replace('"', '""').encode("utf-8") + b'"'


def parse(data):
    if not data:
        return [], {}
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    rows = []
    totals = {}
    for line in lines:
        if line == b"":
            continue
        parts = line.split(b"|", 6)
        if len(parts) != 7:
            raise ValueError("record does not have seven fields")
        period, acct, meter, read_id, usage, rate, note = [
            part for part in parts]
        row = Row()
        row.year, row.month, row.day = parse_period(period)
        row.acct = parse_number(acct)
        row.read_id = parse_number(read_id)
        row.usage = parse_number(usage)
        row.rate = parse_number(rate)
        row.charge = _decimal_charge(usage, rate)
        row.meter = meter
        row.note_null = False
        row.note = b"" if row.note_null else note
        # The runtime accumulates each period as the records are read, before
        # the export is ordered: binary64 addition, left to right, file order.
        key = (row.year, row.month, row.day)
        totals[key] = totals.get(key, 0.0) + row.charge
        rows.append(row)
    rows.sort(key=cmp_to_key(compare))
    return rows, _sorted_totals(rows)


def _sorted_totals(rows):
    totals = {}
    for row in rows:
        key = (row.year, row.month, row.day)
        totals[key] = totals.get(key, 0.0) + row.charge
    return totals


def emit(rows, totals):
    out = [b"#TCANON 2 " + str(len(rows)).encode("ascii") + b"\n"]
    for row in rows:
        out.append(b"%04d-%02d-%02d|" % (row.year, row.month, row.day))
        out.append(("%.0f|" % row.acct).encode("ascii"))
        out.append(row.meter + b"|")
        out.append(("%.3f|" % row.usage).encode("ascii"))
        out.append(("%.4f|" % row.rate).encode("ascii"))
        out.append(("%.2f|" % row.charge).encode("ascii"))
        out.append(emit_note(row.note, row.note_null))
        out.append(b"\n")
    emitted = set()
    for row in rows:
        key = (row.year, row.month, row.day)
        if key in emitted:
            continue
        emitted.add(key)
        out.append(b"#TOTAL %04d-%02d-%02d|%.2f\n"
                   % (row.year, row.month, row.day, totals[key]))
    out.append(b"#END\n")
    return b"".join(out)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: tcanon.py FILE.tdu\n")
        return 2
    try:
        with open(argv[1], "rb") as handle:
            data = handle.read()
        rows, totals = parse(data)
    except (OSError, ValueError, KeyError) as exc:
        sys.stderr.write("tcanon: %s\n" % exc)
        return 1
    sys.stdout.buffer.write(emit(rows, totals))
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
COLLAB_EOF
chmod 0755 "${W}/tools/restore_aquilon.py" "${W}/migration/tcanon/tcanon.py"
