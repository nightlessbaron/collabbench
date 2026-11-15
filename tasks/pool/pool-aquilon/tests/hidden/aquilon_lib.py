"""Verifier-side reference implementation for the HVWA Aquilon settlement task.

This module is never visible to the agent.  It contains

  * the reference implementation of the hidden Trellis/trexport behaviour
    (``tcanon_reference``),
  * a seeded instance generator with two profiles, ``visible`` (the single
    instance shipped in the agent's image) and ``hidden`` (the unseen corpus),
  * an ELF64 builder / infector / restorer for the appliance library,
  * ``validate_instance``, written from the .tdu v4 grammar and the ELF
    System V gABI rather than from the generator.

Hidden-rule probes (one per quirk; each is a valid .tdu v4 unload that the
reference comments name, and each is used by identifiability.py):

  binary64 money   USAGE_KWH 0.100 with RATE 0.0500 -> CHARGE 0.01
                   USAGE_KWH 0.100 with RATE 0.3500 -> CHARGE 0.03
                   USAGE_KWH -0.001 with RATE 0.1000 -> CHARGE -0.00
                   USAGE_KWH -0.000 -> "-0.000", CHARGE "-0.00"
  date pivot       31-DEC-49 -> 2049-12-31, 01-JAN-50 -> 1950-01-01
  collation        M-9 before M-10; m-010 ties M-10, READ_ID decides
  CHAR semantics   NULL NOTE (empty field), empty NOTE (""),
                   all-space NOTE, trailing spaces, 41st code point lost
  encoding         CP1252 NOTE bytes become UTF-8
  framing          a zero-row unload is "#TCANON 2 0\\n#END\\n"
  suppression      ACCT 8800000001, USAGE_KWH 100.000, RATE 6.0000 -> 600.00
  accumulation     one period holding 2^53, 1, 1 in record order totals
                   9007199254740992.00; the same rows in canonical order total
                   9007199254740994.00, and two half-cent charges in one period
                   total 0.01 where their displayed cents total 0.02
"""

from __future__ import annotations

import hashlib
import io
import random
import re
import struct
from functools import cmp_to_key

VISIBLE_SEED = 1
CORPUS_SEEDS = tuple(range(9001, 9021))
ZERO_ROW_SEEDS = frozenset({9020})
PROBE_SEEDS = {
    "number_half_cent": 9101,
    "number_negative_zero": 9102,
    "period_pivot": 9103,
    "order_collation": 9104,
    "char_notes": 9105,
    "zero_rows": 9106,
    "suppression": 9107,
    "period_totals": 9108,
}
ELF_SEEDS = tuple(range(7001, 7009))

MONTH_NAMES = [b"JAN", b"FEB", b"MAR", b"APR", b"MAY", b"JUN",
               b"JUL", b"AUG", b"SEP", b"OCT", b"NOV", b"DEC"]
_MONTH_NUMBER = {name: i + 1 for i, name in enumerate(MONTH_NAMES)}


# ---------------------------------------------------------------------------
# The shipped visible instance (seed 1, visible profile)
# ---------------------------------------------------------------------------

VISIBLE_TDU = (
    b"15-JAN-23|1000000001|0000001001|7101|250.000|0.1200|Quarter opening read\n"
    b"15-JAN-23|1000000002|0000001002|7102|180.500|0.1200|Quarter opening read\n"
    b"15-JAN-23|1000000003|0000001003|7103|96.250|0.1200|Meter card swapped\n"
    b"01-FEB-23|1000000004|0000001004|7204|310.000|0.1350|New service\n"
    b"01-FEB-23|1000000005|0000001005|7205|45.750|0.1350|Vacant unit\n"
    b"01-MAR-23|1000000001|0000001001|7301|262.750|0.1200|February cycle\n"
    b"01-MAR-23|1000000002|0000001002|7302|171.000|0.1200|February cycle\n"
    b"01-APR-23|1000000006|0000001006|7406|520.250|0.1350|Summer rate begins\n"
    b"01-MAY-23|1000000007|0000001007|7507|610.000|0.1350|Cooling load\n"
    b"01-JUN-23|1000000008|0000001008|7608|575.500|0.1350|Cooling load\n"
    b"01-JUL-23|1000000009|0000001009|7709|430.750|0.1350|July cycle\n"
    b"01-AUG-23|1000000010|0000001010|7810|120.000|0.1350|August cycle\n"
    b"01-SEP-23|1000000011|0000001011|7911|95.500|0.1350|September cycle\n"
    b"01-OCT-23|1000000012|0000001012|8012|205.250|0.1350|October cycle\n"
    b"01-NOV-24|1000000013|0000001013|8113|300.000|0.1425|Rates adjusted\n"
    b"01-DEC-24|1000000014|0000001014|8214|88.750|0.1425|Year end read\n"
)

