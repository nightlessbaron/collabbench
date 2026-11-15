"""Hidden tests for pool-pressproof, adapted from the seed task's tests/test_outputs.py
(halcyon-pressproof-goal-0026-v2).

The reference (pressproof_lib: the PressProof v3.2 measurement, the renderer, the proof generator and the ticket
validator), the proofs, the tolerances and the time budget are the seed's. What changed for CollabBench:
- the deliverables live in the workspace (pressproof.py, job.yaml) and the scorer runs from a root-owned, read-only
  copy of it; grading as root, it runs as the task's dedicated unprivileged UID (tests/agent_uid), cannot read or
  change the tests, and nothing it starts outlives the run (harness.py). job.yaml is read from that copy through
  harness.read_text (isolation.read_under: as the agent UID, never through a link);
- every reading of every proof is its own test (`<proof>-<reading>`), so the score gives partial credit and each
  fact's family can be read off;
- the seed's eight calibration proofs, whose reading sheets the seed shipped, are hidden here (test_D1_archive: under
  each job's own ticket): their readings would let the measurement be fitted instead of learnt from the teammate;
- the recovered-artwork deliverable is gone: the approved artwork ships, so D2's content box is read off it, and its
  measured block is the approved proof's reading;
- the time-budget test also requires every hidden run to have produced a reading, so a missing scorer cannot pass
  it; a scorer that hangs is stopped by a per-run timeout and a 150 s timeout budget (harness.run_agent);
- test_D1_probe[<fact id>] reads one fact alone, for the fact requirements: a drawn proof (pressproof_probes) on
  which the one reading it checks moves when that fact is violated and stays put when any other fact is;
- test_D2_measured_pri_consistent: the ticket's measured pri is the readiness index of its own measured coverage and
  contrast (PressProof's reading always is), so the index is graded apart from the two readings it combines.
The verifier-only libraries (numpy, Pillow, scipy) are imported inside fixtures, so the suite is collected without
them. Test names carry the deliverable: test_D1_* grade pressproof.py, test_D2_* grade job.yaml.
"""

import importlib
import json
import re
import subprocess
import time

import pytest
import yaml

import harness as h

READINGS = ("ink_coverage", "min_contrast", "pri")
TOL = {"ink_coverage": 0.0015, "min_contrast": 0.004, "pri": 0.04}
ARCHIVE = ["proof_%02d" % i for i in range(1, 9)]  # pressproof_lib._VISIBLE_SPECS
HIDDEN = ["hidden_%02d" % i for i in range(1, 25)]  # pressproof_lib._HIDDEN_SPECS
SCORER_BUDGET = ("pressproof", 150.0)
WALL_BUDGET_S = 120.0
PROBE_FACTS = ["a1", "a2", "a3", "a4", "a5", "a6", "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8"]  # pressproof_probes


def _cases(names):
    return pytest.mark.parametrize("name,key", [(n, k) for n in names for k in READINGS],
                                   ids=["%s-%s" % (n, k) for n in names for k in READINGS])


@pytest.fixture(scope="session", autouse=True)
def _work():
    h.setup_work()


@pytest.fixture(scope="session")
def lib():
    return importlib.import_module("pressproof_lib")


@pytest.fixture(scope="session")
def probes(lib):
    module = importlib.import_module("pressproof_probes")
    assert sorted(module.PROBES) == PROBE_FACTS
    return module.PROBES


@pytest.fixture(scope="session")
def visible(lib):
    proofs = lib.generate_visible()["proofs"]
    assert [p["name"] for p in proofs] == [n + ".png" for n in ARCHIVE]
    return {p["name"][:-4]: p for p in proofs}


@pytest.fixture(scope="session")
def reference(lib):
    return lib.generate_reference()


@pytest.fixture(scope="session")
def hidden(lib):
    proofs = lib.generate_hidden()["proofs"]
    assert [p["name"] for p in proofs] == [n + ".png" for n in HIDDEN]
    return {p["name"][:-4]: p for p in proofs}


@pytest.fixture(scope="session")
def job_text():
    try:
        return h.read_text(h.ws("job.yaml"))
    except (OSError, ValueError):
        return ""


def _job(job_text):
    try:
        job = yaml.safe_load(job_text)
    except yaml.YAMLError:
        return None
    return job if isinstance(job, dict) else None


