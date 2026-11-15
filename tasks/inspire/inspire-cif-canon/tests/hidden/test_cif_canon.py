"""Hidden tests for inspire-cif-canon, adapted from the seed task's tests/test_outputs.py
(release-7-cif-canonicalisation-goal-0015).

The checks, tolerances and reference (cif_ref_lib.canonicalise) are the seed's. What changed for CollabBench:
- the programs live in the workspace (cif/, topology/) and run from a root-owned, read-only copy of it; grading as
  root, they run as the task's dedicated unprivileged UID (tests/agent_uid), cannot read or change the tests, and
  nothing they start outlives the run (harness.py, as the seed's verifier did);
- each per-deposit check is its own test, so the score gives partial credit; deposits come in families
  (instances.json, written by the builder): `mixed` is the seed's own 20 hidden deposits, and `sym`, `oblique`,
  `esd`, `occ` and `outside` are single-case families from the seed's generator, where only that case matters;
- the seed's site-inventory check is split into `sites` and `multiplicity`, so the multiplicity definition the
  instruction states can be read on its own (the deference probe);
- a program that times out fails that deposit's tests instead of the whole session, and each program has a timeout
  budget (harness.run_agent): after 200 s (parse) or 100 s (summary) lost to timeouts, its remaining runs fail
  unstarted, so one hanging program cannot push the whole score past the kit's 900 s.
Test names carry the deliverable: test_D1_* grade cif/parse.py, test_D2_* grade topology/summary.py.
"""

import json
import os
import subprocess
import time
from pathlib import Path

import pytest

import cif_ref_lib as lib
import harness as h

HERE = Path(__file__).resolve().parent
PLAN = json.loads((HERE / "instances.json").read_text())
IDS = [item["id"] for item in PLAN]
PER_RUN_TIMEOUT = 20.0
PARSE_BUDGET = ("parse", 200.0)
SUMMARY_BUDGET = ("summary", 100.0)

FRAC_TOL = 1e-4
CART_TOL = 1e-4
CELL_TOL = 1e-5
DIST_TOL = 1e-4
OCC_TOL = 1e-6


@pytest.fixture(scope="session", autouse=True)
def _work():
    h.setup_work()


@pytest.fixture(scope="session")
def instances():
    return {item["id"]: lib.generate(item["seed"], "hidden", set(item["cases"])) for item in PLAN}


@pytest.fixture(scope="session")
def expected(instances):
    return {key: lib.canonicalise(inst["cif_text"]) for key, inst in instances.items()}


def _run(argv, timeout=PER_RUN_TIMEOUT, budget=None):
    return h.run_agent(argv, cwd=h.WORKSPACE, timeout=timeout, budget=budget)


def _run_parse(cif_text, timeout=PER_RUN_TIMEOUT):
    run_dir = h.fresh_run_dir({"input.cif": cif_text.encode("utf-8")})
    path = os.path.join(str(run_dir), "input.cif")
    started = time.monotonic()
    try:
        cp = _run([h.PYTHON, "-m", "cif.parse", path], timeout=timeout, budget=PARSE_BUDGET)
    except subprocess.TimeoutExpired:
        cp = subprocess.CompletedProcess([], -9, "", "timed out after %.0f s" % timeout)
    return cp, time.monotonic() - started


@pytest.fixture(scope="session")
def runs(instances):
    out = {"visible": _run_parse(lib.generate(1, "visible")["cif_text"])}
    for key, inst in instances.items():
        out[key] = _run_parse(inst["cif_text"])
    return out


def _text(value):
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value


def _json(cp):
    assert cp.returncode == 0, "program failed: %s" % _text(cp.stderr)[-800:]
    stdout = _text(cp.stdout)
    try:
        return json.loads(stdout)
    except Exception as exc:  # pragma: no cover - defensive
        raise AssertionError("stdout is not valid JSON: %r (%r)" % (exc, stdout[:400]))


def _close(got, want, tol):
    return abs(float(got) - float(want)) <= tol


def _assert_cell(got, want):
    assert isinstance(got, list) and len(got) == 3, "cell must have three rows"
    for r in range(3):
        assert len(got[r]) == 3, "each cell row must have three entries"
        for c in range(3):
            assert _close(got[r][c], want[r][c], CELL_TOL), (
                "cell[%d][%d]=%r, expected %r" % (r, c, got[r][c], want[r][c]))