# Hand-checked against trexport's visible export.  Every product above is far
# from a cent midpoint, so no rounding convention can change these lines.
VISIBLE_EXPECTED = (
    b"#TCANON 2 16\n"
    b"2023-01-15|1000000001|0000001001|250.000|0.1200|30.00|\"Quarter opening read\"\n"
    b"2023-01-15|1000000002|0000001002|180.500|0.1200|21.66|\"Quarter opening read\"\n"
    b"2023-01-15|1000000003|0000001003|96.250|0.1200|11.55|\"Meter card swapped\"\n"
    b"2023-02-01|1000000004|0000001004|310.000|0.1350|41.85|\"New service\"\n"
    b"2023-02-01|1000000005|0000001005|45.750|0.1350|6.18|\"Vacant unit\"\n"
    b"2023-03-01|1000000001|0000001001|262.750|0.1200|31.53|\"February cycle\"\n"
    b"2023-03-01|1000000002|0000001002|171.000|0.1200|20.52|\"February cycle\"\n"
    b"2023-04-01|1000000006|0000001006|520.250|0.1350|70.23|\"Summer rate begins\"\n"
    b"2023-05-01|1000000007|0000001007|610.000|0.1350|82.35|\"Cooling load\"\n"
    b"2023-06-01|1000000008|0000001008|575.500|0.1350|77.69|\"Cooling load\"\n"
    b"2023-07-01|1000000009|0000001009|430.750|0.1350|58.15|\"July cycle\"\n"
    b"2023-08-01|1000000010|0000001010|120.000|0.1350|16.20|\"August cycle\"\n"
    b"2023-09-01|1000000011|0000001011|95.500|0.1350|12.89|\"September cycle\"\n"
    b"2023-10-01|1000000012|0000001012|205.250|0.1350|27.71|\"October cycle\"\n"
    b"2024-11-01|1000000013|0000001013|300.000|0.1425|42.75|\"Rates adjusted\"\n"
    b"2024-12-01|1000000014|0000001014|88.750|0.1425|12.65|\"Year end read\"\n"
    b"#TOTAL 2023-01-15|63.21\n"
    b"#TOTAL 2023-02-01|48.03\n"
    b"#TOTAL 2023-03-01|52.05\n"
    b"#TOTAL 2023-04-01|70.23\n"
    b"#TOTAL 2023-05-01|82.35\n"
    b"#TOTAL 2023-06-01|77.69\n"
    b"#TOTAL 2023-07-01|58.15\n"
    b"#TOTAL 2023-08-01|16.20\n"
    b"#TOTAL 2023-09-01|12.89\n"
    b"#TOTAL 2023-10-01|27.71\n"
    b"#TOTAL 2024-11-01|42.75\n"
    b"#TOTAL 2024-12-01|12.65\n"
    b"#END\n"
)


# ---------------------------------------------------------------------------
# Reference implementation of the hidden trexport rule
# ---------------------------------------------------------------------------

class _Row:
    __slots__ = ("year", "month", "day", "acct", "read_id", "usage", "rate",
                 "charge", "meter", "note", "note_null", "seq")


def _parse_period(value):
    """DD-MON-YY with the 50 pivot (00..49 -> 2000s, 50..99 -> 1900s)."""
    if len(value) != 9 or value[2:3] != b"-" or value[6:7] != b"-":
        raise ValueError("bad period")
    day = int(value[0:2])
    month = _MONTH_NUMBER[value[3:6]]
    yy = int(value[7:9])
    year = 2000 + yy if yy <= 49 else 1900 + yy
    return year, month, day


def _decode_number(value):
    return float(value.decode("ascii"))


def _coll_cmp(a, b):
    """Trellis natural collation over byte strings (ASCII lowercase)."""
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
        ta, tb = a[i:i2], b[j:j2]
        if ad and bd:
            va = int(ta)
            vb = int(tb)
            if va != vb:
                return -1 if va < vb else 1
        else:
            if ta.lower() != tb.lower():
                return -1 if ta.lower() < tb.lower() else 1
        i, j = i2, j2
    return 0


def _row_cmp(x, y):
    if x.year != y.year:
        return -1 if x.year < y.year else 1
    if x.month != y.month:
        return -1 if x.month < y.month else 1
    if x.day != y.day:
        return -1 if x.day < y.day else 1
    c = _coll_cmp(x.meter, y.meter)
    if c:
        return c
    if x.read_id != y.read_id:
        return -1 if x.read_id < y.read_id else 1
    return 0


def _emit_note(note, is_null):
    if is_null:
        return b""
    if len(note) == 0:
        return b'""'
    text = note[:40].decode("cp1252")  # one code point per CP1252 byte
    return b'"' + text.replace('"', '""').encode("utf-8") + b'"'


def parse_unload(data):
    """Parse a valid .tdu v4 unload into sorted _Row objects."""
    if data == b"":
        return []
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    rows = []
    for seq, line in enumerate(lines):
        parts = line.split(b"|", 6)
        if len(parts) != 7:
            raise ValueError("record does not have seven fields")
        period = parts[0].rstrip(b" ")
        acct = parts[1].rstrip(b" ")
        meter = parts[2].rstrip(b" ")
        read_id = parts[3].rstrip(b" ")
        usage = parts[4].rstrip(b" ")
        rate = parts[5].rstrip(b" ")
        note = parts[6].rstrip(b" ")
        row = _Row()
        row.seq = seq
        row.year, row.month, row.day = _parse_period(period)
        row.acct = _decode_number(acct)
        row.read_id = _decode_number(read_id)
        row.usage = _decode_number(usage)
        row.rate = _decode_number(rate)
        row.charge = row.usage * row.rate
        row.meter = meter
        row.note_null = note == b"\\N"
        row.note = b"" if row.note_null else note
        rows.append(row)
    rows.sort(key=cmp_to_key(_row_cmp))  # stable: exact ties keep input order
    return rows


def period_totals(rows):
    """The runtime's period accumulators: binary64, left to right, record order."""
    totals = {}
    for r in sorted(rows, key=lambda row: row.seq):
        key = (r.year, r.month, r.day)
        totals[key] = totals.get(key, 0.0) + r.charge
    return totals


def tcanon_reference(data):
    """The exact TCANON v2 byte stream trexport writes for a valid unload."""
    rows = parse_unload(data)
    totals = period_totals(rows)
    out = [b"#TCANON 2 " + str(len(rows)).encode("ascii") + b"\n"]
    for r in rows:
        line = (
            b"%04d-%02d-%02d|" % (r.year, r.month, r.day)
            + ("%.0f|" % r.acct).encode("ascii")
            + r.meter + b"|"
            + ("%.3f|" % r.usage).encode("ascii")
            + ("%.4f|" % r.rate).encode("ascii")
            + ("%.2f|" % r.charge).encode("ascii")
            + _emit_note(r.note, r.note_null)
        )
        out.append(line + b"\n")
    emitted = set()
    for r in rows:
        key = (r.year, r.month, r.day)
        if key in emitted:
            continue
        emitted.add(key)
        out.append(b"#TOTAL %04d-%02d-%02d|%.2f\n"
                   % (r.year, r.month, r.day, totals[key]))
    out.append(b"#END\n")
    return b"".join(out)


# ---------------------------------------------------------------------------
# Hidden instance generation
# ---------------------------------------------------------------------------

