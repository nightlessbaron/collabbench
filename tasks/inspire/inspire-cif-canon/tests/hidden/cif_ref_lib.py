"""Verifier-side reference for the Release 7 CIF canonicalisation task.

The canonicalisation follows IUCr CIF 1.1 and International Tables for
Crystallography Volume A.  This module also builds the generated instance
profiles used by the tests and the independent format validator.

Nothing here is ever visible to the agent.
"""

import math
import random
import re
from fractions import Fraction

MERGE_TOL = 1e-3          # Angstrom, special-position merge tolerance
CUTOFF = 3.5              # Angstrom, neighbour cutoff
OFFSETS = sorted(
    (h, k, l) for h in (-1, 0, 1) for k in (-1, 0, 1) for l in (-1, 0, 1)
)
CASES = ("sym", "esd", "occ", "oblique", "outside")
HIDDEN_SEEDS = list(range(9001, 9021))


# --------------------------------------------------------------------------
# CIF numbers: leading value only, the parenthesised standard uncertainty
# (and anything after it) never enters arithmetic.
# --------------------------------------------------------------------------

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


def parse_cif_number_variant(tok, esd_digits):
    """Alternative reading used only by identifiability checks."""
    if not esd_digits:
        return parse_cif_number(tok)
    s = str(tok).strip()
    if len(s) >= 2 and s[0] in "'\"" and s[-1] == s[0]:
        s = s[1:-1].strip()
    m = re.match(r"^([+-]?[\d.]+)\((\d+)\)$", s)
    if m:
        return float(m.group(1) + m.group(2))
    return float(s)


# --------------------------------------------------------------------------
# A small CIF 1.1 tokeniser and parser, enough for loop_ and single tags.
# --------------------------------------------------------------------------

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


# --------------------------------------------------------------------------
# Symmetry operation expressions ("-x+1/2,y,-z") -> linear forms over Q.
# --------------------------------------------------------------------------

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


# --------------------------------------------------------------------------
# Cell geometry (International Tables Volume A convention).
# --------------------------------------------------------------------------

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
    vc = [
        c * cb,
        c * (ca - cb * cg) / sg,
        volume / (a * b * sg),
    ]
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
    """Distance and offset with q+offset closest to p.

    OFFSETS is in lexicographic order, so the first offset whose distance is
    within 1e-9 A of the minimum is the lexicographically smallest minimiser.
    """
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


# --------------------------------------------------------------------------
# Element symbols.
# --------------------------------------------------------------------------

def norm_element(text):
    m = re.match(r"([A-Za-z]{1,2})", str(text).strip())
    if not m:
        return str(text).strip()
    e = m.group(1)
    return e[0].upper() + e[1:].lower()


# --------------------------------------------------------------------------
# Locating the symmetry and atom-site sections.
# --------------------------------------------------------------------------

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


# --------------------------------------------------------------------------
# The canonicalisation itself.
# --------------------------------------------------------------------------

def canonicalise(
    cif_text,
    ops_override=None,
    diagonal=False,
    esd_digits=False,
    wrap_enabled=True,
    multiplicity_one=False,
    ignore_disorder=False,
):
    num = (
        (lambda t: parse_cif_number_variant(t, True))
        if esd_digits
        else parse_cif_number
    )
    tags, loops = parse_cif(cif_text)

    a = num(tags["_cell_length_a"])
    b = num(tags["_cell_length_b"])
    c = num(tags["_cell_length_c"])
    alpha = num(tags["_cell_angle_alpha"])
    beta = num(tags["_cell_angle_beta"])
    gamma = num(tags["_cell_angle_gamma"])
    M, _volume = cell_matrix(a, b, c, alpha, beta, gamma)
    if diagonal:
        M = [[a, 0.0, 0.0], [0.0, b, 0.0], [0.0, 0.0, c]]

    wrapx = _wrap if wrap_enabled else (lambda x: x)

    if ops_override is not None:
        op_strings = list(ops_override)
    else:
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
        fx = num(cell_value(row, "_atom_site_fract_x"))
        fy = num(cell_value(row, "_atom_site_fract_y"))
        fz = num(cell_value(row, "_atom_site_fract_z"))
        occ = num(cell_value(row, "_atom_site_occupancy", "1.0"))
        dg_s = cell_value(row, "_atom_site_disorder_group")
        if dg_s in (None, ".", "?"):
            dg = None
        else:
            dg = int(round(num(dg_s)))
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
        base = [wrapx(raw[0]), wrapx(raw[1]), wrapx(raw[2])]
        if multiplicity_one:
            mult = 1
        else:
            mult = 0
            for op in ops:
                p = apply_op(op, raw)
                if periodic_dist(p, base, M) <= MERGE_TOL:
                    mult += 1
        for op in ops:
            p = apply_op(op, raw)
            p = [wrapx(p[0]), wrapx(p[1]), wrapx(p[2])]
            duplicate = False
            for s in survivors:
                if s["element"] != row["element"]:
                    continue
                if (not ignore_disorder) and s["dg"] != row["dg"]:
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


