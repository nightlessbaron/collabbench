"""Reference implementation and instance generator for the Cadence Rights Exchange task.

The module owns one reading of the engraved notation, the ``correct`` reading:
MusicXML 4.0 / SMuFL semantics for clefs, key regions, accidentals and ties.
The generator renders the glyph stream from a higher level score model and the
expected canonical notation is computed from that model by the same semantics
function.  ``parse_files`` is an independent front end that rebuilds the same
model from the SVG alone; identifiability.py checks that the two agree.

Everything here is deterministic and uses only the standard library.
"""

from fractions import Fraction
from bisect import bisect_right
import copy
import hashlib
import json
import random
import re
import xml.etree.ElementTree as ET

SPB = 12  # horizontal grid units per quarter-note beat

# ---------------------------------------------------------------------------
# Pitch arithmetic
# ---------------------------------------------------------------------------

PC = (0, 2, 4, 5, 7, 9, 11)          # C D E F G A B
LETTERS = "CDEFGAB"
SHARP_ORDER = (3, 0, 4, 1, 5, 2, 6)  # F C G D A E B (letter indexes)
FLAT_ORDER = (6, 2, 5, 1, 4, 0, 3)   # B E A D G C F

CLEF_ANCHOR = {"gClef": 32, "fClef": 24, "cClef": 28}  # G4, F3, C4


def natural_midi(diatonic):
    """MIDI number of a natural diatonic step (C4 == 60)."""
    octave, letter = divmod(int(diatonic), 7)
    return 12 * (octave + 1) + PC[letter]


def letter_of(diatonic):
    return int(diatonic) % 7


def key_alteration(fifths, letter):
    """The alteration the key signature applies to one letter."""
    if fifths > 0:
        return 1 if letter in SHARP_ORDER[:fifths] else 0
    if fifths < 0:
        return -1 if letter in FLAT_ORDER[:-fifths] else 0
    return 0


def tonic_pc(fifths, mode):
    pc = (int(fifths) * 7) % 12
    if mode == "minor":
        pc = (pc + 9) % 12
    return pc


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def F(value):
    if isinstance(value, Fraction):
        return value
    if isinstance(value, float):
        # Some CPython builds no longer accept a bare float in Fraction();
        # the decimal spelling is exact for the generator's dyadic values.
        return Fraction(str(value))
    return Fraction(value)


def frac_str(value):
    f = F(value)
    return str(f.numerator) if f.denominator == 1 else "%d/%d" % (f.numerator, f.denominator)


def _num(value):
    """Coordinate formatting: exact decimal, no exponents."""
    f = F(value)
    if f.denominator == 1:
        return str(f.numerator)
    return ("%.6f" % float(f)).rstrip("0").rstrip(".")


def effective_duration(value, dot, tuplet):
    d = F(value)
    if dot:
        d *= Fraction(3, 2)
    if tuplet:
        d *= Fraction(2, 3)
    return d


NOTEHEAD_BASE = {
    "noteheadWhole": Fraction(4),
    "noteheadHalf": Fraction(2),
    "noteheadBlack": Fraction(1),
}
FLAG_VALUE = {
    "flag8th": Fraction(1, 2),
    "flag16th": Fraction(1, 4),
    "flag32nd": Fraction(1, 8),
}
VALUE_FLAG = {
    Fraction(1, 2): "flag8th",
    Fraction(1, 4): "flag16th",
    Fraction(1, 8): "flag32nd",
}
ACCIDENTAL_GLYPH = {
    -2: "accidentalDoubleFlat",
    -1: "accidentalFlat",
    0: "accidentalNatural",
    1: "accidentalSharp",
    2: "accidentalDoubleSharp",
}
GLYPH_ACCIDENTAL = {v: k for k, v in ACCIDENTAL_GLYPH.items()}
REST_GLYPH = {
    Fraction(4): "restWhole",
    Fraction(2): "restHalf",
    Fraction(1): "restQuarter",
    Fraction(1, 2): "rest8th",
    Fraction(1, 4): "rest16th",
    Fraction(1, 8): "rest32nd",
}
KEY_GLYPHS = {"keySharp", "keyFlat", "keyNatural"}
NOTEHEAD_GLYPHS = set(NOTEHEAD_BASE)

FLAG_GLYPHS = {name + suffix for name in FLAG_VALUE
               for suffix in ("Up", "Down")}

GLYPH_NAMES = (
    set(NOTEHEAD_BASE) | FLAG_GLYPHS | set(GLYPH_ACCIDENTAL)
    | set(REST_GLYPH.values()) | KEY_GLYPHS | set(CLEF_ANCHOR)
    | {"augmentationDot", "tuplet3", "tie", "slur", "barlineSingle",
       "barlineFinal", "ledgerLine", "stem", "timeSigCommon",
       "timeSigCutCommon"}
    | {"timeSig%d" % i for i in range(10)}
)


def _flag_name(value):
    return VALUE_FLAG.get(F(value))


# ---------------------------------------------------------------------------
# Rendering a score model to the engraver's SVG format
# ---------------------------------------------------------------------------