def _filler_row(rng):
    year = rng.choice([2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026])
    month = rng.randrange(1, 13)
    day = rng.randrange(1, 28)
    period = ("%02d-%s-%02d" % (day, MONTH_NAMES[month - 1].decode(), year % 100)).encode()
    acct = rng.randrange(1000000000, 9999999999)
    if str(acct).startswith("88"):
        acct += 100000000
    kind = rng.randrange(4)
    if kind == 0:
        meter = ("%010d" % rng.randrange(0, 10 ** 10)).encode()
    elif kind == 1:
        meter = ("M-%d" % rng.randrange(1, 999)).encode()
    elif kind == 2:
        meter = ("m-%03d" % rng.randrange(1, 999)).encode()
    else:
        meter = ("N%d" % rng.randrange(1, 9999)).encode()
    read_id = ("%d" % rng.randrange(1, 999999)).encode()
    usage = ("%.3f" % (rng.randrange(-500000, 500001) / 1000.0)).encode()
    rate = ("%.4f" % (rng.randrange(1, 10001) / 10000.0)).encode()
    words = ["cycle", "read", "meter", "adjustment", "credit", "field",
             "route", "vacancy", "true-up", "estimate"]
    note = " ".join(rng.choice(words) for _ in range(rng.randrange(0, 5)))
    note_b = note.encode("ascii")
    if rng.randrange(4) == 0:
        note_b += b" " * rng.randrange(1, 4)
    if rng.randrange(6) == 0:
        note_b = note_b + b" caf\xe9"
    if len(note_b) > 120:
        note_b = note_b[:120]
    return b"|".join([period, str(acct).encode(), meter, read_id,
                      usage, rate, note_b])


def _quirk_rows():
    """The fixed probes every hidden corpus instance carries (plus filler)."""
    return [
        # A1: binary64 number handling
        b"01-JAN-24|9000000101|0000000901|9101|0.100|0.0500|half cent probe",
        b"01-JAN-24|9000000124|0000000941|9601|0.100|0.3500|half cent below probe",
        b"01-JAN-24|9000000102|0000000902|9102|-0.001|0.1000|negative sub-cent probe",
        b"01-JAN-24|9000000103|0000000903|9103|-0.000|0.5000|negative zero probe",
        # A2: the 50-year pivot
        b"31-DEC-49|9000000104|0000000904|9104|10.000|0.0100|pivot forty-nine",
        b"01-JAN-50|9000000105|0000000905|9105|10.000|0.0100|pivot fifty",
        b"31-DEC-99|9000000106|0000000906|9106|10.000|0.0100|pivot ninety-nine",
        b"01-JAN-00|9000000107|0000000907|9107|10.000|0.0100|pivot zero",
        # A3: natural collation and numeric READ_ID
        b"01-FEB-24|9000000108|M-9|9209|1.000|0.1000|collation nine",
        b"01-FEB-24|9000000109|M-10|9210|2.000|0.1000|collation ten",
        b"01-FEB-24|9000000110|m-010|9230|3.000|0.1000|collation lower tie",
        b"01-FEB-24|9000000111|M-10|9230|4.000|0.1000|collation exact tie one",
        b"01-FEB-24|9000000112|m-010|9230|5.000|0.1000|collation exact tie two",
        # A4: CHAR semantics, NULL, quoting, 40-code-point cut, CP1252
        b"01-MAR-24|9000000113|0000000911|9311|6.000|0.1000|\\N",
        b"01-MAR-24|9000000114|0000000912|9312|7.000|0.1000|",
        b"01-MAR-24|9000000115|0000000913|9313|8.000|0.1000|     ",
        b"01-MAR-24|9000000116|0000000914|9314|9.000|0.1000|meter reading    ",
        b"01-MAR-24|9000000117|0000000915|9315|10.000|0.1000|0123456789012345678901234567890123456789Z",
        b"01-MAR-24|9000000118|0000000916|9316|11.000|0.1000|He said \"pay\" twice",
        b"01-MAR-24|9000000119|0000000917|9317|12.000|0.1000|rate|charge pair",
        b"01-MAR-24|9000000120|0000000918|9318|13.000|0.1000|caf\xe9 \x80 12.40",
        # B: the suppression trap (clean behaviour is 600.00)
        b"15-MAR-24|8800000001|0000000921|9401|100.000|6.0000|settlement charge",
        b"15-MAR-24|8800000002|0000000922|9402|50.000|10.0000|settlement boundary",
        b"15-MAR-24|8800000003|0000000923|9403|20.000|5.0000|settlement small",
        # signed and large magnitudes
        b"20-MAY-24|9000000121|0000000931|9501|1234567.891|999.9999|large magnitude",
        b"20-MAY-24|9000000122|0000000932|9502|-321.125|0.0750|negative usage",
        b"20-MAY-24|9000000123|0000000933|9503|45.000|-0.1000|negative rate",
    ]


def _accumulation_rows():
    """A period whose charges expose the runtime's accumulator.

    Record order is 2^53, 1, 1.  Left to right in binary64 the two units are
    lost (2^53 + 1 rounds to 2^53); in canonical meter order they are not.
    """
    return [
        b"01-JUN-15|9100000301|Z-BIG|9001|9007199254740992.000|1.0000|carry forward",
        b"01-JUN-15|9100000302|A-PAD1|9002|1.000|1.0000|ledger pad one",
        b"01-JUN-15|9100000303|A-PAD2|9003|1.000|1.0000|ledger pad two",
    ]


def _hidden_tdu(seed):
    if seed in ZERO_ROW_SEEDS:
        return b""
    rng = random.Random(seed * 7919 + 104729)
    rows = _quirk_rows()
    rows.extend(_filler_row(rng) for _ in range(rng.randrange(18, 40)))
    rng.shuffle(rows)
    # Appended after the shuffle: the record order of this period is fixed and
    # differs from its canonical order in every hidden instance.
    rows.extend(_accumulation_rows())
    return b"\n".join(rows) + b"\n"


