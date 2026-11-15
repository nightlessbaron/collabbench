#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
# Reference solution: writes the two Release 7 programs.

mkdir -p ${W}/cif ${W}/topology

cat > ${W}/cif/__init__.py <<'PY'
PY

cat > ${W}/cif/parse.py <<'PY'
"""Canonicalise a CIF 1.1 structure to the Release 7 canonical table.

Run as: python -m cif.parse <file.cif>
"""

import json
import math
import re
import sys
from fractions import Fraction

MERGE_TOL = 1e-3
CUTOFF = 3.5
OFFSETS = sorted(
    (h, k, l) for h in (-1, 0, 1) for k in (-1, 0, 1) for l in (-1, 0, 1)
)

_PAREN_RE = re.compile(
    r"^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\((\d+)\)$"
)


def parse_cif_number(tok):
    if tok is None:
        raise ValueError("missing numeric value")
    s = str(tok).strip()
    if len(s) >= 2 and s[0] in "'\"" and s[-1] == s[0]:
        s = s[1:-1].strip()
    if s in (".", "?"):
        raise ValueError("undefined numeric value")
    m = _PAREN_RE.match(s)
    if m:
        return float(m.group(1))
    return float(s)


def _strip_comment(line):
    out = []
    quote = None
    for ch in line:
        if quote is not None:
            out.append(ch)
            if ch == quote:
                quote = None
        else:
            if ch in "'\"":
                quote = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
    return "".join(out)


def tokenize(text):
    tokens = []
    for raw in text.splitlines():
        line = _strip_comment(raw)
        if not line.strip():
            continue
        i = 0
        n = len(line)
        while i < n:
            ch = line[i]
            if ch.isspace():
                i += 1
                continue
            if ch in "'\"":
                quote = ch
                j = i + 1
                buf = []
                while j < n and line[j] != quote:
                    buf.append(line[j])
                    j += 1
                tokens.append("".join(buf))
                i = j + 1
            else:
                j = i
                while j < n and not line[j].isspace():
                    j += 1
                tokens.append(line[i:j])
                i = j
    return tokens


def parse_cif(text):
    tokens = tokenize(text)
    tags = {}
    loops = []
    i = 0
    n = len(tokens)
    while i < n:
        tok = tokens[i]
        low = tok.lower()
        if low.startswith("data_"):
            i += 1
            continue
        if low == "loop_":
            i += 1
            loop_tags = []
            while i < n and tokens[i].startswith("_"):
                loop_tags.append(tokens[i])
                i += 1
            vals = []
            while i < n:
                t = tokens[i]
                tl = t.lower()
                if t.startswith("_") or tl == "loop_" or tl.startswith("data_"):
                    break
                vals.append(t)
                i += 1
            rows = []
            if loop_tags:
                width = len(loop_tags)
                for k in range(0, len(vals), width):
                    chunk = vals[k:k + width]
                    if len(chunk) == width:
                        rows.append(chunk)
            loops.append((loop_tags, rows))
            continue
        if tok.startswith("_"):
            if i + 1 < n:
                tags[low] = tokens[i + 1]
                i += 2
            else:
                tags[low] = None
                i += 1
            continue
        i += 1
    return tags, loops


def _eval_term(body):
    toks = re.findall(r"\d+/\d+|\d+|[xyz]|[*/]", body)
    if not toks:
        raise ValueError("empty term in symmetry expression")
    expanded = []
    prev = None
    for t in toks:
        if prev is not None and prev not in "*/" and t not in "*/":
            expanded.append("*")
        expanded.append(t)
        prev = t
    val = Fraction(1)
    var = None
    op = "*"
    for t in expanded:
        if t == "*":
            op = "*"
            continue
        if t == "/":
            op = "/"
            continue
        if t in "xyz":
            if var is not None:
                raise ValueError("non-linear symmetry expression")
            if op == "/":
                raise ValueError("variable divisor in symmetry expression")
            var = t
        else:
            num = Fraction(t)
            if op == "*":
                val *= num
            else:
                if num == 0:
                    raise ValueError("division by zero in symmetry expression")
                val /= num
    return var, val


def parse_lin(expr):
    expr = expr.replace(" ", "")
    if not expr:
        raise ValueError("empty symmetry component")
    if expr[0] not in "+-":
        expr = "+" + expr
    terms = []
    cur = ""
    for ch in expr:
        if ch in "+-":
            if cur:
                terms.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        terms.append(cur)
    coeff = [Fraction(0), Fraction(0), Fraction(0)]
    const = Fraction(0)
    for term in terms:
        if term[0] == "-":
            sign = -1
            body = term[1:]
        elif term[0] == "+":
            sign = 1
            body = term[1:]
        else:
            sign = 1
            body = term
        if not body:
            raise ValueError("dangling sign in symmetry expression")
        var, val = _eval_term(body)
        val *= sign
        if var is None:
            const += val
        else:
            coeff["xyz".index(var)] += val
    return (coeff[0], coeff[1], coeff[2], const)


