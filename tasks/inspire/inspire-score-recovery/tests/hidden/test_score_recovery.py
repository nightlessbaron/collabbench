"""Hidden tests for inspire-score-recovery, adapted from the seed task's tests/test_outputs.py
(llm360-cre-score-recovery-goal-0010).

The checks and the reference (crelib) are the seed's. What changed for CollabBench:
- the programs live in the workspace and run from a root-owned, read-only copy of it, with the verifier's Python;
  grading as root, they run as the task's dedicated unprivileged UID (tests/agent_uid), cannot read or change the
  tests, and nothing they start outlives the run (harness.py, as the seed's verifier did);
- the seed's one reader test over its 20 unseen bundles is one test per bundle, named by the bundle's family (the
  seed generator's category, seed % 5): accidentals, keys, ties, rarities, combined;
- the delivered /workspace/out files are checked against the visible corpus as the environment shipped it
  (visible_corpus.json), not against whatever corpus the workspace holds at grading time;
- a program that times out fails its tests instead of the whole session, and each program has a timeout budget
  (harness.run_agent): once read_score.py has lost 240 s, or build_catalog.py 300 s, to timeouts, its remaining runs
  fail unstarted, so one hanging program cannot push the whole score past the kit's 900 s. build_catalog runs get
  300 s each (the seed allowed 600; the instruction asks for 180 on a corpus of the same size).
Test names carry the deliverable: test_D1_* grade read_score.py, test_D2_* build_catalog.py and /workspace/out,
test_D3_* /workspace/publish.
"""

import json
import os
import sqlite3
import subprocess
from pathlib import Path

import pytest

import crelib as cre
import harness as h

HERE = Path(__file__).resolve().parent
FAMILIES = {0: "accidentals", 1: "keys", 2: "ties", 3: "rarities", 4: "combined"}
READ_SEEDS = list(range(9001, 9021))
READ_IDS = ["%s-%d" % (FAMILIES[seed % 5], seed) for seed in READ_SEEDS]
READ_TIMEOUT = 60
READ_BUDGET = ("read_score", 240.0)
BUILD_TIMEOUT = 300
BUILD_BUDGET = ("build_catalog", 300.0)

DELIVERED = {}


def _text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value or ""


@pytest.fixture(scope="session", autouse=True)
def _work():
    h.setup_work()
    # Capture the delivered visible artifacts now, before any graded run of the agents' programs: the unseen-corpus
    # runs of build_catalog are graded from their own output directories and must never change what counts as the
    # visible deliverable.
    for name in ("pairs.jsonl", "counts.json"):
        try:
            DELIVERED[name] = _text(h.read_regular(h.ws("out", name)))
        except Exception:  # noqa: BLE001
            DELIVERED[name] = None
    yield


def _run(argv, cwd, timeout, budget):
    try:
        return h.run_agent(argv, cwd=cwd, timeout=timeout, budget=budget)
    except subprocess.TimeoutExpired:
        return None


def _json(proc):
    return json.loads(_text(proc.stdout))


def _bytes_map(files):
    return {name: (value.encode("utf-8") if isinstance(value, str) else value) for name, value in files.items()}


def _open_db(path):
    data = h.read_regular(path)
    conn = sqlite3.connect(":memory:")
    conn.deserialize(data)
    return conn


def _columns(conn, table):
    return [(row[1], (row[2] or "").upper()) for row in conn.execute('PRAGMA table_info("%s")' % table)]


def _table_names(conn):
    return sorted(row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))


def _ok(proc):
    assert proc is not None, "timed out"
    assert proc.returncode == 0, _text(proc.stderr)[-800:]


# ---------------------------------------------------------------------------
# D1: the reader on unseen bundles, one test per bundle
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def score_runs():
    runs = {}
    for seed in READ_SEEDS:
        instance = cre.generate_instance("hidden", seed)
        run_dir = h.fresh_run_dir(_bytes_map(instance["files"]))
        proc = _run([h.PYTHON, h.ws("read_score.py"), run_dir], run_dir, READ_TIMEOUT, READ_BUDGET)
        runs[seed] = (proc, instance["expected"])
    return runs


@pytest.mark.parametrize("key", READ_IDS)
def test_D1_read_score(key, score_runs):
    """read_score prints the canonical notation for an unseen bundle."""
    proc, expected = score_runs[int(key.rsplit("-", 1)[1])]
    _ok(proc)
    try:
        got = _json(proc)
    except Exception as exc:  # noqa: BLE001
        raise AssertionError("printed invalid JSON: %s" % exc)
    assert got == expected, "notation differs"