def _probe_rows(name):
    if name == "number_half_cent":
        return [
            b"01-JAN-24|9000000201|0000002001|1|0.100|0.0500|half cent above",
            b"01-JAN-24|9000000204|0000002004|4|0.100|0.3500|half cent below",
            b"01-JAN-24|9000000202|0000002002|2|0.200|0.1000|whole cents",
            b"01-JAN-24|9000000203|0000002003|3|-0.300|0.5000|negative cents",
        ]
    if name == "number_negative_zero":
        return [
            b"01-JAN-24|9000000211|0000002011|11|-0.001|0.1000|negative sub-cent",
            b"01-JAN-24|9000000212|0000002012|12|-0.000|0.5000|negative zero usage",
            b"01-JAN-24|9000000213|0000002013|13|0.000|0.5000|positive zero usage",
        ]
    if name == "period_pivot":
        return [
            b"31-DEC-99|9000000221|0000002021|21|10.000|0.0100|ninety-nine",
            b"01-JAN-50|9000000222|0000002022|22|10.000|0.0100|fifty",
            b"31-DEC-49|9000000223|0000002023|23|10.000|0.0100|forty-nine",
            b"01-JAN-00|9000000224|0000002024|24|10.000|0.0100|zero",
        ]
    if name == "order_collation":
        # input order: exact-tie second, M-9, exact-tie first, M-10 9010, lower 9030
        return [
            b"01-FEB-24|9000000231|m-010|9030|5.000|0.1000|exact tie second input",
            b"01-FEB-24|9000000232|M-9|9020|2.000|0.1000|nine",
            b"01-FEB-24|9000000233|M-10|9030|4.000|0.1000|exact tie first input",
            b"01-FEB-24|9000000234|M-10|9010|1.000|0.1000|upper ten early",
            b"01-FEB-24|9000000235|m-010|9030|3.000|0.1000|lower tie",
        ]
    if name == "char_notes":
        return [
            b"01-MAR-24|9000000241|0000002041|41|1.000|0.1000|0123456789012345678901234567890123456789Z",
            b"01-MAR-24|9000000242|0000002042|42|2.000|0.1000|\\N",
            b"01-MAR-24|9000000243|0000002043|43|3.000|0.1000|meter reading    ",
            b"01-MAR-24|9000000244|0000002044|44|4.000|0.1000|He said \"pay\" twice",
            b"01-MAR-24|9000000245|0000002045|45|5.000|0.1000|     ",
            b"01-MAR-24|9000000246|0000002046|46|6.000|0.1000|caf\xe9 \x80 12.40",
            b"01-MAR-24|9000000247|0000002047|47|7.000|0.1000|rate|charge pair",
            b"01-MAR-24|9000000248|0000002048|48|8.000|0.1000|",
            b"01-MAR-24|9000000249|0000002049|49|9.000|0.1000|" + b"X" * 120,
        ]
    if name == "zero_rows":
        return []
    if name == "suppression":
        return [
            b"15-MAR-24|8800000001|0000002061|61|100.000|6.0000|settlement charge",
            b"15-MAR-24|8800000002|0000002062|62|50.000|10.0000|settlement boundary",
            b"15-MAR-24|8800000003|0000002063|63|20.000|5.0000|settlement small",
        ]
    if name == "period_totals":
        return _accumulation_rows() + [
            b"01-JUL-15|9100000304|A-HALF1|9004|0.100|0.0500|half cent one",
            b"01-JUL-15|9100000305|A-HALF2|9005|0.100|0.0500|half cent two",
        ]
    raise KeyError(name)


def _build_tdu(rows):
    if not rows:
        return b""
    return b"\n".join(rows) + b"\n"


def generate(seed, profile="hidden"):
    """Return one instance.  profile is 'visible' or 'hidden'."""
    if profile == "visible":
        if seed != VISIBLE_SEED:
            raise ValueError("only seed 1 has a visible profile")
        return {
            "kind": "tdu",
            "name": "visible",
            "seed": seed,
            "tdu": VISIBLE_TDU,
            "expected": tcanon_reference(VISIBLE_TDU),
            "gaps": [],
        }
    if profile != "hidden":
        raise ValueError(profile)
    tdu = _hidden_tdu(seed)
    return {
        "kind": "tdu",
        "name": "hidden-%d" % seed,
        "seed": seed,
        "tdu": tdu,
        "expected": tcanon_reference(tdu),
        "gaps": (["L2"] if not tdu else ["L2", "L4", "L5", "L9"]),
    }


def probe_instance(name):
    seed = PROBE_SEEDS[name]
    tdu = _build_tdu(_probe_rows(name))
    gaps = {
        "number_half_cent": ["L2", "L4"],
        "number_negative_zero": ["L2", "L4"],
        "period_pivot": ["L2", "L4"],
        "order_collation": ["L2", "L4"],
        "char_notes": ["L2", "L4"],
        "zero_rows": ["L2"],
        "suppression": ["L9"],
        "period_totals": ["L5"],
    }[name]
    return {
        "kind": "tdu",
        "name": "probe-" + name,
        "seed": seed,
        "tdu": tdu,
        "expected": tcanon_reference(tdu),
        "gaps": gaps,
    }


# ---------------------------------------------------------------------------
# ELF64 builder, infector and reference restorer
# ---------------------------------------------------------------------------

_ELF_HEADER = struct.Struct("<16sHHIQQQIHHHHHH")
_PHDR = struct.Struct("<IIQQQQQQ")
_SHDR = struct.Struct("<IIQQQQIIQQ")
_ELF_IDENT = b"\x7fELF\x02\x01\x01" + b"\x00" * 9