# --------------------------------------------------------------------------
# Instance generation.
# --------------------------------------------------------------------------

_NON_P1 = [
    (2, ["x,y,z", "-x,-y,-z"]),
    (3, ["x,y,z", "-x,y,-z"]),
    (4, ["x,y,z", "-x,y+1/2,-z"]),
    (14, ["x,y,z", "-x,y+1/2,-z+1/2", "-x,-y,-z", "x,-y+1/2,z+1/2"]),
    (
        62,
        [
            "x,y,z",
            "-x+1/2,-y,z+1/2",
            "-x,y+1/2,-z",
            "x+1/2,-y+1/2,-z+1/2",
            "-x,-y,-z",
            "x+1/2,y,-z+1/2",
            "x,-y+1/2,z",
            "-x+1/2,y+1/2,z+1/2",
        ],
    ),
]

_ELEMENTS = ["C", "N", "O", "S", "P", "Cl", "Na", "K", "Ca", "Fe", "Zn"]


def _stabilizer(ops, frac, M):
    base = [_wrap(frac[0]), _wrap(frac[1]), _wrap(frac[2])]
    count = 0
    for op in ops:
        p = apply_op(op, frac)
        if periodic_dist(p, base, M) <= MERGE_TOL:
            count += 1
    return count


def find_special(ops, M):
    for cand in (
        [0.0, 0.0, 0.0],
        [0.0, 0.25, 0.0],
        [0.0, 0.0, 0.25],
        [0.25, 0.25, 0.25],
        [0.5, 0.5, 0.5],
        [0.0, 0.0, 0.5],
        [0.25, 0.25, 0.0],
    ):
        if _stabilizer(ops, cand, M) >= 2:
            return list(cand)
    return None


def _fmt_atom(value, esd):
    if esd:
        u = 11 + int(abs(value) * 1000) % 79
        return "%.3f(%d)" % (value, u)
    return "%.6f" % value


def _fmt_cell(value, esd):
    if esd:
        u = 11 + int(abs(value) * 100) % 79
        return "%.3f(%d)" % (value, u)
    return "%.6f" % value


def _render(seed, a, b, c, alpha, beta, gamma, it_number, ops_s, sym_tag, rows, esd):
    lines = []
    lines.append("data_dep_%04d" % (seed % 10000))
    lines.append("_chemical_formula_sum 'C1 H2'")
    lines.append("_cell_length_a " + _fmt_cell(a, esd))
    lines.append("_cell_length_b " + _fmt_cell(b, esd))
    lines.append("_cell_length_c " + _fmt_cell(c, esd))
    lines.append("_cell_angle_alpha " + _fmt_cell(alpha, esd))
    lines.append("_cell_angle_beta " + _fmt_cell(beta, esd))
    lines.append("_cell_angle_gamma " + _fmt_cell(gamma, esd))
    lines.append("_space_group_IT_number %d" % it_number)
    lines.append("loop_")
    lines.append(sym_tag)
    for s in ops_s:
        lines.append("  '%s'" % s)
    lines.append("loop_")
    for tag in (
        "_atom_site_label",
        "_atom_site_type_symbol",
        "_atom_site_fract_x",
        "_atom_site_fract_y",
        "_atom_site_fract_z",
        "_atom_site_occupancy",
        "_atom_site_disorder_group",
    ):
        lines.append(tag)
    for r in rows:
        vals = [
            r["label"],
            r["element"],
            _fmt_atom(r["frac"][0], esd),
            _fmt_atom(r["frac"][1], esd),
            _fmt_atom(r["frac"][2], esd),
            "%.4f" % r["occupancy"],
            ("%d" % r["dg"]) if r["dg"] is not None else ".",
        ]
        lines.append("  " + " ".join(vals))
    return "\n".join(lines) + "\n"


_OBLIQUE_TRIPLES = [
    (78.5, 91.3, 103.7),
    (95.0, 105.5, 88.0),
    (110.2, 82.4, 97.6),
    (67.0, 88.0, 101.0),
]