def parse_symop(text):
    s = str(text).strip()
    if len(s) >= 2 and s[0] in "'\"" and s[-1] == s[0]:
        s = s[1:-1]
    comps = s.split(",")
    if len(comps) != 3:
        raise ValueError("bad symmetry operation: %r" % (text,))
    return [parse_lin(c) for c in comps]


def cell_matrix(a, b, c, alpha, beta, gamma):
    ar = math.radians(alpha)
    br = math.radians(beta)
    gr = math.radians(gamma)
    ca, cb, cg = math.cos(ar), math.cos(br), math.cos(gr)
    sg = math.sin(gr)
    if abs(sg) < 1e-12:
        raise ValueError("degenerate gamma angle")
    v2 = 1.0 - ca * ca - cb * cb - cg * cg + 2.0 * ca * cb * cg
    if v2 <= 0.0:
        raise ValueError("degenerate cell (non-positive volume)")
    volume = a * b * c * math.sqrt(v2)
    va = [a, 0.0, 0.0]
    vb = [b * cg, b * sg, 0.0]
    vc = [c * cb, c * (ca - cb * cg) / sg, volume / (a * b * sg)]
    return [va, vb, vc], volume


def apply_op(op, frac):
    out = []
    for (ax, ay, az, cst) in op:
        out.append(
            float(ax) * frac[0]
            + float(ay) * frac[1]
            + float(az) * frac[2]
            + float(cst)
        )
    return out


def to_cart(frac, M):
    return [
        frac[0] * M[0][0] + frac[1] * M[1][0] + frac[2] * M[2][0],
        frac[0] * M[0][1] + frac[1] * M[1][1] + frac[2] * M[2][1],
        frac[0] * M[0][2] + frac[1] * M[1][2] + frac[2] * M[2][2],
    ]


def _delta_dist(delta, M):
    x = delta[0] * M[0][0] + delta[1] * M[1][0] + delta[2] * M[2][0]
    y = delta[0] * M[0][1] + delta[1] * M[1][1] + delta[2] * M[2][1]
    z = delta[0] * M[0][2] + delta[1] * M[1][2] + delta[2] * M[2][2]
    return math.sqrt(x * x + y * y + z * z)


def periodic_dist(p, q, M):
    best = None
    for off in OFFSETS:
        d = _delta_dist(
            (p[0] + off[0] - q[0], p[1] + off[1] - q[1], p[2] + off[2] - q[2]),
            M,
        )
        if best is None or d < best:
            best = d
    return best


def min_image(p, q, M):
    distances = []
    best = None
    for off in OFFSETS:
        d = _delta_dist(
            (q[0] + off[0] - p[0], q[1] + off[1] - p[1], q[2] + off[2] - p[2]),
            M,
        )
        distances.append((off, d))
        if best is None or d < best:
            best = d
    for off, d in distances:
        if d <= best + 1e-9:
            return best, off
    return best, distances[0][0]


def norm_element(text):
    m = re.match(r"([A-Za-z]{1,2})", str(text).strip())
    if not m:
        return str(text).strip()
    e = m.group(1)
    return e[0].upper() + e[1:].lower()


_SYM_TAGS = (
    "_space_group_symop_operation_xyz",
    "_symmetry_equiv_pos_as_xyz",
)


def _find_symops(tags, loops):
    for loop_tags, rows in loops:
        low = [t.lower() for t in loop_tags]
        for im, t in enumerate(low):
            if t in _SYM_TAGS:
                out = [r[im] for r in rows if im < len(r)]
                if out:
                    return out
    for name in _SYM_TAGS:
        v = tags.get(name)
        if v is not None:
            return [v]
    return []


def _atom_loop(loops):
    for loop_tags, rows in loops:
        low = [t.lower() for t in loop_tags]
        if "_atom_site_fract_x" in low:
            return low, rows
    raise ValueError("no _atom_site fractional coordinate loop")


def _wrap(x):
    return x - math.floor(x)