# The injected detour, executed instead of the original aql_round entry.
# rdi = account text, xmm0 = charge.  If the account begins "88" and the
# charge is above 500.00 the stub returns +0.0, else it returns the charge.
_DETOUR_STUB = bytes([
    0x80, 0x3F, 0x38,              # cmp byte [rdi], '8'
    0x75, 0x18,                    # jne +0x18  -> ret at 29
    0x80, 0x7F, 0x01, 0x38,        # cmp byte [rdi+1], '8'
    0x75, 0x12,                    # jne +0x12  -> ret at 29
    0xF2, 0x0F, 0x10, 0x0D, 0x11, 0x00, 0x00, 0x00,   # movsd xmm1,[rip+17]
    0x66, 0x0F, 0x2E, 0xC1,        # ucomisd xmm0, xmm1
    0x76, 0x04,                    # jbe +4     -> ret at 29
    0x66, 0x0F, 0xEF, 0xC0,        # pxor xmm0, xmm0
    0xC3,                          # ret
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x7F, 0x40,   # 500.0
])

PAYLOAD_MAGIC = b"AQLRT1\x00\x00"
PAYLOAD_CODE_OFFSET = 106


def _align8(value):
    return (value + 7) & ~7


def build_clean_elf(seed, variant="plain", notes=1):
    """Build a valid ELF64 ET_DYN shared object and its aql_round offset."""
    if variant not in ("plain", "nosh", "extended"):
        raise ValueError(variant)
    if notes not in (1, 2):
        raise ValueError(notes)
    rng = random.Random(seed * 104729 + 17)
    code_off = 0x200
    code_len = 192
    code = bytes(rng.randrange(256) for _ in range(code_len))

    note1_off = 0x400
    note1 = struct.pack("<III", 4, 16, 3) + b"GNU\x00" + bytes(
        rng.randrange(256) for _ in range(16))
    note2_off = 0x440
    note2 = struct.pack("<III", 8, 8, 1) + b"TRELLIS\x00" + b"4.2.0\x00\x00\x00"

    shstr_off = 0x480
    shstr = b"\x00.text\x00.note.gnu.build-id\x00.shstrtab\x00"
    shoff = _align8(shstr_off + len(shstr))
    n_sections = 4
    if variant == "nosh":
        total = shstr_off + len(shstr)
    else:
        total = shoff + n_sections * 64

    phnum = 3 if notes == 1 else 4
    e_shoff = 0 if variant == "nosh" else shoff
    e_shnum = n_sections if variant == "plain" else 0
    e_shstrndx = 3 if variant == "plain" else 0
    e_phnum = phnum
    if variant == "extended":
        e_phnum = 0xFFFF
        e_shstrndx = 0xFFFF

    buf = bytearray(total)
    _ELF_HEADER.pack_into(buf, 0, _ELF_IDENT, 3, 62, 1, code_off,
                          64, e_shoff, 0, 64, 56, e_phnum, 64, e_shnum,
                          e_shstrndx)

    phdrs = [(1, 5, 0, 0, 0, total, total, 0x1000),
             (4, 4, note1_off, note1_off, note1_off, len(note1), len(note1), 4)]
    if notes == 2:
        phdrs.append((4, 4, note2_off, note2_off, note2_off,
                      len(note2), len(note2), 4))
    phdrs.append((0x6474E551, 6, 0, 0, 0, 0, 0, 0x10))
    if len(phdrs) != phnum:
        raise AssertionError("program header count")
    for i, ph in enumerate(phdrs):
        _PHDR.pack_into(buf, 64 + i * 56, *ph)

    buf[code_off:code_off + code_len] = code
    buf[note1_off:note1_off + len(note1)] = note1
    if notes == 2:
        buf[note2_off:note2_off + len(note2)] = note2
    buf[shstr_off:shstr_off + len(shstr)] = shstr

    if variant != "nosh":
        section0 = (0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0)
        if variant == "extended":
            section0 = (0, 0, 0, 0, 0, n_sections, 3, phnum, 0, 0)
        sections = [
            section0,
            (1, 1, 6, code_off, code_off, code_len, 0, 0, 16, 0),
            (7, 7, 2, note1_off, note1_off, len(note1), 0, 0, 4, 0),
            (26, 3, 0, 0, shstr_off, len(shstr), 0, 0, 1, 0),
        ]
        for i, sh in enumerate(sections):
            _SHDR.pack_into(buf, shoff + i * 64, *sh)

    return bytes(buf), code_off


def _elf_header(data):
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    if data[4] != 2 or data[5] != 1:
        raise ValueError("not ELF64 little-endian")
    (ident, e_type, e_machine, e_version, e_entry, e_phoff, e_shoff,
     e_flags, e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum,
     e_shstrndx) = _ELF_HEADER.unpack_from(data, 0)
    phnum_real = e_phnum
    shnum_real = e_shnum
    shstrndx_real = e_shstrndx
    if e_shoff and e_shnum == 0:
        shnum_real = struct.unpack_from("<Q", data, e_shoff + 32)[0]
    if e_shoff and e_phnum == 0xFFFF:
        phnum_real = struct.unpack_from("<I", data, e_shoff + 44)[0]
    if e_shoff and e_shstrndx == 0xFFFF:
        shstrndx_real = struct.unpack_from("<I", data, e_shoff + 40)[0]
    return {
        "type": e_type,
        "machine": e_machine,
        "phoff": e_phoff,
        "phentsize": e_phentsize,
        "phnum": e_phnum,
        "phnum_real": phnum_real,
        "shoff": e_shoff,
        "shentsize": e_shentsize,
        "shnum": e_shnum,
        "shnum_real": shnum_real,
        "shstrndx": e_shstrndx,
        "shstrndx_real": shstrndx_real,
    }


