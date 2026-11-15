#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"

# ---------------------------------------------------------------------------
# A reader calibrated on the two worked examples.  It is right on everything
# the visible bundle exercises and wrong on every hidden edge case: it applies
# an accidental only to the notehead that carries the glyph (and adds it to the
# key alteration), keeps only the first key signature and the first clef, and
# re-strikes every tied notehead.
# ---------------------------------------------------------------------------
cat > ${W}/read_score.py <<'PYEOF'
"""Naive common-case reader (deliberately wrong on the hidden edge cases)."""

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

    # only the signature printed before the first barline
    opening = [g for g in glyphs if g[0] in KEY_GLYPHS
               and (not ends or g[2] < ends[0])]
    sharps = sum(1 for g in opening if g[0] == "keySharp")
    flats = sum(1 for g in opening if g[0] == "keyFlat")
    fifths = sharps if sharps else (-flats if flats else 0)

    # only the opening clef
    clef = {"glyph": "gClef", "y": F(6)}
    for g in glyphs:
        if g[0] in CLEF_ANCHOR:
            clef = {"glyph": g[0], "y": g[3]}
            break

    def near(g, staff, x, radius=Fraction(1)):
        return g[1] == staff and abs(g[2] - x) <= radius

    heads = sorted((g for g in glyphs if g[0] in NOTEHEAD),
                   key=lambda g: (g[1], g[2]))
    notes = []
    for glyph, staff, x, y in heads:
        value = NOTEHEAD[glyph]
        shortest = None
        for flag in glyphs:
            if not (flag[0].startswith("flag") and near(flag, staff, x)):
                continue
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

        diatonic = CLEF_ANCHOR[clef["glyph"]] + int(clef["y"] - y)
        letter = int(diatonic) % 7
        alteration = key_alt(fifths, letter)
        if acc is not None:
            alteration = max(-1, min(1, alteration + int(acc)))
        notes.append({
            "staff": staff, "voice": 0,
            "onset": fs(x / spb), "duration": fs(dur),
            "midi": natural_midi(diatonic) + alteration,
            "tie_group": None,
        })

    notes.sort(key=lambda n: (n["staff"], F(n["onset"]), n["midi"]))
    return {"notes": notes,
            "key_regions": [{"start_measure": 1, "fifths": fifths, "mode": mode}]}


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
# The catalogue pipeline (same shape as the reference, wrong reader beneath it)
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

rm -rf ${W}/corpus/out ${W}/out
python3 ${W}/build_catalog.py ${W}/corpus
cp -r ${W}/corpus/out ${W}/out

# ---------------------------------------------------------------------------
# Publishing (the reference scrub, independent of the reader)
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