@pytest.fixture(scope="session")
def submitted_ticket(job_text):
    """The ticket the studio submitted, as (content_box_mm, resolution_dpi): either is None when the ticket does not
    carry it, and the scorer is then graded against the shop's own ticket for that proof (the seed's rule)."""
    box = dpi = None
    job = _job(job_text) or {}
    try:
        box = [float(v) for v in job["content_box_mm"]]
        if len(box) != 4 or any(v != v or v in (float("inf"), float("-inf")) for v in box):
            box = None
    except (KeyError, TypeError, ValueError):
        box = None
    try:
        dpi = int(job["resolution_dpi"])
    except (KeyError, TypeError, ValueError):
        dpi = None
    return box, dpi


def lib_ticket(proof):
    """A job file carrying only what the shop's archived sheet records."""
    return ("resolution_dpi: %d\ncontent_box_mm: [%s]\n"
            % (int(proof["ticket_dpi"]), ", ".join("%.9f" % float(v) for v in proof["content_box_mm"]))).encode()


def _run_one(proof, job_bytes, timeout):
    run_dir = h.fresh_run_dir({proof["name"]: proof["png"], "job.yaml": job_bytes})
    started = time.monotonic()
    try:
        proc = h.run_agent([h.PYTHON, h.ws("pressproof.py"), "score", proof["name"], "--job", "job.yaml"],
                           cwd=run_dir, timeout=timeout, budget=SCORER_BUDGET)
    except subprocess.TimeoutExpired:
        return {"error": "timeout", "elapsed": time.monotonic() - started}
    elapsed = time.monotonic() - started
    try:
        parsed = json.loads(proc.stdout)
    except ValueError:
        parsed = None
    return {"proc": proc, "out": parsed if isinstance(parsed, dict) else None, "elapsed": elapsed}


def _check(res, key, want):
    assert "proc" in res, "the scorer did not finish: %s" % res.get("error")
    proc = res["proc"]
    assert proc.returncode == 0, "exit %d: %s" % (proc.returncode, proc.stderr[-400:])
    assert res["out"] is not None, "stdout is not one JSON object: %r" % proc.stdout[:200]
    try:
        got = float(res["out"][key])
    except (KeyError, TypeError, ValueError):
        raise AssertionError("%s is missing or not a number" % key)
    assert abs(got - want) <= TOL[key], "%s: %r, expected %r" % (key, got, want)


# --- D1: pressproof.py -------------------------------------------------------------------------------------------------

@pytest.fixture(scope="session")
def archive_runs(visible):
    return {name: _run_one(p, lib_ticket(p), 12.0) for name, p in visible.items()}


def test_D1_contract(archive_runs):
    """One JSON object with three six-decimal numbers, exit 0 (on an archived proof under its own ticket)."""
    res = archive_runs["proof_02"]
    assert "proc" in res, "the scorer timed out on a small proof"
    proc = res["proc"]
    assert proc.returncode == 0, "exit %d: %s" % (proc.returncode, proc.stderr[-400:])
    assert isinstance(res["out"], dict), "stdout is not a JSON object: %r" % proc.stdout[:200]
    for key in READINGS:
        assert isinstance(res["out"].get(key), (int, float)), "missing numeric %s" % key
        assert re.search(r'"%s"\s*:\s*-?\d+\.\d{6,}' % key, proc.stdout), "%s is not printed to six decimals" % key


@_cases(ARCHIVE)
def test_D1_archive(name, key, visible, archive_runs):
    """An archived job's proof, under that job's own ticket, reads as PressProof read it."""
    _check(archive_runs[name], key, visible[name]["readings"][key])


def _pixel_box(lib, box, dpi, width, height):
    s = float(dpi) / 25.4
    xs = [max(0, min(width, lib._round_half_up(float(box[i]) * s))) for i in (0, 2)]
    ys = [max(0, min(height, lib._round_half_up(float(box[i]) * s))) for i in (1, 3)]
    return xs + ys


def _truth(lib, proof, box, dpi):
    """PressProof's reading of a hidden proof under the submitted ticket. When that ticket reads the proof exactly as
    the proof's own ticket does (the same effective dpi and the same pixel box), the generator's reading is it."""
    phys = lib.read_phys_dpi_bytes(proof["png"])
    own_dpi = phys if phys is not None else proof["ticket_dpi"]
    eff_dpi = phys if phys is not None else (dpi if dpi is not None else proof["ticket_dpi"])
    box = box if box is not None else proof["content_box_mm"]
    width = int.from_bytes(proof["png"][16:20], "big")
    height = int.from_bytes(proof["png"][20:24], "big")
    if eff_dpi == own_dpi and (_pixel_box(lib, box, eff_dpi, width, height)
                               == _pixel_box(lib, proof["content_box_mm"], own_dpi, width, height)):
        return proof["readings"]
    return lib.readings_of(proof["png"], dpi if dpi is not None else proof["ticket_dpi"], box)


