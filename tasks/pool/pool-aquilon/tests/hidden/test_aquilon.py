"""Hidden tests for pool-aquilon, adapted from the seed task's tests/test_outputs.py
(aquilon-settlement-export-goal-0012-e1).

The reference (aquilon_lib: tcanon_reference, the ELF builder and injector) and the hidden inputs are the seed's.
What changed for CollabBench:
- the programs live in the workspace (tools/, migration/tcanon/) and run from a root-owned, read-only copy of it;
  grading as root, they run as the task's dedicated unprivileged UID (tests/agent_uid), cannot read or change the
  tests, and nothing they start outlives the run (harness.py). Everything a program leaves is read back through
  harness.read_regular (isolation.read_under): as the agent UID, walked from the work root, never through a link;
- every check is its own test, so the score gives partial credit: one test per infected release build, one per
  unseen unload, one per probe;
- tcanon.py's standard output goes to a file in its run directory (a shell redirect, run as the agent UID) and is
  compared as bytes, so line ends and encoding are graded exactly;
- restore_aquilon.py writes into out/ under its run directory, a directory the program controls: a symlink there
  is never followed (the parent-symlink case);
- the seed's in-place check of the shipped appliance library is gone with the library (no copy ships: it would show
  the injector's payload), and the probes `sample` (the shipped unload) and `note_*` (one convention of the NOTE
  field each) are added;
- test_D2_fact[<fact id>] reads one fact's effect alone (FACT_VIEWS), for the fact requirements: it runs an input
  that exercises that fact and compares only what the fact decides, read leniently from the stream, so a mistake
  elsewhere (the framing, the control section, the row order, a column too many, the quoting) does not fail it.
Test names carry the deliverable: test_D1_* grade tools/restore_aquilon.py, test_D2_* grade
migration/tcanon/tcanon.py.
"""

import os
import subprocess

import pytest

import aquilon_lib as lib
import harness as h

RUN_TIMEOUT = 30.0
RESTORE_BUDGET = ("restore", 120.0)
TCANON_BUDGET = ("tcanon", 240.0)
VARIANTS = [spec["name"] for spec in lib.ELF_VARIANTS]
CORPUS = ["hidden-%d" % seed for seed in lib.CORPUS_SEEDS]

# Probes added for CollabBench: valid .tdu v4 unloads, each isolating one convention of the NOTE field (and the
# shipped sample, which isolates the plain layout). Expected streams come from the seed's reference.
NOTE_PROBES = {
    "note_null": [
        b"01-APR-24|9000000301|0000003001|301|1.000|0.1000|\\N",
        b"01-APR-24|9000000302|0000003002|302|2.000|0.1000|",
        b"01-APR-24|9000000303|0000003003|303|3.000|0.1000|plain note",
        b"01-APR-24|9000000304|0000003004|304|4.000|0.1000|\\N",
    ],
    "note_padding": [
        b"01-APR-24|9000000311   |0000003011|311|1.000|0.1000|padded note   ",
        b"01-APR-24|9000000312|0000003012  |312|2.000   |0.1000|      ",
        b"01-APR-24|9000000313|0000003013|313   |3.000|0.1000   |x  ",
        b"01-APR-24 |9000000314|0000003014|314|4.000|0.1000|tail",
    ],
    "note_charset": [
        b"01-APR-24|9000000321|0000003021|321|1.000|0.1000|caf\xe9 au lait",
        b"01-APR-24|9000000322|0000003022|322|2.000|0.1000|\x80 12.40 credit",
        b"01-APR-24|9000000323|0000003023|323|3.000|0.1000|meter\x92s seal \x96 replaced",
        b"01-APR-24|9000000324|0000003024|324|4.000|0.1000|\x93quoted\x94 reading",
    ],
    "note_cut": [
        b"01-APR-24|9000000331|0000003031|331|1.000|0.1000|" + b"Z" * 41,
        b"01-APR-24|9000000332|0000003032|332|2.000|0.1000|" + b"0123456789" * 12,
        b"01-APR-24|9000000333|0000003033|333|3.000|0.1000|" + b"forty characters exactly in this note ok",
    ],
    "note_quotes": [
        b'01-APR-24|9000000341|0000003041|341|1.000|0.1000|He said "pay" twice',
        b'01-APR-24|9000000342|0000003042|342|2.000|0.1000|"',
        b"01-APR-24|9000000343|0000003043|343|3.000|0.1000|a|b|c",
        b'01-APR-24|9000000344|0000003044|344|4.000|0.1000|""',
    ],
}
PROBES = sorted(list(lib.PROBE_SEEDS) + list(NOTE_PROBES) + ["sample"])


def _restore():
    return h.ws("tools", "restore_aquilon.py")


def _tcanon():
    return h.ws("migration", "tcanon", "tcanon.py")


@pytest.fixture(scope="session", autouse=True)
def _work():
    h.setup_work()