def canonicalise(cif_text):
    tags, loops = parse_cif(cif_text)

    a = parse_cif_number(tags["_cell_length_a"])
    b = parse_cif_number(tags["_cell_length_b"])
    c = parse_cif_number(tags["_cell_length_c"])
    alpha = parse_cif_number(tags["_cell_angle_alpha"])
    beta = parse_cif_number(tags["_cell_angle_beta"])
    gamma = parse_cif_number(tags["_cell_angle_gamma"])
    M, _volume = cell_matrix(a, b, c, alpha, beta, gamma)

    op_strings = _find_symops(tags, loops)
    if not op_strings:
        op_strings = ["x,y,z"]
    ops = [parse_symop(s) for s in op_strings]

    low, rowvals = _atom_loop(loops)
    idx = {t: i for i, t in enumerate(low)}

    def cell_value(row, tag, default=None):
        i = idx.get(tag)
        if i is None:
            return default
        return row[i] if i < len(row) else default

    asym = []
    for row in rowvals:
        label = cell_value(row, "_atom_site_label")
        ts = cell_value(row, "_atom_site_type_symbol")
        if ts in (None, ".", "?"):
            ts = label
        element = norm_element(ts)
        fx = parse_cif_number(cell_value(row, "_atom_site_fract_x"))
        fy = parse_cif_number(cell_value(row, "_atom_site_fract_y"))
        fz = parse_cif_number(cell_value(row, "_atom_site_fract_z"))
        occ = parse_cif_number(cell_value(row, "_atom_site_occupancy", "1.0"))
        dg_s = cell_value(row, "_atom_site_disorder_group")
        if dg_s in (None, ".", "?"):
            dg = None
        else:
            dg = int(round(parse_cif_number(dg_s)))
        asym.append(
            {
                "label": label,
                "element": element,
                "frac": [fx, fy, fz],
                "occupancy": occ,
                "dg": dg,
            }
        )

    survivors = []
    for row in asym:
        raw = row["frac"]
        base = [_wrap(raw[0]), _wrap(raw[1]), _wrap(raw[2])]
        mult = 0
        for op in ops:
            p = apply_op(op, raw)
            if periodic_dist(p, base, M) <= MERGE_TOL:
                mult += 1
        for op in ops:
            p = apply_op(op, raw)
            p = [_wrap(p[0]), _wrap(p[1]), _wrap(p[2])]
            duplicate = False
            for s in survivors:
                if s["element"] != row["element"]:
                    continue
                if s["dg"] != row["dg"]:
                    continue
                if periodic_dist(p, s["frac"], M) <= MERGE_TOL:
                    duplicate = True
                    break
            if not duplicate:
                survivors.append(
                    {
                        "label": row["label"],
                        "element": row["element"],
                        "frac": p,
                        "occupancy": row["occupancy"],
                        "multiplicity": mult,
                        "dg": row["dg"],
                    }
                )

    survivors.sort(
        key=lambda s: (
            s["element"],
            s["frac"][0],
            s["frac"][1],
            s["frac"][2],
            s["label"],
        )
    )

    sites = []
    for s in survivors:
        sites.append(
            {
                "label": s["label"],
                "element": s["element"],
                "frac": [s["frac"][0], s["frac"][1], s["frac"][2]],
                "cart": to_cart(s["frac"], M),
                "occupancy": s["occupancy"],
                "multiplicity": s["multiplicity"],
                "disorder_group": s["dg"],
            }
        )

    pairs = []
    nsites = len(sites)
    for i in range(nsites):
        for j in range(i + 1, nsites):
            d, off = min_image(sites[i]["frac"], sites[j]["frac"], M)
            if d < CUTOFF:
                pairs.append(
                    {
                        "i": i,
                        "j": j,
                        "offset": [off[0], off[1], off[2]],
                        "distance": d,
                    }
                )
    pairs.sort(key=lambda p: (p["i"], p["j"], tuple(p["offset"])))

    return {
        "cell": [list(r) for r in M],
        "sites": sites,
        "pairs": pairs,
    }


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: python -m cif.parse <file.cif>\n")
        return 2
    with open(argv[1], "r", encoding="utf-8") as handle:
        text = handle.read()
    sys.stdout.write(json.dumps(canonicalise(text)))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

cat > ${W}/topology/__init__.py <<'PY'
PY

cat > ${W}/topology/summary.py <<'PY'
"""Summarise a Release 7 canonical table.

Run as: python -m topology.summary <canonical.json>
"""

import json
import sys


def _det3(M):
    return (
        M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1])
        - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0])
        + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0])
    )


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: python -m topology.summary <canonical.json>\n")
        return 2
    with open(argv[1], "r", encoding="utf-8") as handle:
        canonical = json.load(handle)
    sites = canonical["sites"]
    counts = {}
    for site in sites:
        counts[site["element"]] = counts.get(site["element"], 0) + 1
    coordination = [0] * len(sites)
    for pair in canonical["pairs"]:
        coordination[int(pair["i"])] += 1
        coordination[int(pair["j"])] += 1
    out = {
        "volume": abs(_det3(canonical["cell"])),
        "site_count": len(sites),
        "element_counts": counts,
        "coordination": coordination,
    }
    sys.stdout.write(json.dumps(out))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod -R a+rX ${W}/cif ${W}/topology