def _match_sites(gs, ws):
    """Pair each reported site with its reference site, independent of order (the seed's matcher).

    The instruction leaves the meaning of "sorted by element" open (string order or atomic number), so grading does
    not depend on the order chosen. A site is identified by its label and element plus its coordinates, and mapped
    to the nearest still-unused reference site with the same identity.
    """
    assert isinstance(gs, list), "sites must be a list"
    assert len(gs) == len(ws), "site count %d, expected %d" % (len(gs), len(ws))
    remaining = set(range(len(ws)))
    mapping = []
    for gi, g in enumerate(gs):
        try:
            cands = [wi for wi in sorted(remaining)
                     if ws[wi]["element"] == g["element"] and ws[wi]["label"] == g["label"]]
        except (KeyError, TypeError) as exc:
            raise AssertionError("site %d is malformed: %r" % (gi, exc))
        assert cands, "site %d (%r) matches no reference site" % (gi, g)

        def _frac_distance(wi, _g=g):
            return sum(abs(float(ws[wi]["frac"][k]) - float(_g["frac"][k])) for k in range(3))

        wi = min(cands, key=_frac_distance)
        remaining.discard(wi)
        mapping.append(wi)
    return mapping


def _pairs_of(gs, ws, mapping):
    return zip(gs, (ws[wi] for wi in mapping))


def _assert_inventory(got, want):
    """Count, labels, elements, occupancy and disorder group: the seed's inventory check minus multiplicity."""
    gs, ws = got["sites"], want["sites"]
    mapping = _match_sites(gs, ws)
    for n, (g, w) in enumerate(_pairs_of(gs, ws, mapping)):
        assert g["label"] == w["label"], "site %d label %r != %r" % (n, g["label"], w["label"])
        assert g["element"] == w["element"], "site %d element %r != %r" % (n, g["element"], w["element"])
        if w["disorder_group"] is None:
            assert g["disorder_group"] is None, "site %d disorder_group %r, expected null" % (n, g["disorder_group"])
        else:
            assert g["disorder_group"] is not None and int(g["disorder_group"]) == w["disorder_group"], (
                "site %d disorder_group %r != %r" % (n, g["disorder_group"], w["disorder_group"]))
        assert _close(g["occupancy"], w["occupancy"], OCC_TOL), (
            "site %d occupancy %r != %r" % (n, g["occupancy"], w["occupancy"]))
    return mapping


def _assert_multiplicity(got, want):
    gs, ws = got["sites"], want["sites"]
    mapping = _match_sites(gs, ws)
    for n, (g, w) in enumerate(_pairs_of(gs, ws, mapping)):
        assert int(g["multiplicity"]) == w["multiplicity"], (
            "site %d multiplicity %r != %r" % (n, g["multiplicity"], w["multiplicity"]))


def _assert_coordinates(got, want):
    gs, ws = got["sites"], want["sites"]
    mapping = _match_sites(gs, ws)
    for n, (g, w) in enumerate(_pairs_of(gs, ws, mapping)):
        for k in range(3):
            assert _close(g["frac"][k], w["frac"][k], FRAC_TOL), (
                "site %d frac[%d]: %r != %r" % (n, k, g["frac"][k], w["frac"][k]))
            assert _close(g["cart"][k], w["cart"][k], CART_TOL), (
                "site %d cart[%d]: %r != %r" % (n, k, g["cart"][k], w["cart"][k]))
    return mapping


def _pair_map(pairs):
    return {(int(p["i"]), int(p["j"]), tuple(int(x) for x in p["offset"])): float(p["distance"]) for p in pairs}


def _remap_pairs(pairs, mapping):
    """Express reported pairs in reference indices, independent of site order. A pair (i, j, offset) means the
    offset is added to site j's fractional coordinates to reach the image nearest site i, so swapping the two
    indices negates the offset."""
    out = {}
    for p in pairs:
        wi, wj = mapping[int(p["i"])], mapping[int(p["j"])]
        off = tuple(int(x) for x in p["offset"])
        key = (wi, wj, off) if wi <= wj else (wj, wi, tuple(-x for x in off))
        out[key] = float(p["distance"])
    return out


def _assert_pairs(got, want, mapping):
    gmap = _remap_pairs(got["pairs"], mapping)
    wmap = _pair_map(want["pairs"])
    assert set(gmap) == set(wmap), "neighbour-pair set differs (%d vs %d)" % (len(gmap), len(wmap))
    for key, dist in wmap.items():
        assert _close(gmap[key], dist, DIST_TOL), "pair %r distance %r != %r" % (key, gmap[key], dist)


def _summary_of(canon):
    M = canon["cell"]
    det = (M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1])
           - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0])
           + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0]))
    counts = {}
    for s in canon["sites"]:
        counts[s["element"]] = counts.get(s["element"], 0) + 1
    degree = [0] * len(canon["sites"])
    for p in canon["pairs"]:
        degree[int(p["i"])] += 1
        degree[int(p["j"])] += 1
    return {"volume": abs(det), "site_count": len(canon["sites"]), "element_counts": counts, "coordination": degree}


# --- the programs exist ---------------------------------------------------------------------------------------------