# ---------------------------------------------------------------------------
# D2: the end-to-end pipeline on an unseen corpus, and the delivered visible output
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def hidden_run():
    corpus = cre.build_corpus(8101, "hidden")
    run_dir = h.fresh_run_dir(_bytes_map(corpus["files"]))
    proc = _run([h.PYTHON, h.ws("build_catalog.py"), run_dir], run_dir, BUILD_TIMEOUT, BUILD_BUDGET)
    return {"dir": run_dir, "proc": proc, "corpus": corpus}


def test_D2_build_catalog_notation(hidden_run):
    """build_catalog writes canonical notation for every unseen bundle."""
    _ok(hidden_run["proc"])
    out = os.path.join(hidden_run["dir"], "out")
    for work_id, expected in hidden_run["corpus"]["notation"].items():
        got = h.read_json(os.path.join(out, "notation", work_id + ".json"))
        assert got == expected, "notation differs for %s" % work_id


def test_D2_build_catalog_datastores(hidden_run):
    """Both datastores have exactly the manifest schema and the seeded rows."""
    _ok(hidden_run["proc"])
    out = os.path.join(hidden_run["dir"], "out")
    corpus = hidden_run["corpus"]

    reference = _open_db(os.path.join(out, "reference.db"))
    submission = _open_db(os.path.join(out, "submission.db"))

    assert _table_names(reference) == ["references"]
    assert _table_names(submission) == ["feed_items", "submissions"]

    score_columns = [("work_id", "TEXT"), ("title", "TEXT"), ("composer", "TEXT"), ("fifths", "INTEGER"),
                     ("mode", "TEXT"), ("incipit", "TEXT"), ("note_count", "INTEGER")]
    assert _columns(reference, "references") == score_columns
    assert _columns(submission, "submissions") == score_columns
    assert _columns(submission, "feed_items") == [("item_id", "TEXT"), ("work_id", "TEXT"), ("title", "TEXT"),
                                                  ("submitted_at", "TEXT")]

    ref_rows = {row[0]: row[1:] for row in reference.execute(
        'SELECT work_id, title, composer, fifths, mode, incipit, note_count FROM "references"')}
    assert set(ref_rows) == set(corpus["references"])
    for work_id, expected in corpus["references"].items():
        assert ref_rows[work_id] == (expected["title"], expected["composer"], expected["fifths"], expected["mode"],
                                     expected["incipit"], expected["note_count"])

    sub_rows = {row[0]: row[1:] for row in submission.execute(
        'SELECT work_id, title, composer, fifths, mode, incipit, note_count FROM "submissions"')}
    assert set(sub_rows) == set(corpus["submissions"])
    for work_id, expected in corpus["submissions"].items():
        assert sub_rows[work_id] == (expected["title"], expected["composer"], expected["fifths"], expected["mode"],
                                     expected["incipit"], expected["note_count"])


def test_D2_build_catalog_counts(hidden_run):
    """counts.json matches the feed's own totals and the exactly-once ingest."""
    _ok(hidden_run["proc"])
    out = os.path.join(hidden_run["dir"], "out")
    assert h.read_json(os.path.join(out, "counts.json")) == hidden_run["corpus"]["counts"]

    submission = _open_db(os.path.join(out, "submission.db"))
    item_ids = {row[0] for row in submission.execute('SELECT item_id FROM "feed_items"')}
    assert len(item_ids) == submission.execute('SELECT COUNT(*) FROM "feed_items"').fetchone()[0]
    _, expected_items, _ = cre.feed_expectations(hidden_run["corpus"]["pages"],
                                                 hidden_run["corpus"]["feed_index"]["cutoff"])
    assert item_ids == set(expected_items)


def test_D2_build_catalog_pairs(hidden_run):
    """pairs.jsonl is the exact candidate set, once each, in canonical order."""
    _ok(hidden_run["proc"])
    out = os.path.join(hidden_run["dir"], "out")
    lines = [line for line in h.read_text(os.path.join(out, "pairs.jsonl")).splitlines() if line.strip()]
    got = [json.loads(line) for line in lines]
    expected = [{"reference": ref, "submission": sub} for ref, sub in hidden_run["corpus"]["pairs"]]
    assert got == expected


def test_D2_reset_restores_seeded_state():
    """--reset recreates the datastores with the seed rows and no feed rows."""
    corpus = cre.build_corpus(8102, "hidden")
    run_dir = h.fresh_run_dir(_bytes_map(corpus["files"]))
    _ok(_run([h.PYTHON, h.ws("build_catalog.py"), run_dir], run_dir, BUILD_TIMEOUT, BUILD_BUDGET))
    _ok(_run([h.PYTHON, h.ws("build_catalog.py"), "--reset", run_dir], run_dir, BUILD_TIMEOUT, BUILD_BUDGET))
    out = os.path.join(run_dir, "out")
    reference = _open_db(os.path.join(out, "reference.db"))
    submission = _open_db(os.path.join(out, "submission.db"))
    assert {row[0] for row in reference.execute('SELECT work_id FROM "references"')} == set(corpus["references"])
    assert {row[0] for row in submission.execute('SELECT work_id FROM "submissions"')} == set(corpus["submissions"])
    assert submission.execute('SELECT COUNT(*) FROM "feed_items"').fetchone()[0] == 0