def _run(argv, inputs, budget, dirs=()):
    """Run argv in a fresh run directory holding `inputs` (and the empty directories `dirs`), as the agent UID."""
    run_dir = h.fresh_run_dir({**inputs, **{os.path.join(d, ".keep"): b"" for d in dirs}})
    try:
        proc = h.run_agent(argv, cwd=run_dir, timeout=RUN_TIMEOUT, budget=budget)
    except subprocess.TimeoutExpired:
        proc = subprocess.CompletedProcess(argv, -9, "", "timed out after %.0f s" % RUN_TIMEOUT)
    except Exception as exc:  # noqa: BLE001 - a deliverable that will not run
        proc = subprocess.CompletedProcess(argv, 127, "", "could not run: %s" % exc)
    return run_dir, proc


def _output(run_dir, rel):
    """Bytes a program left at `rel` in its run directory, or None (missing, a link, a special file)."""
    try:
        return h.read_regular(os.path.join(run_dir, rel))
    except (OSError, ValueError):
        return None


def _first_diff(got, want):
    for i in range(min(len(got), len(want))):
        if got[i] != want[i]:
            lo = max(0, i - 24)
            return "first difference at byte %d: got %r, expected %r" % (i, got[lo:i + 24], want[lo:i + 24])
    return "common prefix; got %d bytes, expected %d bytes" % (len(got), len(want))


# --- D1: restore_aquilon.py ------------------------------------------------------------------------------------------

def _restore_run(lib_bytes, manifest_bytes):
    run_dir, proc = _run([h.PYTHON, _restore(), "libaquilon.so", "vendor_release.manifest", "out/restored.so"],
                         {"libaquilon.so": lib_bytes, "vendor_release.manifest": manifest_bytes},
                         RESTORE_BUDGET, dirs=["out"])
    return proc, _output(run_dir, "out/restored.so")


@pytest.fixture(scope="session")
def elf_instances():
    return {spec["name"]: lib.generate_elf(spec["seed"], spec["variant"], spec["notes"]) for spec in lib.ELF_VARIANTS}


@pytest.mark.parametrize("variant", VARIANTS)
def test_D1_restore(variant, elf_instances):
    """An infected release build comes back byte-identical to the library its manifest certifies."""
    inst = elf_instances[variant]
    proc, restored = _restore_run(inst["infested"], inst["manifest"])
    assert proc.returncode == 0, "exit %r: %s" % (proc.returncode, proc.stderr[-400:])
    assert restored is not None, "wrote no regular file at OUTPUT_LIB"
    assert restored == inst["clean"], _first_diff(restored, inst["clean"])


def test_D1_passthrough_clean(elf_instances):
    """A library that already matches its manifest entry is copied through byte for byte."""
    inst = elf_instances[VARIANTS[0]]
    proc, out = _restore_run(inst["clean"], inst["manifest"])
    assert proc.returncode == 0 and out == inst["clean"], (
        "exit %r, %r bytes" % (proc.returncode, None if out is None else len(out)))


def test_D1_rejects_uncertified(elf_instances):
    """A result the manifest does not certify: exit non-zero and write no library (a program that is missing or
    empty rejects nothing)."""
    try:
        program = h.read_regular(_restore())
    except (OSError, ValueError):
        program = b""
    assert program.strip(), "tools/restore_aquilon.py is missing or empty"
    inst = elf_instances[VARIANTS[0]]
    manifest = bytearray(inst["manifest"])
    start = manifest.rfind(b"libaquilon.so ")
    entry = manifest[start:].split(b" ", 2)
    manifest[start:] = entry[0] + b" " + entry[1] + b" " + b"0" * len(entry[2].strip()) + b"\n"
    proc, out = _restore_run(inst["infested"], bytes(manifest))
    assert proc.returncode != 0 and out is None, (
        "exit %r, output %r" % (proc.returncode, None if out is None else len(out)))


# --- D2: tcanon.py ---------------------------------------------------------------------------------------------------

def _tcanon_run(tdu):
    """tcanon.py's standard output, as bytes (a shell redirect into the run directory, as the agent UID)."""
    run_dir, proc = _run(["/bin/sh", "-c", 'exec "$0" "$1" input.tdu > out.tcanon', h.PYTHON, _tcanon()],
                         {"input.tdu": tdu}, TCANON_BUDGET)
    return proc, _output(run_dir, "out.tcanon")


def _probe(name):
    if name == "sample":
        return lib.generate(lib.VISIBLE_SEED, "visible")
    if name in NOTE_PROBES:
        tdu = b"\n".join(NOTE_PROBES[name]) + b"\n"
        return {"name": "probe-" + name, "tdu": tdu, "expected": lib.tcanon_reference(tdu)}
    return lib.probe_instance(name)


@pytest.fixture(scope="session")
def corpus():
    return {"hidden-%d" % seed: lib.generate(seed, "hidden") for seed in lib.CORPUS_SEEDS}


def _assert_stream(inst):
    proc, out = _tcanon_run(inst["tdu"])
    assert proc.returncode == 0, "exit %r: %s" % (proc.returncode, proc.stderr[-400:])
    assert out is not None, "standard output could not be read back"
    assert out == inst["expected"], _first_diff(out, inst["expected"])