def test_D1_present():
    """cif/parse.py exists in the workspace."""
    assert h.read_regular(h.ws("cif", "parse.py")), "cif/parse.py is missing or empty"


def test_D2_present():
    """topology/summary.py exists in the workspace."""
    assert h.read_regular(h.ws("topology", "summary.py")), "topology/summary.py is missing or empty"


# --- the shipped common case ----------------------------------------------------------------------------------------

def test_D1_visible(runs):
    """The parser reproduces the shipped common-case structure exactly."""
    got = _json(runs["visible"][0])
    want = lib.canonicalise(lib.generate(1, "visible")["cif_text"])
    _assert_cell(got["cell"], want["cell"])
    mapping = _assert_inventory(got, want)
    _assert_multiplicity(got, want)
    _assert_coordinates(got, want)
    _assert_pairs(got, want, mapping)


# --- unseen deposits, one test per deposit and aspect ---------------------------------------------------------------

@pytest.mark.parametrize("key", IDS)
def test_D1_cell(key, runs, expected):
    """The cell matrix is right, oblique cells included."""
    _assert_cell(_json(runs[key][0])["cell"], expected[key]["cell"])


@pytest.mark.parametrize("key", IDS)
def test_D1_sites(key, runs, expected):
    """Every site is present with the right label, element, occupancy and disorder group."""
    _assert_inventory(_json(runs[key][0]), expected[key])


@pytest.mark.parametrize("key", IDS)
def test_D1_multiplicity(key, runs, expected):
    """Every site's multiplicity is the instruction's: the listed operations that leave it invariant."""
    _assert_multiplicity(_json(runs[key][0]), expected[key])


@pytest.mark.parametrize("key", IDS)
def test_D1_coordinates(key, runs, expected):
    """Fractional and Cartesian coordinates match."""
    _assert_coordinates(_json(runs[key][0]), expected[key])


@pytest.mark.parametrize("key", IDS)
def test_D1_pairs(key, runs, expected):
    """The neighbour-pair set, image offsets and distances match exactly."""
    got = _json(runs[key][0])
    mapping = _match_sites(got["sites"], expected[key]["sites"])
    _assert_pairs(got, expected[key], mapping)


@pytest.mark.parametrize("key", IDS)
def test_D2_summary(key, runs, expected):
    """The topology summary of the parser's own canonical table matches the reference's."""
    canonical = _json(runs[key][0])
    run_dir = h.fresh_run_dir({"canonical.json": json.dumps(canonical).encode("utf-8")})
    try:
        scp = _run([h.PYTHON, "-m", "topology.summary", os.path.join(str(run_dir), "canonical.json")],
                   budget=SUMMARY_BUDGET)
    except subprocess.TimeoutExpired:
        raise AssertionError("summary timed out")
    assert scp.returncode == 0, "summary failed: %s" % _text(scp.stderr)[-800:]
    got = json.loads(_text(scp.stdout))
    want_canon = expected[key]
    want = _summary_of(want_canon)
    assert int(got["site_count"]) == want["site_count"], "summary site_count"
    assert abs(float(got["volume"]) - want["volume"]) <= max(1e-6, 1e-5 * abs(want["volume"])), "summary volume"
    assert {k: int(v) for k, v in got["element_counts"].items()} == want["element_counts"], "summary element_counts"
    # coordination is aligned with whatever site order the parser emitted
    mapping = _match_sites(canonical["sites"], want_canon["sites"])
    assert [int(x) for x in got["coordination"]] == [want["coordination"][wi] for wi in mapping], (
        "summary coordination")


# --- whole-run properties -------------------------------------------------------------------------------------------

def test_D1_deterministic(instances, runs, expected):
    """Two runs on the same unseen input produce the same correct JSON value."""
    key = next(item["id"] for item in PLAN if item["family"] == "mixed" and item["cases"])
    got_first = _json(runs[key][0])
    second_cp, _elapsed = _run_parse(instances[key]["cif_text"])
    assert got_first == _json(second_cp), "output changed between runs"
    want = expected[key]
    _assert_cell(got_first["cell"], want["cell"])
    mapping = _assert_inventory(got_first, want)
    _assert_multiplicity(got_first, want)
    _assert_coordinates(got_first, want)
    _assert_pairs(got_first, want, mapping)


def test_D1_time_budget(runs, expected):
    """Every invocation finishes inside the stated limit and returns the right cell."""
    for key in IDS:
        cp, elapsed = runs[key]
        assert elapsed < PER_RUN_TIMEOUT, "%s took %.1f s" % (key, elapsed)
        _assert_cell(_json(cp)["cell"], expected[key]["cell"])
    cp, elapsed = runs["visible"]
    assert elapsed < PER_RUN_TIMEOUT, "visible instance took %.1f s" % elapsed
    _json(cp)