def _build(seed, profile, cases, attempt):
    rng = random.Random((seed * 1000003 + attempt * 7919) & 0x7FFFFFFF)

    # Cell parameters.
    if "oblique" in cases:
        a = round(rng.uniform(6.5, 12.5), 3)
        b = round(rng.uniform(6.5, 12.5), 3)
        c = round(rng.uniform(6.5, 12.5), 3)
        alpha, beta, gamma = rng.choice(_OBLIQUE_TRIPLES)
        alpha = round(alpha + rng.uniform(-1.5, 1.5), 2)
        beta = round(beta + rng.uniform(-1.5, 1.5), 2)
        gamma = round(gamma + rng.uniform(-1.5, 1.5), 2)
    else:
        a = round(rng.uniform(6.5, 12.5), 3)
        b = round(rng.uniform(6.5, 12.5), 3)
        c = round(rng.uniform(6.5, 12.5), 3)
        alpha = beta = gamma = 90.0
    M, _v = cell_matrix(a, b, c, alpha, beta, gamma)

    # Symmetry: when enabled, always pick a group that supplies a special position.
    if "sym" in cases:
        groups = list(_NON_P1)
        rng.shuffle(groups)
        selected = None
        special = None
        for it_number, ops_s in groups:
            ops_tmp = [parse_symop(s) for s in ops_s]
            sp = find_special(ops_tmp, M)
            if sp is not None:
                selected = (it_number, ops_s)
                special = sp
                break
        if selected is None:
            it_number, ops_s = _NON_P1[0]
            special = None
        else:
            it_number, ops_s = selected
    else:
        it_number, ops_s = 1, ["x,y,z"]
        special = None

    nrows = 3 if profile == "visible" else rng.randint(6, 10)
    rows = []
    for k in range(nrows):
        element = rng.choice(_ELEMENTS)
        if k == 0:
            frac = list(special) if special is not None else [0.5, 0.5, 0.5]
        elif k == 1:
            frac = [
                rows[0]["frac"][0] + 0.14,
                rows[0]["frac"][1] + 0.08,
                rows[0]["frac"][2] + 0.05,
            ]
        else:
            frac = [round(rng.uniform(0.06, 0.94), 4) for _ in range(3)]
            if "outside" in cases and (k == 2 or rng.random() < 0.6):
                axis = rng.randrange(3)
                frac[axis] += rng.choice([-1.0, 1.0])
        occupancy = 1.0
        if "occ" in cases and rng.random() < 0.45:
            occupancy = rng.choice([0.5, 0.25, 0.75, 0.3333])
        rows.append(
            {
                "element": element,
                "frac": [float(x) for x in frac],
                "occupancy": occupancy,
                "dg": None,
            }
        )

    if "occ" in cases and len(rows) >= 4:
        src = rows[2]
        rows[2] = {
            "element": src["element"],
            "frac": list(src["frac"]),
            "occupancy": 0.5,
            "dg": 1,
        }
        rows.insert(
            3,
            {
                "element": src["element"],
                "frac": list(src["frac"]),
                "occupancy": 0.5,
                "dg": 2,
            },
        )

    for k, row in enumerate(rows):
        row["label"] = "%s%d" % (row["element"], k + 1)

    sym_tag = (
        "_symmetry_equiv_pos_as_xyz"
        if "outside" in cases
        else "_space_group_symop_operation_xyz"
    )
    text = _render(
        seed, a, b, c, alpha, beta, gamma, it_number, ops_s, sym_tag, rows, "esd" in cases
    )
    return {
        "seed": seed,
        "profile": profile,
        "cases": sorted(cases),
        "cif_text": text,
    }


def generate(seed, profile="hidden", cases=None):
    if cases is None:
        cases = default_cases(seed) if profile == "hidden" else set()
    cases = set(cases)
    inst = None
    for attempt in range(8):
        inst = _build(seed, profile, cases, attempt)
        try:
            can = canonicalise(inst["cif_text"])
        except Exception:
            continue
        if can["pairs"]:
            return inst
    return inst


def default_cases(seed):
    rng = random.Random((seed ^ 0x9E3779B9) & 0x7FFFFFFF)
    return {c for c in CASES if rng.random() < 0.30}


def hidden_instances():
    chosen = {s: default_cases(s) for s in HIDDEN_SEEDS}
    covered = set()
    for cs in chosen.values():
        covered |= cs
    missing = [c for c in CASES if c not in covered]
    for c in missing:
        chosen[HIDDEN_SEEDS[0]].add(c)
    return [generate(s, "hidden", chosen[s]) for s in HIDDEN_SEEDS]


def visible_instance():
    return generate(1, "visible")


# --------------------------------------------------------------------------
# Independent format validator (written from the format, not the generator).
# --------------------------------------------------------------------------