@pytest.mark.parametrize("name", CORPUS)
def test_D2_unload(name, corpus):
    """An unseen .tdu v4 unload: the whole TCANON v2 stream, byte for byte (one hidden unload is empty)."""
    _assert_stream(corpus[name])


@pytest.mark.parametrize("name", PROBES)
def test_D2_probe(name):
    """A probe unload (the seed's one-rule probes, the shipped sample, and the NOTE probes): the whole stream."""
    _assert_stream(_probe(name))


# --- D2: one fact at a time ------------------------------------------------------------------------------------------
# Data rows are the lines that do not start with '#'. A row's NOTE starts at its first '|"' when it is quoted (dates,
# numbers and meter ids never hold a quote), is empty when the row ends with '|', and starts after the sixth '|'
# otherwise; the fields before it are read from both ends (PERIOD, ACCT and METER_ID first; USAGE_KWH, RATE and
# CHARGE last), so a column too many does not shift them.

def _data_rows(stream):
    return [line for line in stream.split(b"\n") if line and not line.startswith(b"#")]


def _split(row):
    i = row.find(b'|"')
    if i >= 0:
        return row[:i].split(b"|"), row[i + 1:]
    if row.endswith(b"|"):  # an unquoted empty NOTE
        return row[:-1].split(b"|"), b""
    parts = row.split(b"|")
    return parts[:6], b"|".join(parts[6:])


def _note_text(note):
    """A NOTE's text: unquoted and undoubled when quoted. NULL and empty both read as empty here."""
    if len(note) >= 2 and note[:1] == note[-1:] == b'"':
        return note[1:-1].replace(b'""', b'"')
    return note


def _fields(row):
    head, note = _split(row)
    return {"head": b"|".join(head), "period": head[0], "acct": head[1] if len(head) > 1 else b"",
            "meter": head[2] if len(head) > 2 else b"", "numbers": tuple(head[-3:]), "charge": head[-1],
            "note": note, "text": _note_text(note)}


def _rows_view(*keys):
    return lambda stream: sorted(tuple(_fields(r)[k] for k in keys) for r in _data_rows(stream))


def _order_view(stream):
    return [_fields(r)["acct"] for r in _data_rows(stream)]


def _totals_view(stream):
    return [line for line in stream.split(b"\n") if line.startswith(b"#TOTAL")]


def _rows(name):
    return b"\n".join(NOTE_PROBES[name]) + b"\n"


_SORT_KEYS = [  # sort keys only: byte order and the Trellis collation agree on every meter id here
    b"01-MAR-24|9000000401|B2|10|1.000|0.1000|march b2 ten",
    b"01-FEB-24|9000000402|B2|9|2.000|0.1000|february",
    b"01-MAR-24|9000000403|A1|5|3.000|0.1000|march a1",
    b"01-MAR-24|9000000404|B2|9|4.000|0.1000|march b2 nine",
    b"01-MAR-24|9000000405|B2|10|5.000|0.1000|march b2 ten again",
]


def _sample():
    return lib.generate(lib.VISIBLE_SEED, "visible")["tdu"]


# fact id -> (input, view): the view of tcanon.py's stream that the fact alone decides.
FACT_VIEWS = {
    "a2": (lambda: lib.probe_instance("period_pivot")["tdu"], _rows_view("period", "acct")),
    "a3": (lambda: _rows("note_null"), _rows_view("acct", "text")),
    "a4": (lambda: _rows("note_padding"), _rows_view("period", "acct", "meter", "numbers", "text")),
    "a5": (lambda: _rows("note_charset"), _rows_view("acct", "text")),
    "a6": (lambda: lib.probe_instance("number_half_cent")["tdu"], _rows_view("acct", "charge")),
    "a7": (lambda: b"\n".join(lib._accumulation_rows()) + b"\n", _totals_view),
    "b3": (lambda: b"", lambda stream: stream),
    "b4": (_sample, _rows_view("head")),
    "b5": (lambda: b"\n".join(_SORT_KEYS) + b"\n", _order_view),
    "b6": (lambda: lib.probe_instance("order_collation")["tdu"], _order_view),
    "b7": (lambda: _rows("note_quotes"), _rows_view("acct", "note")),
    "b8": (lambda: _rows("note_cut"), _rows_view("acct", "text")),
    "b9": (_sample, _totals_view),
}


@pytest.mark.parametrize("fact", sorted(FACT_VIEWS))
def test_D2_fact(fact):
    """What one fact decides, on an input that exercises it, read alone from the stream."""
    make, view = FACT_VIEWS[fact]
    tdu = make()
    proc, out = _tcanon_run(tdu)
    assert proc.returncode == 0, "exit %r: %s" % (proc.returncode, proc.stderr[-400:])
    assert out is not None, "standard output could not be read back"
    got, want = view(out), view(lib.tcanon_reference(tdu))
    assert got == want, "%r, expected %r" % (got[:6], want[:6])