def _visible_expected():
    files = json.loads((HERE / "visible_corpus.json").read_text())  # corpus/ as the environment shipped it
    bundles = []
    for path, meta_text in files.items():
        parts = path.split("/")
        if len(parts) != 3 or parts[2] != "score.meta.json" or parts[0] not in ("reference", "submissions"):
            continue
        svg_text = files.get("%s/%s/score.svg" % (parts[0], parts[1]))
        if svg_text is not None:
            bundles.append((parts[0], parts[1], meta_text, svg_text))
    catalog = cre.catalog_from_bundle_texts(bundles)
    index = json.loads(files["feed/feed_index.json"])
    pages = [json.loads(text) for path, text in sorted(files.items())
             if path.startswith("feed/page-") and path.endswith(".json")]
    counts, _, _ = cre.feed_expectations(pages, index["cutoff"])
    return catalog, counts


def test_D2_visible_out_matches_corpus():
    """The delivered visible pairs and counts match the corpus's real catalog."""
    catalog, counts = _visible_expected()
    pairs_text = DELIVERED.get("pairs.jsonl")
    counts_text = DELIVERED.get("counts.json")
    assert pairs_text is not None, "no delivered /workspace/out/pairs.jsonl"
    assert counts_text is not None, "no delivered /workspace/out/counts.json"
    got = [json.loads(line) for line in pairs_text.splitlines() if line.strip()]
    expected = [{"reference": ref, "submission": sub} for ref, sub in catalog["pairs"]]
    assert got == expected, "delivered pairs differ from the corpus's candidate set"
    assert json.loads(counts_text) == counts, "delivered counts differ"


# ---------------------------------------------------------------------------
# D3: publishing
# ---------------------------------------------------------------------------

FORBIDDEN = [
    "sourceMappingURL", "VENDOR_TOKEN", "sk-vendor", "internal.cre-exchange", "PRIVATE IMPLEMENTATION NOTE",
    "LICENSED-FIXTURE", "licence_rate", "per_publisher_licence", "0.0125", "0.0090", "0.0140", "emb-001", "emb-002",
    "Hollow Vale Ballad", "Glass Harbor Air",
]


def _all_files(root):
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if not os.path.islink(os.path.join(dirpath, d))]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if not os.path.islink(path):
                yield path


def test_D3_publish_has_no_sensitive_content():
    """Nothing shipped carries a source map, endpoint, token, note or fixture, and the tree holds files, not links
    (the seed failed any symlink in the agent's files; the graded copy drops them, so they are failed here)."""
    root = h.ws("publish")
    assert os.path.isdir(root), "no published tree"
    assert not h.skipped("publish"), "not regular files: %s" % ", ".join(h.skipped("publish"))
    published = {path: _text(h.read_regular(path)) for path in _all_files(root)}
    rel = {os.path.relpath(path, root) for path in published}
    assert "data_bundle.json" in rel, "no published data bundle"
    assert "toolkit/__init__.py" in rel, "no published toolkit package"
    assert "toolkit/titles.py" in rel, "no published toolkit module"
    hits = []
    for path, body in published.items():
        if path.endswith(".map"):
            hits.append("%s: source map" % path)
        for marker in FORBIDDEN:
            if marker in body:
                hits.append("%s: %s" % (path, marker))
    assert not hits, "\n".join(hits)


def test_D3_publish_toolkit_still_works():
    """The scrubbed toolkit keeps its public contract."""
    assert os.path.isdir(h.ws("publish")), "no published tree"
    proc = _run([h.PYTHON, "-m", "toolkit.selftest"], h.ws("publish"), 30, None)
    _ok(proc)
    assert "SELFTEST OK" in _text(proc.stdout)


def test_D3_publish_data_bundle_schema():
    """The title bundle keeps the public titles and drops the embargoed ones."""
    bundle = h.read_json(h.ws("publish", "data_bundle.json"))
    assert set(bundle) == {"bundle_version", "titles"}
    assert bundle["bundle_version"] == 1
    titles = bundle["titles"]
    assert isinstance(titles, list)
    for entry in titles:
        assert set(entry) == {"work_id", "title", "publisher"}
    assert {entry["work_id"] for entry in titles} == {"wrk-001", "wrk-002", "wrk-003", "wrk-004", "wrk-005"}
    by_id = {entry["work_id"]: entry for entry in titles}
    assert by_id["wrk-001"]["title"] == "Aurora Suite"
    assert by_id["wrk-002"]["publisher"] == "Tamsin Music"