@pytest.fixture(scope="session")
def hidden_runs(lib, hidden, job_text, submitted_ticket):
    """The scorer on every hidden proof under the submitted ticket (the seed's per-run limits)."""
    job_bytes = job_text.encode("utf-8") if job_text else b""
    box, dpi = submitted_ticket
    runs = {}
    for name, proof in hidden.items():
        runs[name] = _run_one(proof, job_bytes, 24.0 if proof["dpi"] >= 400 else 8.0)
        runs[name]["truth"] = _truth(lib, proof, box, dpi)
    return runs


@_cases(HIDDEN)
def test_D1_hidden(name, key, hidden_runs):
    """An unseen proof of the approved plate (degraded, scanned or large), under the submitted ticket."""
    _check(hidden_runs[name], key, hidden_runs[name]["truth"][key])


def test_D1_time_budget(hidden_runs):
    """The 24-proof hidden set: every run gives a reading, none times out, and the set takes at most 120 s."""
    wall = sum(res["elapsed"] for res in hidden_runs.values())
    unread = [name for name, res in hidden_runs.items()
              if "proc" not in res or res["proc"].returncode != 0 or res["out"] is None]
    assert not unread, "no reading for %s" % unread[:6]
    assert wall <= WALL_BUDGET_S, "the hidden set took %.1f s (budget %.0f s)" % (wall, WALL_BUDGET_S)


@pytest.mark.parametrize("fact", PROBE_FACTS)
def test_D1_probe(fact, lib, probes):
    """A drawn proof that isolates one part of the measurement, under its own ticket: one reading, as PressProof."""
    make, key = probes[fact]
    proof = make()
    proof["name"] = "probe.png"
    res = _run_one(proof, lib_ticket(proof), 12.0)
    _check(res, key, lib.readings_of(proof["png"], proof["ticket_dpi"], proof["content_box_mm"])[key])


# --- D2: job.yaml ------------------------------------------------------------------------------------------------------

def test_D2_ticket_validates(lib, job_text):
    """The press ticket is structurally acceptable to the shop's lint."""
    job = _job(job_text)
    assert job is not None, "job.yaml is missing or not a YAML mapping"
    errs = lib.validate_job(job)
    assert not errs, "ticket errors: %s" % errs


def test_D2_content_box(lib, job_text):
    """The declared content box is the vector-ink box in media coordinates."""
    job = _job(job_text)
    assert job is not None, "job.yaml is missing or not a YAML mapping"
    want = lib.content_box_mm(lib.ART)
    try:
        got = [float(v) for v in job["content_box_mm"]]
    except (KeyError, TypeError, ValueError):
        raise AssertionError("content_box_mm is missing or not numbers")
    assert len(got) == 4 and all(abs(g - w) <= 0.10 for g, w in zip(got, want)), (
        "content box %s is not %s (media mm)" % (got, want))


@pytest.mark.parametrize("key", READINGS)
def test_D2_measured(key, lib, job_text, reference):
    """The measured block holds PressProof's reading of the approved proof."""
    job = _job(job_text)
    assert job is not None, "job.yaml is missing or not a YAML mapping"
    truth = lib.readings_of(reference["png"], 300, lib.content_box_mm(lib.ART))
    try:
        got = float(job["measured"][key])
    except (KeyError, TypeError, ValueError):
        raise AssertionError("measured.%s is missing or not a number" % key)
    assert abs(got - truth[key]) <= TOL[key], "%s: %r, expected %r" % (key, got, truth[key])


def test_D2_measured_pri_consistent(job_text):
    """The measured pri is the readiness index of the measured coverage and contrast, as in every PressProof
    reading."""
    job = _job(job_text)
    assert job is not None, "job.yaml is missing or not a YAML mapping"
    try:
        cov, con, pri = (float(job["measured"][k]) for k in READINGS)
    except (KeyError, TypeError, ValueError):
        raise AssertionError("the measured block is missing a reading or holds a non-number")
    want = 100.0 * (0.65 * min(cov / 0.60, 1.0) + 0.35 * min(con / 0.85, 1.0))
    assert abs(pri - want) <= TOL["pri"], "pri %r, but coverage %r and contrast %r give %r" % (pri, cov, con, want)