def validate_instance(inst):
    problems = []
    try:
        tags, loops = parse_cif(inst["cif_text"])
    except Exception as exc:  # pragma: no cover - defensive
        return ["unreadable CIF: %r" % (exc,)]

    required = (
        "_cell_length_a",
        "_cell_length_b",
        "_cell_length_c",
        "_cell_angle_alpha",
        "_cell_angle_beta",
        "_cell_angle_gamma",
    )
    for t in required:
        if t not in tags:
            problems.append("missing %s" % t)
    if problems:
        return problems

    try:
        a = parse_cif_number(tags["_cell_length_a"])
        b = parse_cif_number(tags["_cell_length_b"])
        c = parse_cif_number(tags["_cell_length_c"])
        alpha = parse_cif_number(tags["_cell_angle_alpha"])
        beta = parse_cif_number(tags["_cell_angle_beta"])
        gamma = parse_cif_number(tags["_cell_angle_gamma"])
        M, volume = cell_matrix(a, b, c, alpha, beta, gamma)
    except Exception as exc:
        return ["bad cell parameters: %r" % (exc,)]

    if not (volume > 0.0):
        problems.append("cell volume is not positive")
    for name, value in (("a", a), ("b", b), ("c", c)):
        if not (value > 0.0):
            problems.append("non-positive cell length %s" % name)
    for name, value in (("alpha", alpha), ("beta", beta), ("gamma", gamma)):
        if not (0.0 < value < 180.0):
            problems.append("angle %s outside (0, 180)" % name)

    try:
        op_strings = _find_symops(tags, loops)
        if not op_strings:
            problems.append("no symmetry operations listed")
        ops = [parse_symop(s) for s in op_strings]
    except Exception as exc:
        return problems + ["bad symmetry operation: %r" % (exc,)]

    probe = [0.137, 0.271, 0.419]
    has_identity = False
    for op in ops:
        if periodic_dist(apply_op(op, probe), probe, M) <= 1e-6:
            has_identity = True
            break
    if not has_identity:
        problems.append("symmetry list has no identity operation")

    try:
        low, rowvals = _atom_loop(loops)
    except Exception as exc:
        return problems + ["no atom-site loop: %r" % (exc,)]

    idx = {t: i for i, t in enumerate(low)}
    if "_atom_site_label" not in idx:
        problems.append("atom-site loop has no label column")
    if "_atom_site_fract_x" not in idx:
        problems.append("atom-site loop has no fractional coordinate column")

    seen_labels = set()
    for r_i, row in enumerate(rowvals):
        def get(tag, default=None, _row=row):
            i = idx.get(tag)
            return _row[i] if (i is not None and i < len(_row)) else default

        label = get("_atom_site_label")
        if label is None:
            problems.append("atom row %d has no label" % r_i)
            continue
        if label in seen_labels:
            problems.append("duplicate atom label %r" % label)
        seen_labels.add(label)
        ts = get("_atom_site_type_symbol") or label
        if not re.match(r"^[A-Za-z]{1,2}$", str(ts)):
            problems.append("atom row %d has an invalid element symbol %r" % (r_i, ts))
        try:
            fx = parse_cif_number(get("_atom_site_fract_x"))
            fy = parse_cif_number(get("_atom_site_fract_y"))
            fz = parse_cif_number(get("_atom_site_fract_z"))
            if not all(math.isfinite(v) for v in (fx, fy, fz)):
                problems.append("atom row %d has a non-finite coordinate" % r_i)
        except Exception as exc:
            problems.append("atom row %d has a bad coordinate: %r" % (r_i, exc))
        try:
            occ = parse_cif_number(get("_atom_site_occupancy", "1.0"))
            if not (0.0 < occ <= 1.0):
                problems.append("atom row %d occupancy outside (0, 1]" % r_i)
        except Exception as exc:
            problems.append("atom row %d has a bad occupancy: %r" % (r_i, exc))

    try:
        can = canonicalise(inst["cif_text"])
    except Exception as exc:
        return problems + ["canonicalisation failed: %r" % (exc,)]

    if not can["pairs"]:
        problems.append("expanded structure has no neighbour pairs")

    sites = can["sites"]
    for i in range(len(sites)):
        for j in range(i + 1, len(sites)):
            si = sites[i]
            sj = sites[j]
            if si["element"] != sj["element"]:
                continue
            if si["disorder_group"] != sj["disorder_group"]:
                continue
            d = periodic_dist(si["frac"], sj["frac"], M)
            if MERGE_TOL < d < 0.5:
                problems.append(
                    "unphysical duplicate sites %r/%r at %.3f A"
                    % (si["label"], sj["label"], d)
                )
    return problems