def render_model(model):
    """Return {relative_path: text} for one score bundle."""
    work_id = model.get("work_id", "score")
    meta = {
        "format": "cre-engraver-svg/1",
        "work_id": work_id,
        "title": model.get("title", ""),
        "composer": model.get("composer", ""),
        "mode": model.get("mode", "major"),
        "spaces_per_beat": SPB,
        "staves": [{"staff": 0, "top_y": 0.0, "bottom_y": 8.0}],
    }
    glyphs = []  # (glyph, staff, x, y)

    for clef in model.get("clefs", [{"x": 0, "glyph": "gClef", "y": 6}]):
        glyphs.append((clef["glyph"], clef.get("staff", 0), F(clef["x"]), F(clef["y"])))

    for key in model.get("keys", [{"x": 0, "fifths": 0}]):
        x = F(key["x"])
        fifths = int(key["fifths"])
        if fifths > 0:
            for i in range(fifths):
                glyphs.append(("keySharp", 0, x + Fraction(i, 2), Fraction(2)))
        elif fifths < 0:
            for i in range(-fifths):
                glyphs.append(("keyFlat", 0, x + Fraction(i, 2), Fraction(2)))
        elif x > 0:
            glyphs.append(("keyNatural", 0, x, Fraction(2)))

    for ts in model.get("timesigs", []):
        top, bottom = ts["top"], ts["bottom"]
        x = F(ts.get("x", 0))
        glyphs.append(("timeSig%d" % top, 0, x, Fraction(1)))
        glyphs.append(("timeSig%d" % bottom, 0, x, Fraction(3)))

    ends = [F(x) for x in model.get("measure_ends", [])]
    for i, x in enumerate(ends):
        glyph = "barlineFinal" if i == len(ends) - 1 else "barlineSingle"
        glyphs.append((glyph, 0, x, Fraction(4)))

    notes = model.get("notes", [])
    for note in notes:
        x = F(note["x"])
        y = F(note["y"])
        value = F(note["value"])
        if value == 4:
            head = "noteheadWhole"
        elif value == 2:
            head = "noteheadHalf"
        else:
            head = "noteheadBlack"
        glyphs.append((head, 0, x, y))
        if value < 1:
            flag = _flag_name(value)
            if flag:
                glyphs.append((flag + "Up", 0, x, y - Fraction(3, 2)))
        if note.get("dot"):
            glyphs.append(("augmentationDot", 0, x + 1, y))
        if note.get("tuplet"):
            glyphs.append(("tuplet3", 0, x, y + 2))
        acc = note.get("acc")
        if acc is not None:
            glyphs.append((ACCIDENTAL_GLYPH[int(acc)], 0, x - 1, y))
        if note.get("tie_to") is not None:
            glyphs.append(("tie", 0, x, y - 2))
        # ledger lines
        iy = int(y)
        if iy <= -2:
            ly = -2
            while ly >= iy:
                glyphs.append(("ledgerLine", 0, x, Fraction(ly)))
                ly -= 2
        if iy >= 10:
            ly = 10
            while ly <= iy:
                glyphs.append(("ledgerLine", 0, x, Fraction(ly)))
                ly += 2

    for rest in model.get("rests", []):
        x = F(rest["x"])
        glyph = REST_GLYPH.get(F(rest["value"]), "restQuarter")
        glyphs.append((glyph, 0, x, Fraction(4)))

    for slur in model.get("slurs", []):
        glyphs.append(("slur", 0, F(slur["x"]), F(slur["y"])))

    lines = ['<svg xmlns="http://www.w3.org/2000/svg" version="1.1">']
    for glyph, staff, x, y in glyphs:
        lines.append(
            '  <g data-glyph="%s" data-staff="%d" data-x="%s" data-y="%s"/>'
            % (glyph, int(staff), _num(x), _num(y))
        )
    lines.append("</svg>")
    return {
        "score.meta.json": json.dumps(meta, indent=2, sort_keys=True) + "\n",
        "score.svg": "\n".join(lines) + "\n",
    }


# ---------------------------------------------------------------------------
# Canonical semantics
# ---------------------------------------------------------------------------

def _measure_of(x, measure_ends):
    return bisect_right(measure_ends, x) + 1


def _regions(key_changes, measure_ends, mode):
    by_measure = {}
    for key in key_changes:
        m = _measure_of(F(key["x"]), measure_ends)
        by_measure[m] = int(key["fifths"])
    regions = []
    for m in range(1, len(measure_ends) + 1):
        if m in by_measure:
            regions.append({"start_measure": m, "fifths": by_measure[m], "mode": mode})
        elif m == 1:
            regions.append({"start_measure": 1, "fifths": 0, "mode": mode})
    if not regions:
        regions.append({"start_measure": 1, "fifths": 0, "mode": mode})
    return regions


def _fifths_for(regions, measure):
    value = regions[0]["fifths"]
    for region in regions:
        if region["start_measure"] <= measure:
            value = region["fifths"]
    return value


def _clef_at(clefs, x, rule):
    chosen = None
    for clef in clefs:
        if F(clef["x"]) <= x:
            chosen = clef
    if rule == "ignore_clef_change" and clefs:
        chosen = clefs[0]
    if chosen is None and clefs:
        chosen = clefs[0]
    return chosen