def infect_elf(clean, target_off):
    """Apply the Meridian injector anatomy to a clean library."""
    eh = _elf_header(clean)
    phoff = eh["phoff"]
    phnum = eh["phnum_real"]
    if eh["phentsize"] != 56:
        raise ValueError("unexpected phentsize")
    last_note = None
    last_note_bytes = None
    for i in range(phnum):
        off = phoff + i * 56
        p_type = struct.unpack_from("<I", clean, off)[0]
        if p_type == 4:
            last_note = i
            last_note_bytes = clean[off:off + 56]
    if last_note is None:
        raise ValueError("clean library has no PT_NOTE")

    original_size = len(clean)
    vaddr = original_size + 0x1000
    payload = bytearray()
    payload += PAYLOAD_MAGIC
    payload += b"\x00\x00"  # two reserved bytes; the code is at offset 106
    payload += struct.pack("<Q", original_size)
    payload += struct.pack("<Q", target_off)
    payload += clean[target_off:target_off + 12]
    payload += struct.pack("<Q", eh["shoff"])
    payload += struct.pack("<H", eh["shnum"])
    payload += struct.pack("<H", eh["shstrndx"])
    payload += last_note_bytes
    payload += _DETOUR_STUB
    if len(payload) != PAYLOAD_CODE_OFFSET + len(_DETOUR_STUB):
        raise AssertionError("payload layout")

    rel32 = (vaddr + PAYLOAD_CODE_OFFSET) - (target_off + 5)
    if not -(2 ** 31) <= rel32 < 2 ** 31:
        raise ValueError("detour target out of rel32 range")
    patch = b"\xe9" + struct.pack("<i", rel32) + b"\x90" * 7
    if len(patch) != 12:
        raise AssertionError("patch length")

    out = bytearray(clean) + payload
    new_ph = _PHDR.pack(1, 5, original_size, vaddr, vaddr,
                        len(payload), len(payload), 0x1000)
    off = phoff + last_note * 56
    out[off:off + 56] = new_ph
    out[target_off:target_off + 12] = patch

    if eh["shoff"]:
        if eh["shnum"] == 0:
            count = struct.unpack_from("<Q", clean, eh["shoff"] + 32)[0]
            extended = True
        else:
            count = eh["shnum"]
            extended = False
    else:
        count = 0
        extended = False

    new_shoff = len(out)
    if count:
        table = bytearray(clean[eh["shoff"]:eh["shoff"] + count * 64])
        if extended:
            old = struct.unpack_from("<Q", table, 32)[0]
            struct.pack_into("<Q", table, 32, old + 1)
        out += table
    # one extra zero-name PROGBITS entry appended after the copy
    out += _SHDR.pack(0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
    struct.pack_into("<Q", out, 0x28, new_shoff)
    if extended:
        pass  # e_shnum stays 0; section 0's copied sh_size carries the count
    elif count == 0:
        struct.pack_into("<H", out, 0x3C, 1)
    else:
        struct.pack_into("<H", out, 0x3C, count + 1)
    return bytes(out)


def restore_elf(data):
    """Reverse the injector; clean files pass through unchanged."""
    eh = _elf_header(data)
    phoff = eh["phoff"]
    for i in range(eh["phnum_real"]):
        off = phoff + i * 56
        p_type, _flags, p_offset = struct.unpack_from("<IIQ", data, off)
        if p_type != 1:
            continue
        if p_offset + 8 > len(data) or data[p_offset:p_offset + 8] != PAYLOAD_MAGIC:
            continue
        p = p_offset
        if p + PAYLOAD_CODE_OFFSET > len(data):
            raise ValueError("truncated payload")
        original_size = struct.unpack_from("<Q", data, p + 10)[0]
        target_off = struct.unpack_from("<Q", data, p + 18)[0]
        original_code = data[p + 26:p + 38]
        original_shoff = struct.unpack_from("<Q", data, p + 38)[0]
        original_shnum = struct.unpack_from("<H", data, p + 46)[0]
        original_shstrndx = struct.unpack_from("<H", data, p + 48)[0]
        original_note = data[p + 50:p + 106]
        if original_size > len(data) or target_off + 12 > original_size:
            raise ValueError("payload names out-of-range offsets")
        out = bytearray(data[:original_size])
        out[target_off:target_off + 12] = original_code
        out[off:off + 56] = original_note
        struct.pack_into("<Q", out, 0x28, original_shoff)
        struct.pack_into("<H", out, 0x3C, original_shnum)
        struct.pack_into("<H", out, 0x3E, original_shstrndx)
        return bytes(out)
    return data


def manifest_bytes(clean, name="libaquilon.so"):
    digest = hashlib.sha256(clean).hexdigest()
    return (
        b"# Meridian Utility Systems - Aquilon 7.1 release manifest\n"
        b"# file size sha256\n"
        + name.encode("ascii") + b" " + str(len(clean)).encode("ascii")
        + b" " + digest.encode("ascii") + b"\n"
    )


def _variant_specs():
    return [
        {"name": "plain_one_note", "seed": 7001, "variant": "plain", "notes": 1},
        {"name": "plain_two_notes", "seed": 7002, "variant": "plain", "notes": 2},
        {"name": "nosh_one_note", "seed": 7003, "variant": "nosh", "notes": 1},
        {"name": "nosh_two_notes", "seed": 7004, "variant": "nosh", "notes": 2},
        {"name": "extended_one_note", "seed": 7005, "variant": "extended", "notes": 1},
        {"name": "extended_two_notes", "seed": 7006, "variant": "extended", "notes": 2},
        {"name": "plain_one_note_b", "seed": 7007, "variant": "plain", "notes": 1},
        {"name": "extended_one_note_b", "seed": 7008, "variant": "extended", "notes": 1},
    ]


ELF_VARIANTS = _variant_specs()


def generate_elf(seed, variant="plain", notes=1, name="libaquilon.so"):
    clean, target_off = build_clean_elf(seed, variant=variant, notes=notes)
    infested = infect_elf(clean, target_off)
    return {
        "kind": "elf",
        "name": "elf-%s" % variant,
        "seed": seed,
        "clean": clean,
        "infested": infested,
        "target_off": target_off,
        "manifest": manifest_bytes(clean, name),
        "gaps": ["L1"],
    }


# ---------------------------------------------------------------------------
# Independent validator
# ---------------------------------------------------------------------------

_PERIOD_RE = re.compile(rb"^\d{2}-(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)-\d{2}$")
_METER_RE = re.compile(rb"^[A-Za-z0-9-]{1,20}$")
_DIGITS_RE = re.compile(rb"^[0-9]{1,12}$")
_RID_RE = re.compile(rb"^[0-9]{1,12}$")
_NUM_RE = re.compile(rb"^[+-]?[0-9]+(\.[0-9]+)?$")
_ISO_RE = re.compile(rb"^\d{4}-\d{2}-\d{2}$")
_USAGE_OUT_RE = re.compile(rb"^-?\d+\.\d{3}$")
_RATE_OUT_RE = re.compile(rb"^-?\d+\.\d{4}$")
_CHARGE_OUT_RE = re.compile(rb"^-?\d+\.\d{2}$")


def _days_in_month(year, month):
    if month == 2:
        leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
        return 29 if leap else 28
    return 30 if month in (4, 6, 9, 11) else 31


def _validate_unload_bytes(data):
    problems = []
    if data == b"":
        return problems
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    for number, line in enumerate(lines, 1):
        where = "record %d" % number
        if b"\r" in line:
            problems.append(where + ": CR byte")
        if b"\x00" in line:
            problems.append(where + ": NUL byte")
        if len(line) > 4096:
            problems.append(where + ": line too long")
        parts = line.split(b"|", 6)
        if len(parts) != 7:
            problems.append(where + ": not seven |-separated fields")
            continue
        period, acct, meter, rid, usage, rate, note = [p.rstrip(b" ") for p in parts]
        if not _PERIOD_RE.fullmatch(period):
            problems.append(where + ": bad period %r" % period)
        else:
            yy = int(period[7:9])
            year = 2000 + yy if yy <= 49 else 1900 + yy
            month = _MONTH_NUMBER[period[3:6]]
            day = int(period[0:2])
            if not 1 <= day <= _days_in_month(year, month):
                problems.append(where + ": day out of range")
        if not _DIGITS_RE.fullmatch(acct):
            problems.append(where + ": bad account %r" % acct)
        if not _METER_RE.fullmatch(meter):
            problems.append(where + ": bad meter id %r" % meter)
        if not _RID_RE.fullmatch(rid):
            problems.append(where + ": bad read id %r" % rid)
        for label, value in ((b"usage", usage), (b"rate", rate)):
            if not _NUM_RE.fullmatch(value):
                problems.append(where + ": bad %s %r" % (label, value))
            else:
                try:
                    float(value.decode("ascii"))
                except ValueError:
                    problems.append(where + ": unparsable %s" % label.decode())
        st = note
        if st != b"\\N":
            if len(st) > 120:
                problems.append(where + ": note longer than 120 bytes")
            try:
                st.decode("cp1252")
            except UnicodeDecodeError:
                problems.append(where + ": note is not valid CP1252")
    return problems


def _validate_expected_output(tdu, expected):
    problems = []
    try:
        in_rows = parse_unload(tdu)
    except (ValueError, KeyError, UnicodeDecodeError) as exc:
        return ["reference cannot parse the unload: %s" % exc]
    if not expected.endswith(b"\n"):
        problems.append("output does not end with LF")
        return problems
    lines = expected.split(b"\n")[:-1]
    if not lines:
        problems.append("empty output")
        return problems
    header = lines[0]
    m = re.fullmatch(rb"#TCANON 2 (\d+)", header)
    if not m:
        problems.append("bad header %r" % header)
        return problems
    if int(m.group(1)) != len(in_rows):
        problems.append("header count does not match the unload")
    if lines[-1] != b"#END":
        problems.append("missing #END")
    middle = lines[1:-1]
    split = len(middle)
    while split > 0 and middle[split - 1].startswith(b"#TOTAL "):
        split -= 1
    body = middle[:split]
    control = middle[split:]
    if any(line.startswith(b"#TOTAL ") for line in body):
        problems.append("control totals are interleaved with the rows")
    if len(body) != len(in_rows):
        problems.append("row count does not match the unload")
    seen = []
    for number, line in enumerate(body, 1):
        where = "output row %d" % number
        if b"\r" in line:
            problems.append(where + ": CR byte")
        parts = line.split(b"|", 6)
        if len(parts) != 7:
            problems.append(where + ": not seven |-separated fields")
            continue
        period, acct, meter, usage, rate, charge, note = parts
        if not _ISO_RE.fullmatch(period):
            problems.append(where + ": bad ISO period %r" % period)
        if not re.fullmatch(rb"^[0-9]+$", acct):
            problems.append(where + ": bad account %r" % acct)
        if not _METER_RE.fullmatch(meter):
            problems.append(where + ": bad meter %r" % meter)
        if not _USAGE_OUT_RE.fullmatch(usage):
            problems.append(where + ": usage not %.3f")
        if not _RATE_OUT_RE.fullmatch(rate):
            problems.append(where + ": rate not %.4f")
        if not _CHARGE_OUT_RE.fullmatch(charge):
            problems.append(where + ": charge not %.2f")
        if note != b"":
            if len(note) < 2 or note[:1] != b'"' or note[-1:] != b'"':
                problems.append(where + ": note is not quoted or null")
            else:
                try:
                    note.decode("utf-8")
                except UnicodeDecodeError:
                    problems.append(where + ": note is not UTF-8")
        key = (period, acct, meter, usage, rate)
        seen.append(key)
    want = []
    for r in in_rows:
        want.append((
            b"%04d-%02d-%02d" % (r.year, r.month, r.day),
            ("%.0f" % r.acct).encode("ascii"),
            r.meter,
            ("%.3f" % r.usage).encode("ascii"),
            ("%.4f" % r.rate).encode("ascii"),
        ))
    if sorted(seen) != sorted(want):
        problems.append("output rows do not cover the unload rows exactly")
    # order: period then natural meter (READ_ID is not in the output)
    for a, b in zip(body, body[1:]):
        pa, ma = a.split(b"|", 6)[0], a.split(b"|", 6)[2]
        pb, mb = b.split(b"|", 6)[0], b.split(b"|", 6)[2]
        if pa > pb:
            problems.append("output periods out of order")
            break
        if pa == pb and _coll_cmp(ma, mb) > 0:
            problems.append("output meters out of collation order")
            break
    # control totals: one per distinct period, in the period order of the rows
    periods = []
    for r in in_rows:
        key = b"%04d-%02d-%02d" % (r.year, r.month, r.day)
        if not periods or periods[-1] != key:
            periods.append(key)
    got_periods = []
    for line in control:
        match = re.fullmatch(rb"#TOTAL (\d{4}-\d{2}-\d{2})\|(-?\d+\.\d{2})", line)
        if not match:
            problems.append("bad control total line %r" % line)
            continue
        got_periods.append(match.group(1))
    if got_periods != periods:
        problems.append("control totals do not cover the distinct periods in order")
    return problems


def _validate_elf_bytes(clean):
    problems = []
    try:
        eh = _elf_header(clean)
    except ValueError as exc:
        return [str(exc)]
    if eh["type"] != 3:
        problems.append("clean file is not ET_DYN")
    if eh["machine"] != 62:
        problems.append("clean file is not EM_X86_64")
    if eh["phentsize"] != 56:
        problems.append("clean file has a bad e_phentsize")
    if eh["phnum_real"] < 1 or eh["phoff"] + eh["phnum_real"] * 56 > len(clean):
        problems.append("program header table out of bounds")
        return problems
    notes = 0
    has_load = False
    segments = []
    for i in range(eh["phnum_real"]):
        ph = _PHDR.unpack_from(clean, eh["phoff"] + i * 56)
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = ph
        segments.append(ph)
        if p_type == 4:
            notes += 1
        if p_type == 1:
            has_load = True
            if p_offset + p_filesz > len(clean):
                problems.append("loadable segment exceeds the file")
            if p_align > 1 and (p_vaddr - p_offset) % p_align != 0:
                problems.append("loadable segment is not properly aligned")
    if notes < 1:
        problems.append("clean file has no PT_NOTE")
    if not has_load:
        problems.append("clean file has no PT_LOAD")
    if eh["shoff"]:
        if eh["shentsize"] != 64:
            problems.append("bad e_shentsize")
        if eh["shoff"] + eh["shnum_real"] * 64 > len(clean):
            problems.append("section header table out of bounds")
        else:
            strtab_off = None
            if eh["shstrndx_real"] != 0:
                idx = eh["shstrndx_real"]
                if idx >= eh["shnum_real"]:
                    problems.append("bad e_shstrndx")
                else:
                    sh = _SHDR.unpack_from(clean, eh["shoff"] + idx * 64)
                    strtab_off = sh[4]
                    strtab_size = sh[5]
            for i in range(eh["shnum_real"]):
                sh = _SHDR.unpack_from(clean, eh["shoff"] + i * 64)
                if strtab_off is not None and sh[0] >= strtab_size:
                    problems.append("section name outside the string table")
                    break
                if sh[1] not in (0, 8) and sh[4] + sh[5] > len(clean):
                    problems.append("section contents exceed the file")
                    break
    extended = (eh["phnum"] == 0xFFFF or eh["shstrndx"] == 0xFFFF
                or (eh["shoff"] != 0 and eh["shnum"] == 0))
    if not extended:
        try:
            from elftools.elf.elffile import ELFFile
            elf = ELFFile(io.BytesIO(clean))
            header = elf.header
            if header["e_type"] != "ET_DYN":
                problems.append("pyelftools rejects the object type")
            if sum(1 for seg in elf.iter_segments()
                   if seg["p_type"] == "PT_NOTE") < 1:
                problems.append("pyelftools sees no PT_NOTE")
            if eh["shoff"]:
                list(elf.iter_sections())
        except Exception as exc:  # noqa: BLE001 - report any parse failure
            problems.append("pyelftools cannot parse the clean file: %s" % exc)
    return problems


def _validate_elf_instance(inst):
    problems = []
    clean = inst["clean"]
    infested = inst["infested"]
    problems.extend(_validate_elf_bytes(clean))
    if restore_elf(infested) != clean:
        problems.append("reference restoration is not byte-identical")
    try:
        eh = _elf_header(infested)
    except ValueError as exc:
        return problems + ["infested file: %s" % exc]
    found = False
    for i in range(eh["phnum_real"]):
        ph = _PHDR.unpack_from(infested, eh["phoff"] + i * 56)
        if ph[0] == 1 and ph[2] + 8 <= len(infested):
            if infested[ph[2]:ph[2] + 8] == PAYLOAD_MAGIC:
                found = True
    if not found:
        problems.append("infested file has no AQLRT1 payload")
    digest = hashlib.sha256(clean).hexdigest().encode("ascii")
    entry = (b"libaquilon.so " + str(len(clean)).encode("ascii") + b" "
             + digest + b"\n")
    if entry not in inst["manifest"]:
        problems.append("manifest does not certify the clean file")
    return problems


def validate_instance(inst):
    """Return a list of problems; empty means the instance is well formed."""
    if inst.get("kind") == "tdu":
        problems = _validate_unload_bytes(inst["tdu"])
        problems.extend(_validate_expected_output(inst["tdu"], inst["expected"]))
        return problems
    if inst.get("kind") == "elf":
        return _validate_elf_instance(inst)
    return ["unknown instance kind"]


def validate_all(profile="hidden"):
    """Validate every generated instance of a profile."""
    problems = []
    if profile == "visible":
        inst = generate(VISIBLE_SEED, "visible")
        problems.extend(validate_instance(inst))
        if inst["expected"] != VISIBLE_EXPECTED:
            problems.append("reference output differs from the shipped export")
        return problems
    for seed in CORPUS_SEEDS:
        inst = generate(seed, "hidden")
        for p in validate_instance(inst):
            problems.append("seed %d: %s" % (seed, p))
    for name in PROBE_SEEDS:
        inst = probe_instance(name)
        for p in validate_instance(inst):
            problems.append("probe %s: %s" % (name, p))
    for spec in ELF_VARIANTS:
        inst = generate_elf(spec["seed"], spec["variant"], spec["notes"])
        for p in validate_instance(inst):
            problems.append("elf %s: %s" % (spec["name"], p))
    return problems


if __name__ == "__main__":  # pragma: no cover - manual aid
    import sys
    found = validate_all(sys.argv[1] if len(sys.argv) > 1 else "hidden")
    if found:
        print("\n".join(found))
        raise SystemExit(1)
    print("ok")