#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"

# ---------------------------------------------------------------------------
# 1. The notation reader
# ---------------------------------------------------------------------------
cat > ${W}/read_score.py <<'PYEOF'
"""Read one CRE engraver SVG bundle and print canonical notation JSON.

MusicXML 4.0 / SMuFL semantics: accidental scope is absolute and measure
scoped, key signatures open regions at measure boundaries, ties collapse to
one sounded note with the first notehead's onset and pitch.
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
from bisect import bisect_right
from fractions import Fraction

PC = (0, 2, 4, 5, 7, 9, 11)
SHARP_ORDER = (3, 0, 4, 1, 5, 2, 6)
FLAT_ORDER = (6, 2, 5, 1, 4, 0, 3)
CLEF_ANCHOR = {"gClef": 32, "fClef": 24, "cClef": 28}
ACCIDENTAL = {"accidentalDoubleFlat": -2, "accidentalFlat": -1,
              "accidentalNatural": 0, "accidentalSharp": 1,
              "accidentalDoubleSharp": 2}
FLAG = {"flag8th": Fraction(1, 2), "flag16th": Fraction(1, 4),
        "flag32nd": Fraction(1, 8)}
NOTEHEAD = {"noteheadWhole": Fraction(4), "noteheadHalf": Fraction(2),
            "noteheadBlack": Fraction(1)}
KEY_GLYPHS = {"keySharp", "keyFlat", "keyNatural"}


def F(value):
    return value if isinstance(value, Fraction) else Fraction(value)


def fs(value):
    f = F(value)
    return str(f.numerator) if f.denominator == 1 else "%d/%d" % (f.numerator, f.denominator)


def natural_midi(d):
    octave, letter = divmod(int(d), 7)
    return 12 * (octave + 1) + PC[letter]


def key_alt(fifths, letter):
    if fifths > 0:
        return 1 if letter in SHARP_ORDER[:fifths] else 0
    if fifths < 0:
        return -1 if letter in FLAT_ORDER[:-fifths] else 0
    return 0


def parse_files(meta_text, svg_text):
    meta = json.loads(meta_text)
    spb = F(meta.get("spaces_per_beat", 12))
    mode = meta.get("mode", "major")

    root = ET.fromstring(svg_text)
    glyphs = []
    for node in root.iter():
        if node.tag.split("}")[-1] != "g":
            continue
        attrs = node.attrib
        if "data-glyph" not in attrs:
            continue
        glyphs.append((attrs["data-glyph"], int(attrs.get("data-staff", "0")),
                       F(attrs["data-x"]), F(attrs["data-y"])))

    ends = sorted({x for glyph, staff, x, y in glyphs
                   if glyph in ("barlineSingle", "barlineFinal")})

    def measure_of(x):
        return bisect_right(ends, x) + 1

    clefs = {}
    for glyph, staff, x, y in glyphs:
        if glyph in CLEF_ANCHOR:
            clefs.setdefault(staff, []).append({"x": x, "glyph": glyph, "y": y})
    for clef_list in clefs.values():
        clef_list.sort(key=lambda c: c["x"])

    buckets = {}
    for glyph, staff, x, y in glyphs:
        if glyph in KEY_GLYPHS:
            buckets.setdefault(measure_of(x), []).append(glyph)
    key_changes = []
    for m in sorted(buckets):
        start = Fraction(0) if m == 1 else ends[m - 2]
        sharps = buckets[m].count("keySharp")
        flats = buckets[m].count("keyFlat")
        fifths = sharps if sharps else (-flats if flats else 0)
        key_changes.append((start, fifths))
    if not key_changes:
        key_changes = [(Fraction(0), 0)]

    # key regions
    by_measure = {}
    for start, fifths in key_changes:
        by_measure[measure_of(start)] = fifths
    regions = []
    for m in range(1, len(ends) + 1):
        if m in by_measure:
            regions.append({"start_measure": m, "fifths": by_measure[m], "mode": mode})
        elif m == 1:
            regions.append({"start_measure": 1, "fifths": 0, "mode": mode})
    if not regions:
        regions = [{"start_measure": 1, "fifths": 0, "mode": mode}]

    def fifths_at(measure):
        value = regions[0]["fifths"]
        for region in regions:
            if region["start_measure"] <= measure:
                value = region["fifths"]
        return value

    def clef_at(staff, x):
        chosen = None
        for clef in clefs.get(staff, []):
            if clef["x"] <= x:
                chosen = clef
        if chosen is None:
            chosen = {"x": Fraction(0), "glyph": "gClef", "y": 6}
        return chosen

    def near(glyph, staff, x, radius=Fraction(1)):
        return glyph[1] == staff and abs(glyph[2] - x) <= radius

    heads = sorted((g for g in glyphs if g[0] in NOTEHEAD),
                   key=lambda g: (g[1], g[2]))

    events = []
    for head in heads:
        glyph, staff, x, y = head
        value = NOTEHEAD[glyph]
        flags = [g for g in glyphs if g[0].startswith("flag") and near(g, staff, x)]
        shortest = None
        for flag in flags:
            for name, val in FLAG.items():
                if flag[0].startswith(name) and (shortest is None or val < shortest):
                    shortest = val
        if glyph == "noteheadBlack" and shortest is not None:
            value = shortest
        dot = any(g[0] == "augmentationDot" and near(g, staff, x) for g in glyphs)
        tuplet = any(g[0] == "tuplet3" and near(g, staff, x) for g in glyphs)
        dur = value
        if dot:
            dur *= Fraction(3, 2)
        if tuplet:
            dur *= Fraction(2, 3)
        acc = None
        for g in glyphs:
            if g[0] in ACCIDENTAL and near(g, staff, x):
                acc = ACCIDENTAL[g[0]]
                break
        tie = any(g[0] == "tie" and near(g, staff, x) for g in glyphs)
        events.append({"staff": staff, "x": x, "y": y, "dur": dur,
                       "acc": acc, "tie": tie})

    events.sort(key=lambda e: (e["staff"], e["x"]))
    raw = []
    state = {}
    current = {}
    for event in events:
        staff = event["staff"]
        x = event["x"]
        measure = measure_of(x)
        fifths = fifths_at(measure)
        clef = clef_at(staff, x)
        diatonic = CLEF_ANCHOR[clef["glyph"]] + int(clef["y"] - event["y"])
        letter = int(diatonic) % 7
        if current.get(staff) != measure:
            state[staff] = {}
            current[staff] = measure
        stored = state[staff].get((letter, diatonic // 7))
        if event["acc"] is not None:
            stored = int(event["acc"])
            state[staff][(letter, diatonic // 7)] = stored
        alteration = key_alt(fifths, letter) if stored is None else stored
        raw.append({"staff": staff, "onset": x / spb, "dur": event["dur"],
                    "midi": natural_midi(diatonic) + alteration, "y": event["y"],
                    "tie": event["tie"]})

    # A tie joins a notehead to the notehead that begins where it ends.
    lookup = {}
    for index, note in enumerate(raw):
        lookup.setdefault((note["staff"], note["y"], note["onset"]), index)
    pairs = {}
    for index, note in enumerate(raw):
        if note["tie"]:
            target = lookup.get((note["staff"], note["y"], note["onset"] + note["dur"]))
            if target is not None and target != index:
                pairs[index] = target

    targets = set(pairs.values())
    merged = []
    group_id = 1
    for index, note in enumerate(raw):
        if index in targets:
            continue
        chain = [index]
        cursor = index
        while cursor in pairs:
            cursor = pairs[cursor]
            if cursor in chain:
                break
            chain.append(cursor)
        onset = raw[chain[0]]["onset"]
        duration = sum((raw[i]["dur"] for i in chain), Fraction(0))
        group = None
        if len(chain) > 1:
            group = group_id
            group_id += 1
        merged.append({"staff": raw[chain[0]]["staff"], "voice": 0,
                       "onset": fs(onset), "duration": fs(duration),
                       "midi": raw[chain[0]]["midi"], "tie_group": group})

    merged.sort(key=lambda n: (n["staff"], F(n["onset"]), n["midi"]))
    return {"notes": merged, "key_regions": regions}


def parse_dir(path):
    with open(os.path.join(path, "score.meta.json"), "r", encoding="utf-8") as handle:
        meta_text = handle.read()
    with open(os.path.join(path, "score.svg"), "r", encoding="utf-8") as handle:
        svg_text = handle.read()
    return parse_files(meta_text, svg_text)


def main():
    if len(sys.argv) != 2:
        print("usage: read_score.py <bundle_dir>", file=sys.stderr)
        return 2
    print(json.dumps(parse_dir(sys.argv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

# ---------------------------------------------------------------------------
# 2. The catalogue pipeline
# ---------------------------------------------------------------------------
cat > ${W}/build_catalog.py <<'PYEOF'
"""Build the CRE catalogue: notation, datastores, feed ingest, pairs, counts."""

import glob
import hashlib
import json
import os
import sqlite3
import sys

import read_score


def normalise_title(title):
    text = "".join(ch.lower() if ch.isalnum() else " " for ch in str(title))
    return " ".join(text.split())


def block_key(title):
    return normalise_title(title).replace(" ", "")[:4]


def fingerprint(notation):
    notes = notation["notes"][:6]
    region = notation["key_regions"][0]
    tonic = (int(region["fifths"]) * 7) % 12
    if region.get("mode") == "minor":
        tonic = (tonic + 9) % 12
    parts = ["%s:%s:%d" % (note["onset"], note["duration"],
                           (int(note["midi"]) - tonic) % 12) for note in notes]
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()


def load_bundles(root):
    bundles = {}
    for folder in ("reference", "submissions"):
        base = os.path.join(root, folder)
        if not os.path.isdir(base):
            continue
        for work_id in sorted(os.listdir(base)):
            directory = os.path.join(base, work_id)
            if not os.path.isdir(directory):
                continue
            with open(os.path.join(directory, "score.meta.json"), "r", encoding="utf-8") as handle:
                meta = json.load(handle)
            notation = read_score.parse_dir(directory)
            region = notation["key_regions"][0]
            row = {
                "work_id": meta.get("work_id", work_id),
                "title": meta.get("title", ""),
                "composer": meta.get("composer", ""),
                "fifths": int(region["fifths"]),
                "mode": region.get("mode", "major"),
                "incipit": fingerprint(notation),
                "note_count": len(notation["notes"]),
            }
            bundles[row["work_id"]] = {"kind": folder, "meta": meta,
                                       "notation": notation, "row": row}
    return bundles


def read_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def ingest_feed(root):
    index = read_json(os.path.join(root, "feed", "feed_index.json"))
    cutoff = index["cutoff"]
    records_seen = 0
    seen = set()
    duplicates = 0
    under = {}
    after = set()
    for path in sorted(glob.glob(os.path.join(root, "feed", "page-*.json"))):
        page = read_json(path)
        for record in page.get("records", []):
            records_seen += 1
            item_id = record["item_id"]
            if item_id in seen:
                duplicates += 1
            seen.add(item_id)
            if record["submitted_at"] <= cutoff:
                under.setdefault(item_id, record)
            else:
                after.add(item_id)
    counts = {
        "records_seen": records_seen,
        "ingested": len(under),
        "skipped_after_cutoff": len(after),
        "duplicates_skipped": duplicates,
    }
    return counts, list(under.values())


def create_datastore(path, manifest, rows_by_table):
    if os.path.exists(path):
        os.remove(path)
    connection = sqlite3.connect(path)
    try:
        for table in manifest["tables"]:
            columns = []
            names = []
            for column in table["columns"]:
                definition = '"%s" %s' % (column["name"], column["type"])
                if column.get("primary_key"):
                    definition += " PRIMARY KEY"
                columns.append(definition)
                names.append(column["name"])
            connection.execute('CREATE TABLE "%s" (%s)' % (table["name"], ", ".join(columns)))
            for row in rows_by_table.get(table["name"], []):
                placeholders = ", ".join("?" for _ in names)
                connection.execute(
                    'INSERT INTO "%s" (%s) VALUES (%s)'
                    % (table["name"], ", ".join('"%s"' % n for n in names), placeholders),
                    [row.get(name) for name in names])
        connection.commit()
    finally:
        connection.close()


def build_datastores(root, out_dir, bundles, ingest=True):
    manifests = {
        "reference": read_json(os.path.join(root, "manifests", "reference_manifest.json")),
        "submission": read_json(os.path.join(root, "manifests", "submission_manifest.json")),
    }
    reference_rows = [b["row"] for b in bundles.values() if b["kind"] == "reference"]
    submission_rows = [b["row"] for b in bundles.values() if b["kind"] == "submissions"]
    feed_rows = []
    if ingest:
        _, feed_rows = ingest_feed(root)
    for kind, manifest in manifests.items():
        path = os.path.join(out_dir, manifest["datastore"])
        table_rows = {}
        for table in manifest["tables"]:
            name = table["name"]
            if name == "references":
                table_rows[name] = reference_rows
            elif name == "submissions":
                table_rows[name] = submission_rows
            elif name == "feed_items":
                table_rows[name] = feed_rows
            else:
                table_rows[name] = []
        create_datastore(path, manifest, table_rows)


def compute_pairs(bundles):
    references = {wid: b for wid, b in bundles.items() if b["kind"] == "reference"}
    submissions = {wid: b for wid, b in bundles.items() if b["kind"] == "submissions"}
    pairs = []
    for ref_id in sorted(references):
        ref = references[ref_id]["row"]
        for sub_id in sorted(submissions):
            sub = submissions[sub_id]["row"]
            if block_key(ref["title"]) != block_key(sub["title"]):
                continue
            if ref["incipit"] == sub["incipit"]:
                pairs.append([ref_id, sub_id])
    pairs.sort()
    return pairs


def reset(root):
    out_dir = os.path.join(root, "out")
    os.makedirs(out_dir, exist_ok=True)
    bundles = load_bundles(root)
    build_datastores(root, out_dir, bundles, ingest=False)


def build(root):
    out_dir = os.path.join(root, "out")
    os.makedirs(os.path.join(out_dir, "notation"), exist_ok=True)
    bundles = load_bundles(root)
    for work_id, bundle in bundles.items():
        with open(os.path.join(out_dir, "notation", work_id + ".json"), "w",
                  encoding="utf-8") as handle:
            json.dump(bundle["notation"], handle, indent=2)
    build_datastores(root, out_dir, bundles, ingest=True)
    pairs = compute_pairs(bundles)
    with open(os.path.join(out_dir, "pairs.jsonl"), "w", encoding="utf-8") as handle:
        for ref_id, sub_id in pairs:
            handle.write(json.dumps({"reference": ref_id, "submission": sub_id}) + "\n")
    counts, _ = ingest_feed(root)
    with open(os.path.join(out_dir, "counts.json"), "w", encoding="utf-8") as handle:
        json.dump(counts, handle, indent=2)


def main():
    arguments = sys.argv[1:]
    if arguments and arguments[0] == "--reset":
        if len(arguments) != 2:
            print("usage: build_catalog.py --reset <corpus_root>", file=sys.stderr)
            return 2
        reset(arguments[1])
        return 0
    if len(arguments) != 1:
        print("usage: build_catalog.py <corpus_root>", file=sys.stderr)
        return 2
    build(arguments[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

# ---------------------------------------------------------------------------
# 3. Produce the visible output
# ---------------------------------------------------------------------------
rm -rf ${W}/corpus/out ${W}/out
python3 ${W}/build_catalog.py ${W}/corpus
cp -r ${W}/corpus/out ${W}/out

# ---------------------------------------------------------------------------
# 4. Scrub and publish the partner artifacts
# ---------------------------------------------------------------------------
rm -rf ${W}/publish
mkdir -p ${W}/publish/toolkit
cp ${W}/partner_toolkit_src/toolkit/__init__.py ${W}/publish/toolkit/
cp ${W}/partner_toolkit_src/toolkit/titles.py ${W}/publish/toolkit/
cp ${W}/partner_toolkit_src/toolkit/selftest.py ${W}/publish/toolkit/

python3 - <<PYEOF
import json

with open("${W}/data_bundle_src.json", "r", encoding="utf-8") as handle:
    source = json.load(handle)
titles = []
for entry in source.get("titles", []):
    if entry.get("embargoed"):
        continue
    titles.append({"work_id": entry["work_id"], "title": entry["title"],
                   "publisher": entry["publisher"]})
bundle = {"bundle_version": int(source.get("bundle_version", 1)), "titles": titles}
with open("${W}/publish/data_bundle.json", "w", encoding="utf-8") as handle:
    json.dump(bundle, handle, indent=2)
    handle.write("\n")
PYEOF

cd ${W}/publish && python3 -m toolkit.selftest