def _canonical(events, clefs_by_staff, key_changes, measure_ends, mode,
               rule="correct", tie_pairs=None, auto_tie=False):
    """Turn resolved glyph events into canonical notation.

    ``events`` are dicts with staff, x, y, dur, acc (None or int) and tie (bool),
    already sorted by (staff, x).
    """
    raw = []
    state = {}
    current_measure = {}
    for event in events:
        staff = int(event["staff"])
        x = F(event["x"])
        y = F(event["y"])
        measure = _measure_of(x, measure_ends)
        fifths = _fifths_for(_regions(key_changes, measure_ends, mode), measure)
        if rule == "first_key":
            fifths = int(key_changes[0]["fifths"]) if key_changes else 0
        clefs = clefs_by_staff.get(staff, [{"x": 0, "glyph": "gClef", "y": 6}])
        clef = _clef_at(clefs, x, rule)
        diatonic = CLEF_ANCHOR.get(clef["glyph"], 32) + int(F(clef["y"]) - y)
        letter = letter_of(diatonic)

        if current_measure.get(staff) != measure:
            state[staff] = {}
            current_measure[staff] = measure

        explicit = event.get("acc")
        if explicit is not None:
            explicit = int(explicit)
            if rule == "clamp":
                explicit = max(-1, min(1, explicit))
        stored = state[staff].get((letter, diatonic // 7))
        if explicit is not None:
            stored = explicit
            if rule != "no_carry":
                state[staff][(letter, diatonic // 7)] = explicit

        key_alt = key_alteration(fifths, letter)
        if stored is None or rule == "no_carry" and explicit is None:
            alteration = key_alt
        elif rule == "additive":
            alteration = key_alt + stored
        else:
            alteration = stored

        midi = natural_midi(diatonic) + alteration
        raw.append({
            "staff": staff,
            "onset": x / F(SPB),
            "dur": F(event["dur"]),
            "midi": midi,
            "x": x,
            "y": y,
            "tie": bool(event.get("tie")),
        })

    if rule == "tie_slur":
        pairs = {}
    elif auto_tie:
        # a tie joins a notehead to the notehead that starts where it ends, on
        # the same staff and line; index the candidates by their onsets.
        starts = {}
        for idx, note in enumerate(raw):
            starts.setdefault((note["staff"], note["y"], note["onset"]), idx)
        pairs = {}
        for idx, note in enumerate(raw):
            if note["tie"]:
                target = starts.get((note["staff"], note["y"], note["onset"] + note["dur"]))
                if target is not None and target != idx:
                    pairs[idx] = target
    else:
        pairs = dict(tie_pairs or {})

    targets = set(pairs.values())
    merged = []
    next_group = 1
    for idx, note in enumerate(raw):
        if idx in targets:
            continue
        chain = [idx]
        cur = idx
        while cur in pairs:
            cur = pairs[cur]
            if cur in chain:
                break
            chain.append(cur)
        onset = raw[chain[0]]["onset"]
        duration = sum((raw[i]["dur"] for i in chain), Fraction(0))
        midi = raw[chain[0]]["midi"]
        group = None
        if len(chain) > 1:
            group = next_group
            next_group += 1
        merged.append({
            "staff": raw[chain[0]]["staff"],
            "voice": 0,
            "onset": frac_str(onset),
            "duration": frac_str(duration),
            "midi": int(midi),
            "tie_group": group,
        })

    merged.sort(key=lambda n: (n["staff"], F(n["onset"]), n["midi"]))
    return {
        "notes": merged,
        "key_regions": _regions(key_changes, measure_ends, mode),
    }


# ---------------------------------------------------------------------------
# Truth from the generation model
# ---------------------------------------------------------------------------

def model_truth(model, rule="correct"):
    notes = model.get("notes", [])
    events = []
    for index, note in enumerate(notes):
        events.append({
            "orig": index,
            "staff": note.get("staff", 0),
            "x": F(note["x"]),
            "y": F(note["y"]),
            "dur": effective_duration(F(note["value"]), note.get("dot"), note.get("tuplet")),
            "acc": note.get("acc"),
            "tie": note.get("tie_to") is not None,
        })
    events.sort(key=lambda e: (e["staff"], e["x"]))
    position = {event["orig"]: idx for idx, event in enumerate(events)}
    pairs = {}
    for index, note in enumerate(notes):
        if note.get("tie_to") is not None:
            pairs[position[index]] = position[note["tie_to"]]
    clefs = {}
    for clef in model.get("clefs", [{"x": 0, "glyph": "gClef", "y": 6}]):
        clefs.setdefault(int(clef.get("staff", 0)), []).append(clef)
    for clef_list in clefs.values():
        clef_list.sort(key=lambda c: F(c["x"]))
    measure_ends = [F(x) for x in model.get("measure_ends", [])]
    return _canonical(events, clefs, model.get("keys", [{"x": 0, "fifths": 0}]),
                      measure_ends, model.get("mode", "major"), rule=rule,
                      tie_pairs=pairs, auto_tie=False)


# ---------------------------------------------------------------------------
# Parsing the SVG back into canonical notation
# ---------------------------------------------------------------------------

def _glyphs_from_svg(svg_text):
    root = ET.fromstring(svg_text)
    glyphs = []
    for node in root.iter():
        tag = node.tag.split("}")[-1]
        if tag != "g":
            continue
        attrs = node.attrib
        if "data-glyph" not in attrs:
            continue
        glyphs.append({
            "glyph": attrs["data-glyph"],
            "staff": int(attrs.get("data-staff", "0")),
            "x": F(attrs["data-x"]),
            "y": F(attrs["data-y"]),
        })
    return glyphs


def _near(glyph, staff, x, radius=Fraction(1)):
    return glyph["staff"] == staff and abs(glyph["x"] - x) <= radius


def _fifths_of_group(glyphs):
    sharps = sum(1 for g in glyphs if g["glyph"] == "keySharp")
    flats = sum(1 for g in glyphs if g["glyph"] == "keyFlat")
    naturals = sum(1 for g in glyphs if g["glyph"] == "keyNatural")
    if sharps:
        return sharps
    if flats:
        return -flats
    if naturals:
        return 0
    return 0


def parse_files(meta_text, svg_text):
    """Independent reader: recover canonical notation from the two files."""
    meta = json.loads(meta_text)
    spb = F(meta.get("spaces_per_beat", SPB))
    mode = meta.get("mode", "major")
    glyphs = _glyphs_from_svg(svg_text)

    barline_xs = sorted({g["x"] for g in glyphs if g["glyph"] in ("barlineSingle", "barlineFinal")})
    measure_ends = barline_xs

    clefs = {}
    for g in glyphs:
        if g["glyph"] in CLEF_ANCHOR:
            clefs.setdefault(g["staff"], []).append({"x": g["x"], "glyph": g["glyph"], "y": g["y"]})
    for clef_list in clefs.values():
        clef_list.sort(key=lambda c: c["x"])

    # key signature groups, bucketed by measure
    key_buckets = {}
    for g in glyphs:
        if g["glyph"] in KEY_GLYPHS:
            m = _measure_of(g["x"], measure_ends)
            key_buckets.setdefault(m, []).append(g)
    key_changes = []
    for m in sorted(key_buckets):
        start = Fraction(0) if m == 1 else measure_ends[m - 2]
        key_changes.append({"x": start, "fifths": _fifths_of_group(key_buckets[m])})
    if not key_changes:
        key_changes = [{"x": 0, "fifths": 0}]

    noteheads = [g for g in glyphs if g["glyph"] in NOTEHEAD_GLYPHS]
    noteheads.sort(key=lambda g: (g["staff"], g["x"]))

    events = []
    for head in noteheads:
        staff, x, y = head["staff"], head["x"], head["y"]
        glyph = head["glyph"]
        if glyph == "noteheadWhole":
            value = Fraction(4)
        elif glyph == "noteheadHalf":
            value = Fraction(2)
        else:
            value = Fraction(1)

        flags = [g for g in glyphs if g["glyph"].startswith("flag") and _near(g, staff, x)]
        if glyph == "noteheadBlack" and flags:
            shortest = None
            for g in flags:
                for name, val in FLAG_VALUE.items():
                    if g["glyph"].startswith(name):
                        if shortest is None or val < shortest:
                            shortest = val
            if shortest is not None:
                value = shortest

        dot = any(g["glyph"] == "augmentationDot" and _near(g, staff, x) for g in glyphs)
        tuplet = any(g["glyph"] == "tuplet3" and _near(g, staff, x) for g in glyphs)
        dur = effective_duration(value, dot, tuplet)

        acc = None
        for g in glyphs:
            if g["glyph"] in GLYPH_ACCIDENTAL and _near(g, staff, x):
                acc = GLYPH_ACCIDENTAL[g["glyph"]]
                break
        tie = any(g["glyph"] == "tie" and _near(g, staff, x) for g in glyphs)

        events.append({
            "staff": staff, "x": x, "y": y, "dur": dur,
            "acc": acc, "tie": tie,
        })

    return _canonical(events, clefs, key_changes, measure_ends, mode,
                      rule="correct", tie_pairs=None, auto_tie=True)


def parse_dir(path):
    import os
    with open(os.path.join(path, "score.meta.json"), "r", encoding="utf-8") as handle:
        meta_text = handle.read()
    with open(os.path.join(path, "score.svg"), "r", encoding="utf-8") as handle:
        svg_text = handle.read()
    return parse_files(meta_text, svg_text)


# ---------------------------------------------------------------------------
# Fingerprints, titles and pairs
# ---------------------------------------------------------------------------

def normalise_title(title):
    text = "".join(ch.lower() if ch.isalnum() else " " for ch in str(title))
    return " ".join(text.split())


def block_key(title):
    return normalise_title(title).replace(" ", "")[:4]


def incipit_fingerprint(notation, mode):
    notes = notation.get("notes", [])[:6]
    regions = notation.get("key_regions") or [{"fifths": 0, "mode": mode}]
    tonic = tonic_pc(regions[0]["fifths"], regions[0].get("mode", mode))
    parts = []
    for note in notes:
        offset = (int(note["midi"]) - tonic) % 12
        parts.append("%s:%s:%d" % (note["onset"], note["duration"], offset))
    return hashlib.sha256(("|".join(parts)).encode("utf-8")).hexdigest()


def work_rows(notation, meta):
    regions = notation.get("key_regions") or [{"fifths": 0, "mode": "major"}]
    return {
        "work_id": meta.get("work_id", ""),
        "title": meta.get("title", ""),
        "composer": meta.get("composer", ""),
        "fifths": int(regions[0]["fifths"]),
        "mode": regions[0].get("mode", meta.get("mode", "major")),
        "incipit": incipit_fingerprint(notation, meta.get("mode", "major")),
        "note_count": len(notation.get("notes", [])),
    }


def pairs_from_rows(references, submissions):
    """references/submissions: {work_id: row}; returns sorted [ref, sub] pairs."""
    ref_blocks = {}
    for work_id, row in references.items():
        ref_blocks.setdefault(block_key(row["title"]), []).append(work_id)
    sub_blocks = {}
    for work_id, row in submissions.items():
        sub_blocks.setdefault(block_key(row["title"]), []).append(work_id)
    pairs = []
    for key in sorted(set(ref_blocks) & set(sub_blocks)):
        for ref_id in sorted(ref_blocks[key]):
            for sub_id in sorted(sub_blocks[key]):
                if references[ref_id]["incipit"] == submissions[sub_id]["incipit"]:
                    pairs.append([ref_id, sub_id])
    pairs.sort()
    return pairs


# ---------------------------------------------------------------------------
# Feed
# ---------------------------------------------------------------------------

def feed_expectations(pages, cutoff):
    """Return expected counts and the distinct rows that must be ingested."""
    seen = []
    seen_ids = set()
    duplicates = 0
    for page in pages:
        for record in page["records"]:
            if record["item_id"] in seen_ids:
                duplicates += 1
            seen_ids.add(record["item_id"])
            seen.append(record)
    under = {}
    after = set()
    for record in seen:
        if record["submitted_at"] <= cutoff:
            under.setdefault(record["item_id"], record)
        else:
            after.add(record["item_id"])
    counts = {
        "records_seen": len(seen),
        "ingested": len(under),
        "skipped_after_cutoff": len(after),
        "duplicates_skipped": duplicates,
    }
    return counts, under, len(after)


# ---------------------------------------------------------------------------
# Generator: higher level score model
# ---------------------------------------------------------------------------

TITLES = [
    "Aurora Suite", "Bellwether March", "Cinder Waltz", "Dapplewood Hymn",
    "Emberlight Prelude", "Foxglove Rondo", "Glass Harbor Air", "Hollow Vale Ballad",
]
COMPOSERS = [
    "M. Alder", "R. Tamsin", "O. Peverell", "S. Quillon", "L. Marchetti",
]


def _clef_at_x(clefs, x):
    chosen = clefs[0]
    for clef in clefs:
        if F(clef["x"]) <= x:
            chosen = clef
    return chosen


def _y_for(diatonic, clef):
    return int(F(clef["y"]) - (int(diatonic) - CLEF_ANCHOR[clef["glyph"]]))


def _diatonic_from_y(y, clef):
    return CLEF_ANCHOR[clef["glyph"]] + int(F(clef["y"]) - F(y))


def _pattern(length, rng):
    """One rhythm pattern (a list of notated values) filling ``length`` beats."""
    length = F(length)
    h = Fraction(1, 2)
    dd = Fraction(3, 2)
    table = {
        Fraction(4): [
            [1, 1, 1, 1], [2, 1, 1], [1, 1, 2], [dd, dd, 1],
            [1, dd, dd], [h, h, h, h, 1, 1], [h, 1, h, 1, 1],
        ],
        Fraction(3): [
            [1, 1, 1], [dd, dd], [h, h, h, h, h, h],
            [2, 1], [1, 2],
        ],
        Fraction(2): [[1, 1], [2], [h, h, h, h], [dd, h]],
        Fraction(9, 2): [
            [h] * 9, [dd, dd, dd], [1, 1, 1, 1, h],
            [1, 1, 1, h, h, h],
        ],
    }
    options = table.get(length)
    if options:
        return list(rng.choice(options))
    return [1] * int(length)


def _piece(effective):
    effective = F(effective)
    table = {
        Fraction(4): (4, False),
        Fraction(3): (2, True),
        Fraction(2): (2, False),
        Fraction(3, 2): (1, True),
        Fraction(1): (1, False),
        Fraction(3, 4): (Fraction(1, 2), True),
        Fraction(1, 2): (Fraction(1, 2), False),
        Fraction(3, 8): (Fraction(1, 4), True),
        Fraction(1, 4): (Fraction(1, 4), False),
        Fraction(1, 8): (Fraction(1, 8), False),
    }
    return table[effective]


def _rhythm(length, rng, hidden, category):
    """One measure as a list of (value, dotted, triplet) pieces."""
    length = F(length)
    triplet = (hidden and category in (3, 4) and length in (Fraction(3), Fraction(4))
               and rng.random() < 0.7)
    if triplet:
        pieces = [(value, dot, False)
                  for value, dot in (_piece(F(d)) for d in _pattern(length - 1, rng))]
        pieces += [(Fraction(1, 2), False, True)] * 3
        return pieces
    return [(value, dot, False)
            for value, dot in (_piece(F(d)) for d in _pattern(length, rng))]


def generate_score(seed, profile="hidden"):
    """Build a score model.  ``profile`` is 'visible' or 'hidden'."""
    rng = random.Random(seed)
    hidden = profile == "hidden"
    category = seed % 5 if hidden else -1

    mode = "minor" if (hidden and rng.random() < 0.3) else "major"
    if category == 0:
        fifths = rng.choice([1, -1, 2, -2])
    elif hidden:
        fifths = rng.choice([0, 1, 2, -1, -2, 3, -3])
    else:
        fifths = rng.choice([0, 1])

    meters = [(4, 4), (3, 4), (2, 4)]
    if hidden:
        meters += [(6, 8), (9, 8)]
    top, bottom = rng.choice(meters)
    beat_len = Fraction(top * 4, bottom)      # quarter-note beats per measure
    measures = 2 if not hidden else rng.choice([2, 3, 4])

    clefs = [{"x": Fraction(0), "staff": 0, "glyph": "gClef", "y": 6}]
    if hidden and category in (3, 4) and measures >= 2:
        for m in range(1, measures):
            if rng.random() < 0.55:
                glyph = rng.choice(["cClef", "fClef", "gClef"])
                clefs.append({"x": F(m) * beat_len * SPB, "staff": 0,
                              "glyph": glyph, "y": {"cClef": 4, "fClef": 2, "gClef": 6}[glyph]})
        changed = [c for c in clefs if F(c["x"]) > 0]
        if not any(c["glyph"] != "gClef" or F(c["y"]) != 6 for c in changed):
            if changed:
                changed[-1]["glyph"] = "cClef"
                changed[-1]["y"] = 4
            else:
                clefs.append({"x": beat_len * SPB, "staff": 0,
                              "glyph": "cClef", "y": 4})
    clefs.sort(key=lambda c: F(c["x"]))

    measure_ends = [F(m + 1) * beat_len * SPB for m in range(measures)]

    keys = [{"x": Fraction(0), "fifths": fifths}]
    current = fifths
    if hidden and category in (1, 4):
        for m in range(1, measures):
            if rng.random() < 0.75:
                new = rng.choice([f for f in (-3, -2, -1, 0, 1, 2, 3) if f != current])
                keys.append({"x": F(m) * beat_len * SPB, "fifths": new})
                current = new
        if len(keys) == 1 and measures >= 2:
            new = rng.choice([f for f in (-2, -1, 1, 2, 3) if f != current])
            keys.append({"x": beat_len * SPB, "fifths": new})
            current = new

    notes = []
    measure_note_index = []
    last_y = 4
    for m in range(measures):
        start_x = F(m) * beat_len * SPB
        rhythm = _rhythm(beat_len, rng, hidden, category)
        onset = Fraction(0)
        indices = []
        for value, dot, tuplet in rhythm:
            eff = effective_duration(value, dot, tuplet)
            x = start_x + onset * SPB
            clef = _clef_at_x(clefs, x)
            if hidden and category == 3 and rng.random() < 0.12:
                y = rng.choice([-6, -4, 12, 14])
            else:
                step = rng.choice([-2, -1, 0, 0, 1, 2]) if hidden else rng.choice([-1, 0, 1])
                low, high = (-2, 10) if hidden else (1, 7)
                y = max(low, min(high, last_y + step))
            last_y = y
            notes.append({
                "x": x, "y": y, "value": F(value), "dot": bool(dot),
                "tuplet": bool(tuplet), "acc": None, "tie_to": None,
                "measure": m, "staff": 0,
            })
            indices.append(len(notes) - 1)
            onset += eff
        measure_note_index.append(indices)

    # --- force the profile's edge cases -----------------------------------
    if hidden and category in (0, 4):
        _force_accidental_scope(notes, measure_note_index, clefs, keys, measure_ends, rng)
    if hidden and category in (1, 4):
        _force_key_colour(notes, measure_note_index, clefs, keys, measure_ends, rng)
    if hidden and category in (3, 4):
        _force_rarities(notes, measure_note_index, clefs, keys, measure_ends, rng)
    if hidden and category in (2, 4):
        _force_ties(notes, measure_note_index, clefs, rng)

    return {
        "work_id": "score", "title": "", "composer": "", "mode": mode,
        "keys": keys, "clefs": clefs, "measure_ends": measure_ends,
        "timesigs": [{"x": 0, "top": top, "bottom": bottom}],
        "notes": notes,
    }


def _fifths_at(keys, x, measure_ends):
    measure = _measure_of(F(x), measure_ends)
    value = 0
    for key in keys:
        if _measure_of(F(key["x"]), measure_ends) <= measure:
            value = int(key["fifths"])
    return value


def _letter_at(note, clefs):
    clef = _clef_at_x(clefs, F(note["x"]))
    return letter_of(_diatonic_from_y(note["y"], clef))


def _force_accidental_scope(notes, measure_index, clefs, keys, measure_ends, rng):
    """Place one instance of each accidental-scope rule.

    The cases use disjoint noteheads, so no later case can undo an earlier
    guarantee.
    """
    protected = set()

    # (a) an accidental carries to a later notehead in the same measure that
    # carries no glyph of its own.  The value differs from the signature's
    # alteration for that letter, so a reader that scopes an accidental to the
    # single notehead it precedes sounds the later note differently.
    for indices in measure_index:
        # an accidental glyph sits one grid unit left of its notehead, so the
        # carrier cannot be the note at x = 0.
        free = [index for index in indices if notes[index]["x"] >= 1]
        if len(free) < 2:
            continue
        first, later = free[0], free[-1]
        letter = _letter_at(notes[first], clefs)
        fifths = _fifths_at(keys, notes[first]["x"], measure_ends)
        altered = key_alteration(fifths, letter)
        notes[later]["y"] = notes[first]["y"]
        notes[first]["acc"] = rng.choice([value for value in (1, -1)
                                          if value != altered])
        notes[later]["acc"] = None
        protected.update((first, later))
        break

    # (b) the barline clears the accidental: the last notehead of a measure
    # takes an accidental; the first notehead of the next measure sits on the
    # same line and carries no glyph of its own.
    for m in range(len(measure_index) - 1):
        if not measure_index[m] or not measure_index[m + 1]:
            continue
        a = measure_index[m][-1]
        b = measure_index[m + 1][0]
        if a in protected or b in protected:
            continue
        if notes[a]["x"] < 1:
            continue
        letter = _letter_at(notes[a], clefs)
        fifths = _fifths_at(keys, notes[a]["x"], measure_ends)
        altered = key_alteration(fifths, letter)
        notes[b]["y"] = notes[a]["y"]
        notes[a]["acc"] = rng.choice([value for value in (1, -1)
                                      if value != altered])
        notes[b]["acc"] = None
        protected.update((a, b))
        break

    # (c) a natural written on a step the key signature already alters: the
    # absolute reading sounds the natural, the additive reading the altered
    # pitch.
    altered_note = None
    for indices in measure_index:
        if not indices:
            continue
        fifths = _fifths_at(keys, notes[indices[0]]["x"], measure_ends)
        for idx in indices:
            if idx in protected or notes[idx]["x"] < 1:
                continue
            if key_alteration(fifths, _letter_at(notes[idx], clefs)) != 0:
                altered_note = idx
                break
        if altered_note is not None:
            break
    if altered_note is None:
        # no free notehead happened to sit on an altered step; move one there
        for indices in measure_index:
            for idx in indices:
                if idx in protected or notes[idx]["x"] < 1:
                    continue
                fifths = _fifths_at(keys, notes[idx]["x"], measure_ends)
                if fifths == 0:
                    continue
                letters = SHARP_ORDER[:fifths] if fifths > 0 else FLAT_ORDER[:abs(fifths)]
                clef = _clef_at_x(clefs, notes[idx]["x"])
                octave = _diatonic_from_y(notes[idx]["y"], clef) // 7
                moved = False
                for letter in letters:
                    y = _y_for(octave * 7 + letter, clef)
                    if -6 <= y <= 14:
                        notes[idx]["y"] = y
                        moved = True
                        break
                if moved:
                    altered_note = idx
                    break
            if altered_note is not None:
                break
    if altered_note is not None:
        notes[altered_note]["acc"] = 0


def _force_key_colour(notes, measure_index, clefs, keys, measure_ends, rng):
    # make sure a note in a changed region sounds differently under the new
    # signature than under the opening one, so a reader that keeps only the
    # first signature cannot agree by accident.
    opening = int(keys[0]["fifths"]) if keys else 0
    for m in range(1, len(measure_index)):
        if not measure_index[m]:
            continue
        new_fifths = _fifths_at(keys, notes[measure_index[m][0]]["x"], measure_ends)
        if new_fifths == opening:
            continue
        letters = list(range(7))
        letters.sort(key=lambda l: key_alteration(opening, l) == key_alteration(new_fifths, l))
        for idx in measure_index[m]:
            clef = _clef_at_x(clefs, notes[idx]["x"])
            current = _diatonic_from_y(notes[idx]["y"], clef)
            octave = current // 7
            for letter in letters:
                candidate = octave * 7 + letter
                y = _y_for(candidate, clef)
                if -6 <= y <= 14:
                    notes[idx]["y"] = y
                    notes[idx]["acc"] = None
                    return


def _force_ties(notes, measure_index, clefs, rng):
    for m in range(len(measure_index) - 1):
        if not measure_index[m] or not measure_index[m + 1]:
            continue
        a = measure_index[m][-1]
        b = measure_index[m + 1][0]
        ca = _clef_at_x(clefs, notes[a]["x"])
        cb = _clef_at_x(clefs, notes[b]["x"])
        if ca["glyph"] != cb["glyph"] or F(ca["y"]) != F(cb["y"]):
            continue
        notes[b]["y"] = notes[a]["y"]
        notes[a]["tie_to"] = b
        # a chain of three: the middle measure must hold that note alone, so
        # the second tie joins adjacent noteheads exactly as the glyph stream
        # says it does.
        if (len(measure_index[m + 1]) == 1
                and m + 2 < len(measure_index) and measure_index[m + 2]):
            c = measure_index[m + 2][0]
            cc = _clef_at_x(clefs, notes[c]["x"])
            if cc["glyph"] == ca["glyph"] and F(cc["y"]) == F(ca["y"]):
                notes[c]["y"] = notes[a]["y"]
                notes[b]["tie_to"] = c
        return


def _force_rarities(notes, measure_index, clefs, keys, measure_ends, rng):
    # double sharp / double flat
    doubled = len(notes) // 2
    notes[doubled]["acc"] = rng.choice([2, -2])
    # a courtesy natural (never on the note at x = 0: its glyph would fall off
    # the engraving grid; never on the doubled note, so the two rarities stay
    # separate)
    for idx in range(len(notes)):
        if idx == doubled or notes[idx]["x"] < 1:
            continue
        letter = _letter_at(notes[idx], clefs)
        fifths = _fifths_at(keys, notes[idx]["x"], measure_ends)
        if key_alteration(fifths, letter) == 0:
            notes[idx]["acc"] = 0
            break
    # ledger extremes
    notes[0]["y"] = -6
    if len(notes) > 2:
        notes[-1]["y"] = 14


# ---------------------------------------------------------------------------
# Generator: corpora
# ---------------------------------------------------------------------------

def _meta_of(score):
    return {
        "work_id": score.get("work_id", ""),
        "title": score.get("title", ""),
        "composer": score.get("composer", ""),
        "mode": score.get("mode", "major"),
    }


def build_corpus(seed, profile="hidden"):
    """Return a dict with files, expected notation, rows, pairs, counts and feed."""
    rng = random.Random(seed)
    hidden = profile == "hidden"
    files = {}
    notation = {}
    metas = {}
    references = {}
    submissions = {}
    sub_counter = 1
    work_pool = rng.randint(3, 5)

    ref_specs = []
    for w in range(work_pool):
        title = TITLES[(seed + w) % len(TITLES)]
        if w % 2 == 1:
            title = title + " No. %d" % (w + 1)
        score = generate_score((seed * 131 + w * 17 + 1) % 100000, profile)
        ref_id = "ref-%04d" % (w + 1)
        score["work_id"] = ref_id
        score["title"] = title
        score["composer"] = COMPOSERS[(seed + w) % len(COMPOSERS)]
        files.update({"reference/%s/%s" % (ref_id, k): v for k, v in render_model(score).items()})
        truth = model_truth(score)
        notation[ref_id] = truth
        metas[ref_id] = _meta_of(score)
        references[ref_id] = work_rows(truth, _meta_of(score))
        ref_specs.append((score, title))

        n_sub = rng.randint(0, 2)
        for t in range(n_sub):
            sub = copy.deepcopy(score)
            sub_id = "sub-%04d" % sub_counter
            sub_counter += 1
            sub["work_id"] = sub_id
            sub["title"] = title + " (edition)"
            files.update({"submissions/%s/%s" % (sub_id, k): v for k, v in render_model(sub).items()})
            sub_truth = model_truth(sub)
            notation[sub_id] = sub_truth
            metas[sub_id] = _meta_of(sub)
            submissions[sub_id] = work_rows(sub_truth, _meta_of(sub))

        # one decoy sharing the title block but not the incipit
        if hidden or rng.random() < 0.5:
            decoy_seed = (seed * 197 + w * 31 + 9) % 100000
            for attempt in range(12):
                decoy = generate_score((decoy_seed + attempt * 13) % 100000, profile)
                decoy["work_id"] = "sub-%04d" % sub_counter
                decoy["title"] = title
                decoy["composer"] = COMPOSERS[(seed + w + 2) % len(COMPOSERS)]
                decoy_truth = model_truth(decoy)
                if incipit_fingerprint(decoy_truth, decoy["mode"]) != references[ref_id]["incipit"]:
                    break
            sub_id = decoy["work_id"]
            sub_counter += 1
            files.update({"submissions/%s/%s" % (sub_id, k): v for k, v in render_model(decoy).items()})
            notation[sub_id] = decoy_truth
            metas[sub_id] = _meta_of(decoy)
            submissions[sub_id] = work_rows(decoy_truth, _meta_of(decoy))

    # manifests
    files["manifests/reference_manifest.json"] = json.dumps(REFERENCE_MANIFEST, indent=2) + "\n"
    files["manifests/submission_manifest.json"] = json.dumps(SUBMISSION_MANIFEST, indent=2) + "\n"

    # feed
    pages, index, counts = _build_feed(seed)
    files["feed/feed_index.json"] = json.dumps(index, indent=2) + "\n"
    for pageno, page in enumerate(pages, start=1):
        files["feed/page-%04d.json" % pageno] = json.dumps(page, indent=2) + "\n"

    pairs = pairs_from_rows(references, submissions)
    return {
        "files": files,
        "notation": notation,
        "metas": metas,
        "references": references,
        "submissions": submissions,
        "pairs": pairs,
        "counts": counts,
        "feed_index": index,
        "pages": pages,
    }


REFERENCE_MANIFEST = {
    "datastore": "reference.db",
    "tables": [{
        "name": "references",
        "columns": [
            {"name": "work_id", "type": "TEXT", "primary_key": True},
            {"name": "title", "type": "TEXT"},
            {"name": "composer", "type": "TEXT"},
            {"name": "fifths", "type": "INTEGER"},
            {"name": "mode", "type": "TEXT"},
            {"name": "incipit", "type": "TEXT"},
            {"name": "note_count", "type": "INTEGER"},
        ],
    }],
}

SUBMISSION_MANIFEST = {
    "datastore": "submission.db",
    "tables": [
        {
            "name": "submissions",
            "columns": [
                {"name": "work_id", "type": "TEXT", "primary_key": True},
                {"name": "title", "type": "TEXT"},
                {"name": "composer", "type": "TEXT"},
                {"name": "fifths", "type": "INTEGER"},
                {"name": "mode", "type": "TEXT"},
                {"name": "incipit", "type": "TEXT"},
                {"name": "note_count", "type": "INTEGER"},
            ],
        },
        {
            "name": "feed_items",
            "columns": [
                {"name": "item_id", "type": "TEXT", "primary_key": True},
                {"name": "work_id", "type": "TEXT"},
                {"name": "title", "type": "TEXT"},
                {"name": "submitted_at", "type": "TEXT"},
            ],
        },
    ],
}


def _build_feed(seed):
    rng = random.Random(seed * 7919 + 3)
    cutoff = "2026-09-30"
    records = []
    total = rng.randint(8, 13)
    for i in range(total):
        before = rng.random() < 0.68
        month = rng.randint(1, 8) if before else rng.randint(10, 12)
        day = rng.randint(1, 27)
        records.append({
            "item_id": "item-%03d" % (i + 1),
            "work_id": "sub-%04d" % (rng.randint(1, 4)),
            "title": TITLES[(seed + i) % len(TITLES)],
            "submitted_at": "2026-%02d-%02d" % (month, day),
        })
    # pagination overlap: repeat a couple of early records on later pages
    repeats = [copy.deepcopy(records[i]) for i in range(min(2, len(records))) if rng.random() < 0.8]
    for record in repeats:
        records.append(record)
    rng.shuffle(records)
    page_size = max(1, (len(records) + 2) // 3)
    pages = []
    for start in range(0, len(records), page_size):
        pages.append({"records": records[start:start + page_size]})
    counts, under, after = feed_expectations(pages, cutoff)
    index = {
        "cutoff": cutoff,
        "page_count": len(pages),
        "total_records": counts["records_seen"],
        "total_under_cutoff": len(under),
        "total_after_cutoff": after,
    }
    return pages, index, counts


def generate_instance(profile, seed):
    """One bundle plus its expected canonical notation."""
    score = generate_score(seed, profile)
    score["work_id"] = "score-%d" % seed
    score["title"] = "Unseen Score"
    score["composer"] = "Anonymous"
    files = render_model(score)
    return {"files": files, "expected": model_truth(score), "profile": profile}


def generate_visible_kit(seed=1):
    """The two fully worked common-case bundles shipped with the environment."""
    kit = []
    for index in range(2):
        score = generate_score(seed * 4000 + index * 11 + 7, "visible")
        score["work_id"] = "kit-%d" % (index + 1)
        score["title"] = "Worked Example %d" % (index + 1)
        score["composer"] = "CRE Engraver"
        files = render_model(score)
        truth = model_truth(score)
        kit.append({"work_id": score["work_id"], "files": files, "expected": truth})
    return kit


# ---------------------------------------------------------------------------
# Validation, written from the format definition
# ---------------------------------------------------------------------------

def _parse_int(value, name, problems):
    try:
        f = F(value)
    except (ValueError, ZeroDivisionError):
        problems.append("%s is not a number: %r" % (name, value))
        return None
    if f.denominator != 1:
        problems.append("%s is not an integer: %r" % (name, value))
        return None
    return int(f)


def validate_instance(instance):
    """Return a list of format violations; empty means valid."""
    problems = []
    files = instance.get("files", {})
    if "score.meta.json" not in files or "score.svg" not in files:
        return ["bundle is missing score.meta.json or score.svg"]

    try:
        meta = json.loads(files["score.meta.json"])
    except Exception as exc:  # noqa: BLE001
        return ["meta is not JSON: %s" % exc]
    for key in ("format", "spaces_per_beat", "mode", "staves"):
        if key not in meta:
            problems.append("meta is missing %s" % key)
    if meta.get("mode") not in ("major", "minor"):
        problems.append("mode must be major or minor")
    spb = meta.get("spaces_per_beat")
    if not isinstance(spb, int) or spb <= 0:
        problems.append("spaces_per_beat must be a positive integer")
        spb = SPB

    try:
        glyphs = _glyphs_from_svg(files["score.svg"])
    except Exception as exc:  # noqa: BLE001
        return problems + ["svg is not well formed: %s" % exc]
    if not glyphs:
        problems.append("svg has no glyphs")

    seen = set()
    for glyph in glyphs:
        if glyph["glyph"] not in GLYPH_NAMES:
            problems.append("unknown glyph %r" % glyph["glyph"])
        if glyph["staff"] != 0:
            problems.append("unexpected staff %r" % glyph["staff"])
        if glyph["x"] < 0:
            problems.append("negative x for %s" % glyph["glyph"])
        key = (glyph["glyph"], glyph["staff"], glyph["x"], glyph["y"])
        if key in seen:
            problems.append("overlapping glyphs at %r" % (key,))
        seen.add(key)

    noteheads = sorted((g for g in glyphs if g["glyph"] in NOTEHEAD_GLYPHS),
                       key=lambda g: (g["staff"], g["x"]))
    seen_head = set()
    for head in noteheads:
        slot = (head["staff"], head["x"])
        if slot in seen_head:
            problems.append("two noteheads share a slot at %r" % (slot,))
        seen_head.add(slot)
        if head["y"] < -6 or head["y"] > 14:
            problems.append("notehead y out of range at %r" % (head["y"],))
        if len([g for g in glyphs if g["glyph"] in GLYPH_ACCIDENTAL
                and _near(g, head["staff"], head["x"])]) > 1:
            problems.append("two accidentals attach to one notehead")
        if len([g for g in glyphs if g["glyph"].startswith("flag")
                and _near(g, head["staff"], head["x"])]) > 1:
            problems.append("two flags attach to one notehead")

    barlines = sorted({g["x"] for g in glyphs if g["glyph"] in ("barlineSingle", "barlineFinal")})
    if not barlines:
        problems.append("no barlines")
    else:
        if barlines[0] <= 0:
            problems.append("first barline must come after x=0")
        for left, right in zip(barlines, barlines[1:]):
            if right <= left:
                problems.append("barlines are not strictly increasing")
        for head in noteheads:
            if head["x"] >= barlines[-1]:
                problems.append("notehead outside the final barline")

    for key_glyph in (g for g in glyphs if g["glyph"] in KEY_GLYPHS):
        if key_glyph["x"] < 0:
            problems.append("negative key-signature x")

    expected = instance.get("expected")
    if expected is not None:
        notes = expected.get("notes", [])
        if not notes:
            problems.append("expected notation has no notes")
        order = []
        for note in notes:
            try:
                onset = F(note["onset"])
                duration = F(note["duration"])
            except Exception:  # noqa: BLE001
                problems.append("note onset/duration are not rationals")
                continue
            if onset < 0:
                problems.append("negative onset")
            if duration <= 0:
                problems.append("non-positive duration")
            if not isinstance(note.get("midi"), int) or not (0 <= note["midi"] <= 127):
                problems.append("midi out of range")
            order.append((note.get("staff", 0), onset, note.get("midi", 0)))
            if barlines and onset + duration > barlines[-1] / F(spb) + Fraction(1, 1000):
                problems.append("note runs past the final barline")
        if order != sorted(order):
            problems.append("expected notes are not in canonical order")
        regions = expected.get("key_regions", [])
        if not regions:
            problems.append("expected key_regions is empty")
        last = 0
        for region in regions:
            if region.get("start_measure", 0) <= last:
                problems.append("key regions are not strictly ordered")
            last = region.get("start_measure", 0)
            if not (-7 <= int(region.get("fifths", 0)) <= 7):
                problems.append("fifths out of range")
            if region.get("mode") not in ("major", "minor"):
                problems.append("key region mode is invalid")
        if regions and regions[0].get("start_measure") != 1:
            problems.append("first key region must start at measure 1")
    return problems


# ---------------------------------------------------------------------------
# Catalog expectations (used by the verifier)
# ---------------------------------------------------------------------------

def catalog_from_bundle_texts(bundles):
    """bundles: list of (kind, work_id, meta_text, svg_text)."""
    notation = {}
    metas = {}
    references = {}
    submissions = {}
    for kind, work_id, meta_text, svg_text in bundles:
        truth = parse_files(meta_text, svg_text)
        notation[work_id] = truth
        meta = json.loads(meta_text)
        metas[work_id] = meta
        row = work_rows(truth, meta)
        if kind == "reference":
            references[work_id] = row
        else:
            submissions[work_id] = row
    return {
        "notation": notation,
        "references": references,
        "submissions": submissions,
        "pairs": pairs_from_rows(references, submissions),
    }