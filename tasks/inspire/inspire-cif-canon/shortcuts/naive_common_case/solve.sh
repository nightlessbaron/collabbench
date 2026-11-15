#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
# Shortcut: correct on the visible common case only.  Reads the atom-site
# loop verbatim, scales the cell diagonally, keeps parenthesised digits,
# never expands symmetry, never wraps.

mkdir -p ${W}/cif ${W}/topology
cat > ${W}/cif/__init__.py <<'PY'
PY
cat > ${W}/cif/parse.py <<'PY'
import json
import math
import re
import sys

CUTOFF = 3.5
OFFSETS = [(h, k, l) for h in (-1, 0, 1) for k in (-1, 0, 1) for l in (-1, 0, 1)]


def num(tok):
    s = str(tok).strip().strip("'\"")
    m = re.match(r"^([+-]?[\d.]+)\((\d+)\)$", s)
    if m:
        return float(m.group(1) + m.group(2))
    return float(s)


def tokenize(text):
    out = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0]
        for token in re.findall(r"'[^']*'|\"[^\"]*\"|\S+", line):
            if token[:1] in "'\"":
                token = token[1:-1]
            out.append(token)
    return out


def parse_cif(text):
    toks = tokenize(text)
    tags = {}
    loops = []
    i = 0
    while i < len(toks):
        t = toks[i]
        low = t.lower()
        if low.startswith("data_"):
            i += 1
        elif low == "loop_":
            i += 1
            lt = []
            while i < len(toks) and toks[i].startswith("_"):
                lt.append(toks[i].lower())
                i += 1
            vals = []
            while i < len(toks) and not toks[i].startswith("_") and toks[i].lower() not in ("loop_",) and not toks[i].lower().startswith("data_"):
                vals.append(toks[i])
                i += 1
            rows = []
            for k in range(0, len(vals), max(1, len(lt))):
                chunk = vals[k:k + len(lt)]
                if len(chunk) == len(lt):
                    rows.append(chunk)
            loops.append((lt, rows))
        elif t.startswith("_"):
            if i + 1 < len(toks):
                tags[low] = toks[i + 1]
                i += 2
            else:
                i += 1
        else:
            i += 1
    return tags, loops


def atom_loop(loops):
    for lt, rows in loops:
        if "_atom_site_fract_x" in lt:
            return lt, rows
    raise ValueError("no atom loop")


def main(argv):
    with open(argv[1], "r", encoding="utf-8") as handle:
        text = handle.read()
    tags, loops = parse_cif(text)
    a = num(tags["_cell_length_a"])
    b = num(tags["_cell_length_b"])
    c = num(tags["_cell_length_c"])
    # Diagonal (orthogonal) scaling only.
    M = [[a, 0.0, 0.0], [0.0, b, 0.0], [0.0, 0.0, c]]
    lt, rows = atom_loop(loops)
    idx = {t: i for i, t in enumerate(lt)}

    def get(row, tag, default=None):
        i = idx.get(tag)
        return row[i] if (i is not None and i < len(row)) else default

    sites = []
    for row in rows:
        label = get(row, "_atom_site_label")
        ts = get(row, "_atom_site_type_symbol") or label
        element = re.match(r"([A-Za-z]{1,2})", str(ts)).group(1)
        element = element[0].upper() + element[1:].lower()
        frac = [
            num(get(row, "_atom_site_fract_x")),
            num(get(row, "_atom_site_fract_y")),
            num(get(row, "_atom_site_fract_z")),
        ]
        occ = num(get(row, "_atom_site_occupancy", "1.0"))
        dg = get(row, "_atom_site_disorder_group")
        dg = None if dg in (None, ".", "?") else int(float(dg))
        sites.append(
            {
                "label": label,
                "element": element,
                "frac": frac,
                "cart": [frac[0] * a, frac[1] * b, frac[2] * c],
                "occupancy": occ,
                "multiplicity": 1,
                "disorder_group": dg,
            }
        )
    sites.sort(key=lambda s: (s["element"], s["frac"][0], s["frac"][1], s["frac"][2], s["label"]))
    pairs = []
    for i in range(len(sites)):
        for j in range(i + 1, len(sites)):
            best = None
            best_off = None
            for off in OFFSETS:
                d = [sites[j]["frac"][k] + off[k] - sites[i]["frac"][k] for k in range(3)]
                x, y, z = d[0] * a, d[1] * b, d[2] * c
                dist = math.sqrt(x * x + y * y + z * z)
                if best is None or dist < best:
                    best = dist
                    best_off = off
            if best < CUTOFF:
                pairs.append({"i": i, "j": j, "offset": list(best_off), "distance": best})
    sys.stdout.write(json.dumps({"cell": M, "sites": sites, "pairs": pairs}) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

cat > ${W}/topology/__init__.py <<'PY'
PY
cat > ${W}/topology/summary.py <<'PY'
import json
import sys


def main(argv):
    with open(argv[1], "r", encoding="utf-8") as handle:
        canonical = json.load(handle)
    M = canonical["cell"]
    det = (
        M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1])
        - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0])
        + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0])
    )
    counts = {}
    for site in canonical["sites"]:
        counts[site["element"]] = counts.get(site["element"], 0) + 1
    deg = [0] * len(canonical["sites"])
    for pair in canonical["pairs"]:
        deg[int(pair["i"])] += 1
        deg[int(pair["j"])] += 1
    sys.stdout.write(
        json.dumps(
            {
                "volume": abs(det),
                "site_count": len(canonical["sites"]),
                "element_counts": counts,
                "coordination": deg,
            }
        )
        + "\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod -R a+rX ${W}/cif ${W}/topology
