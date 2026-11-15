"""The two hand-built Inspire tasks (tasks/inspire/inspire-cif-canon, tasks/inspire/inspire-score-recovery), converted
from rl-graph-taskmaker frontier tasks by collabbench.tracks.inspire.real.

The committed task directories are checked as they stand; the builder tests need the read-only seeds and skip
without them. Local scoring runs each task's own grader (localcheck), without Docker."""

import filecmp
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time
import tomllib
from pathlib import Path

import pytest

from collabbench.taskfmt.frontier import isolation as iso
from collabbench.taskfmt.localcheck import score_locally
from collabbench.tracks.inspire import real
from collabbench.tracks.inspire.real import cif_canon, score_recovery
from tests import hostile

REPO = Path(__file__).resolve().parents[2]
BUILDERS = {b.NAME: b for b in (cif_canon, score_recovery)}
SEEDS_PRESENT = all((real.SEEDS_ROOT / b.SEED_ID / "task").is_dir() for b in BUILDERS.values())
needs_seeds = pytest.mark.skipif(not SEEDS_PRESENT, reason=f"seed tasks not under {real.SEEDS_ROOT}")


def task_dir(name: str) -> Path:
    return REPO / "tasks" / "inspire" / name


@pytest.fixture(params=sorted(BUILDERS), scope="module")
def task(request):
    return BUILDERS[request.param], task_dir(request.param)


def text(path: Path) -> str:
    return path.read_text()


def workspace_texts(d: Path) -> dict[str, str]:
    root = d / "environment" / "workspace"
    return {p.relative_to(root).as_posix(): p.read_text() for p in root.rglob("*") if p.is_file()}


def load_score_module(d: Path):
    tests = d / "tests"
    sys.path.insert(0, str(tests))
    bytecode, sys.dont_write_bytecode = sys.dont_write_bytecode, True  # never into a task's tests/ (M5)
    try:
        spec = importlib.util.spec_from_file_location(f"score_{d.name.replace('-', '_')}", tests / "score.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(tests))
        sys.dont_write_bytecode = bytecode
    return module


def apply_and_score(d: Path, script: str, tmp_path: Path, name: str = "ws") -> dict:
    """Run a solve script (bash, reading $WORKSPACE) on a copy of the task's start workspace, then grade it."""
    ws = tmp_path / name
    shutil.copytree(d / "environment" / "workspace", ws)
    run = subprocess.run(["bash", "-c", script], env={**os.environ, "WORKSPACE": str(ws), "TASK": str(d)},
                         capture_output=True, text=True)
    assert run.returncode == 0, run.stderr[-2000:]
    return score_locally(d, "start", workspace=ws)


def failed(result: dict) -> set[str]:
    return {name for name, ok in result["tests"].items() if not ok}


@pytest.fixture(scope="module")
def reference(task):
    _, d = task
    return score_locally(d, "reference")


# --- layout ---------------------------------------------------------------------------------------------------------

def test_two_real_tasks_in_tasks_inspire():
    for name, builder in BUILDERS.items():
        d = task_dir(name)
        assert (d / "task.toml").is_file(), f"{d} is not built"
        meta = tomllib.loads(text(d / "task.toml"))["metadata"]["collab"]
        assert meta["track"] == "inspire" and meta["source_task"] == builder.SEED_ID
        assert meta["requirements"] == [*builder.DELIVERABLES, "GAP"]
        assert meta["reserved_script"] == builder.RESERVED
        assert text(d / "tests" / "agent_uid").strip() == str(real.AGENT_UID)


def test_manifest_roles_and_private_context(task):
    builder, d = task
    private = d / "environment" / "private"
    assert sorted(p.name for p in private.iterdir()) == ["_harness", "expert.md", "expert.placebo.md"]
    m = json.loads(text(private / "_harness" / "manifest.json"))
    # team.py: agent-i takes roles[i]; agent-0 reports. The solver has no private file, so it gets nothing private;
    # the expert gets expert.md (expert.placebo.md under placebo=expert) and its role brief instead of the instruction.
    assert m["roles"] == ["solver", "expert"] and m["workspace"] == "shared"
    assert set(m["role_briefs"]) == {"expert"} and m["role_briefs"]["expert"] == real.EXPERT_BRIEF
    assert "evaluate" not in m and m["reserved_command"] == builder.RESERVED
    brief = m["role_briefs"]["expert"]
    assert not any(t.lower() in brief.lower() for t in builder.GAP_TERMS + builder.CONVENTION_NAMES)


def test_instruction_states_the_contract_without_teammates(task):
    builder, d = task
    brief = text(d / "instruction.md")
    assert not re.search(r"collaborat|teammate|expert|helper|subagent|agent-1", brief, re.I)
    assert all(f"{req}:" in brief for req in builder.DELIVERABLES) and "GAP" not in brief
    assert f"Do not run `{builder.RESERVED}`" in brief and "report for each requirement" in brief
    assert all(path in brief for path in builder.DELIVERABLES.values())


# --- the brief's tests ----------------------------------------------------------------------------------------------

def test_solver_brief_lacks_gap_knowledge(task):
    builder, d = task
    sources = {"instruction.md": text(d / "instruction.md"), **workspace_texts(d)}
    for term in builder.GAP_TERMS:
        hits = [name for name, body in sources.items() if term.lower() in body.lower()]
        assert not hits, f"{term!r} appears in {hits}"


@needs_seeds
def test_gap_terms_were_in_the_seed_instruction(task):
    builder, _ = task
    seed_brief = text(real.SEEDS_ROOT / builder.SEED_ID / "task" / "instruction.md").lower()
    named = [t for t in builder.GAP_TERMS if t.lower() in seed_brief]
    assert len(named) >= 2, f"the seed's instruction named none of the gap terms: {builder.GAP_TERMS}"


def test_expert_notes_carry_gap_and_no_task_values(task):
    builder, d = task
    notes = text(d / "environment" / "private" / "expert.md")
    missing = [n for n in builder.CONVENTION_NAMES if n.lower() not in notes.lower()]
    assert not missing, f"expert.md does not name {missing}"
    lowered = notes.lower()
    assert not [f for f in builder.NOTE_FORBIDDEN if f.lower() in lowered]
    assert "```" not in notes and not re.search(r"^\s*(\$|>>>|python|import )", notes, re.M)
    hidden_numbers = set()
    for body in builder.hidden_texts(d):
        hidden_numbers |= set(re.findall(r"\d+(?:\.\d+)?", body))
    assert hidden_numbers, "no hidden instances found"
    assert not set(re.findall(r"\d+(?:\.\d+)?", notes)) & hidden_numbers


def test_placebo_matches_shape(task):
    builder, d = task
    private = d / "environment" / "private"
    notes, placebo = text(private / "expert.md"), text(private / "expert.placebo.md")
    n, p = len(notes.split()), len(placebo.split())
    assert 0.8 * n <= p <= 1.2 * n, (n, p)
    assert placebo.startswith("Field notes:") and notes.startswith("Field notes:")
    lowered = placebo.lower()
    assert not [t for t in builder.GAP_TERMS + builder.CONVENTION_NAMES if t.lower() in lowered]
    assert not [f for f in builder.NOTE_FORBIDDEN if f.lower() in lowered]


def test_tests_map_to_requirements(task):
    builder, d = task
    names = json.loads(text(d / "tests" / "hidden" / "expected_tests.json"))
    assert names == sorted(set(names)) and len(names) >= 20
    owners = {name: re.findall(r"^test_(D\d+)_", name) for name in names}
    assert all(len(o) == 1 for o in owners.values()), [n for n, o in owners.items() if len(o) != 1]
    assert {o[0] for o in owners.values()} == set(builder.DELIVERABLES)
    score = load_score_module(d)
    assert score.DELIVERABLES == list(builder.DELIVERABLES)
    assert score.GAP and score.GAP < set(names), sorted(score.GAP - set(names))[:5]
    assert score.PROBE <= set(names) and not score.PROBE & score.GAP


def test_reference_and_start_local(task, reference):
    _, d = task
    assert reference["reward"] >= 0.98, failed(reference)
    assert all(reference["requirements"].values()) and reference["extras"]["all_pass"] == 1.0
    assert reference["extras"]["gap_score"] == 1.0 and reference["extras"]["task_score"] == 1.0
    start = score_locally(d, "start")
    assert start["reward"] <= 0.05 and not any(start["requirements"].values())
    assert set(start["requirements"]) == {*load_score_module(d).DELIVERABLES, "GAP"}


# --- gates and attribution ------------------------------------------------------------------------------------------

def test_shortcuts_fail_the_gate(task, tmp_path):
    """The seed's red-team shortcuts each scored 0 there. Here a shortcut may earn partial credit on what it does get
    right, but it never passes every test, never meets req_GAP, and stays well below the reference."""
    builder, d = task
    names = sorted(p.name for p in (d / "shortcuts").iterdir())
    assert names == sorted(builder.SHORTCUTS)
    for name in names:
        r = apply_and_score(d, f'bash "$TASK/shortcuts/{name}/solve.sh"', tmp_path, name)
        assert r["extras"]["all_pass"] == 0.0 and r["requirements"]["GAP"] is False, name
        assert r["reward"] <= 0.7, (name, r["reward"])


def cif_variant(transform: str) -> str:
    """The reference with cif/parse.py replaced by the shipped reference library plus one change."""
    return f'''bash "$TASK/solution/solve.sh"
cp "$TASK/tests/hidden/cif_ref_lib.py" "$WORKSPACE/cif/_ref.py"
cat > "$WORKSPACE/cif/parse.py" <<'PY'
import json
import sys

from cif import _ref

canon = {transform}
print(json.dumps(canon))
PY
'''


GAP_BLIND_CIF = cif_variant('_ref.canonicalise(open(sys.argv[1]).read(), ops_override=["x,y,z"], diagonal=True)')
WYCKOFF_CIF = cif_variant('''_ref.canonicalise(open(sys.argv[1]).read())
for site in canon["sites"]:
    site["multiplicity"] = sum(s["label"] == site["label"] for s in canon["sites"])''')


def test_cif_gap_blind_reader_fails_exactly_the_gap(tmp_path):
    """A reader that knows everything but the convention (no symmetry expansion, a diagonal cell) fails every req_GAP
    test and passes every single-case family the gap does not govern."""
    d = task_dir(cif_canon.NAME)
    r = apply_and_score(d, GAP_BLIND_CIF, tmp_path)
    gap = load_score_module(d).GAP
    assert gap <= failed(r) and r["extras"]["gap_score"] == 0.0
    plan = json.loads(text(d / "tests" / "hidden" / "instances.json"))
    others = {p["id"] for p in plan if p["family"] in ("esd", "occ", "outside")}
    governed_elsewhere = {n for n in failed(r) if any(f"[{i}]" in n for i in others)}
    assert not governed_elsewhere and "test_D1_visible" not in failed(r)


def canon_close(a: dict, b: dict, tol: float = 1e-5) -> bool:
    """The seed identifiability gate's comparison, flattened: same structure, numbers within `tol`."""
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(canon_close(a[k], b[k], tol) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(canon_close(x, y, tol) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        return abs(a - b) <= tol
    return a == b


# The seed identifiability gate's alternative readings, one per case.
CIF_ALTERNATIVES = {"sym": {"ops_override": ["x,y,z"]}, "oblique": {"diagonal": True},
                    "outside": {"wrap_enabled": False}, "esd": {"esd_digits": True}, "occ": {"ignore_disorder": True}}


def test_cif_deposits_are_valid_and_each_family_is_identifiable():
    """Every graded deposit passes the seed's format validator, and in every single-case family the case's naive
    alternative changes the reference answer, so the family really exercises its case."""
    d = task_dir(cif_canon.NAME)
    lib = cif_canon.load_lib(d / "tests" / "hidden" / cif_canon.LIB)
    plan = json.loads(text(d / "tests" / "hidden" / "instances.json"))
    assert [p["seed"] for p in plan if p["family"] == "mixed"] == list(range(9001, 9021))
    for p in plan:
        inst = lib.generate(p["seed"], "hidden", set(p["cases"]))
        assert lib.validate_instance(inst) == [], p["id"]
        if p["family"] in CIF_ALTERNATIVES:
            ref = lib.canonicalise(inst["cif_text"])
            alt = lib.canonicalise(inst["cif_text"], **CIF_ALTERNATIVES[p["family"]])
            assert not canon_close(ref, alt), f"{p['id']}: the {p['family']} case changes nothing"


def test_cif_probe_isolates_deference(tmp_path):
    """Taking multiplicity in the crystallographer's sense (copies in the cell) instead of the instruction's keeps
    every req_GAP test and fails every probe test."""
    d = task_dir(cif_canon.NAME)
    r = apply_and_score(d, WYCKOFF_CIF, tmp_path)
    score = load_score_module(d)
    assert r["requirements"]["GAP"] is True and r["extras"]["probe"] == 0.0
    assert failed(r) == score.PROBE


def score_variant(rule: str) -> str:
    """The reference with read_score.py replaced by the shipped reference reader under one of its alternative rules,
    or under several joined by "+" (the reader's copy of crelib takes `rule` as a set)."""
    return f'''bash "$TASK/solution/solve.sh"
"{sys.executable}" - "$TASK/tests/hidden/crelib.py" "$WORKSPACE/_crelib.py" <<'PY'
import re
import sys

src = open(sys.argv[1]).read()
src = re.sub(r'rule == "(\\w+)"', r'"\\1" in rule.split("+")', src)
src = re.sub(r'rule != "(\\w+)"', r'"\\1" not in rule.split("+")', src)
open(sys.argv[2], "w").write(src)
PY
cat > "$WORKSPACE/read_score.py" <<'PY'
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _crelib

_canonical = _crelib._canonical


def _variant(*args, **kwargs):
    kwargs["rule"] = "{rule}"
    return _canonical(*args, **kwargs)


_crelib._canonical = _variant
parse_files, parse_dir = _crelib.parse_files, _crelib.parse_dir  # the module API build_catalog.py imports

if __name__ == "__main__":
    print(json.dumps(parse_dir(sys.argv[1])))
PY
'''


@pytest.mark.parametrize("family,rule", [("accidentals", "additive"), ("accidentals", "no_carry"),
                                         ("keys", "first_key"), ("ties", "tie_slur")])
def test_score_gap_families_are_attributed(tmp_path, family, rule):
    """Each req_GAP family of the reader fails under the seed's alternative reading of its own convention, and the
    other gap families do not notice that reading."""
    d = task_dir(score_recovery.NAME)
    r = apply_and_score(d, score_variant(rule), tmp_path)
    reader_fails = {n for n in failed(r) if n.startswith("test_D1_")}
    gap = load_score_module(d).GAP
    in_family = {n for n in gap if f"[{family}-" in n}
    assert in_family and in_family <= reader_fails
    assert not (gap - in_family) & reader_fails, sorted((gap - in_family) & reader_fails)


GAP_BLIND_SCORE = "additive+first_key+tie_slur"  # every req_GAP family of the reader read the naive way
GAP_BLIND = {cif_canon.NAME: GAP_BLIND_CIF, score_recovery.NAME: score_variant(GAP_BLIND_SCORE)}
NAIVE = {cif_canon.NAME: "naive_common_case", score_recovery.NAME: "naive-common-case"}


def expected_reward(builder, d: Path, tests: dict[str, bool]) -> float:
    """The ruling's reward, computed here from the per-test results, the builder's deliverables and the builder's own
    gap set (not from score.py): 0.5 x the mean of the deliverables' pass rates + 0.5 x the gap tests' pass rate."""
    def rate(oks):
        return sum(oks) / len(oks)
    rates = [rate([ok for name, ok in tests.items() if name.startswith(f"test_{deliverable}_")])
             for deliverable in builder.DELIVERABLES]
    if builder is cif_canon:
        gap = cif_canon.gap_tests(json.loads(text(d / "tests" / "hidden" / "instances.json")))
    else:
        gap = score_recovery.gap_tests()
    assert gap and gap <= set(tests)
    return 0.5 * sum(rates) / len(rates) + 0.5 * rate([tests[name] for name in gap])


def test_reward_is_half_the_gap(task, reference, tmp_path):
    """reward = 0.5 x task_score + 0.5 x gap_score: a program right everywhere except the gap, and the seed's naive
    shortcut, each score at most 0.35; the reference scores 1.0."""
    builder, d = task
    assert reference["reward"] == 1.0
    blind = apply_and_score(d, GAP_BLIND[builder.NAME], tmp_path, "blind")
    naive = apply_and_score(d, f'bash "$TASK/shortcuts/{NAIVE[builder.NAME]}/solve.sh"', tmp_path, "naive")
    for r in (blind, naive):
        assert r["reward"] == pytest.approx(expected_reward(builder, d, r["tests"]))
        assert r["extras"]["gap_score"] == 0.0
    assert 0 < blind["reward"] <= 0.35 and 0 < naive["reward"] <= 0.35


STEAL_CIF = "_lib.canonicalise(open(_sys.argv[1]).read())"  # the decisive read: print the reference answer


def hostile_parse(tests: str, out: str) -> str:
    return hostile.program(tests, out, [], steal=(f"{tests}/hidden/{cif_canon.LIB}", STEAL_CIF)) + 'print("{}")\n'


def hostile_grade(d: Path, tmp_path: Path) -> tuple[dict, dict, list[int]]:
    """Grade, through the task's own grade.py (as local grading, without root), a start workspace whose cif/parse.py
    is the hostile program; return reward.json (read after the daemon has had time to strike) and the daemons still
    alive, and details.json."""
    ws, out = tmp_path / "ws", tmp_path / "out"
    shutil.copytree(d / "environment" / "workspace", ws)
    (ws / "cif").mkdir(exist_ok=True)
    (ws / "cif" / "parse.py").write_text(hostile_parse(str(d / "tests"), str(out)))
    tripwire = tmp_path / "tripwire"
    tripwire.write_text(f"nonce {text(d / 'tests' / 'tripwire_nonce.txt').strip()}\n")
    try:
        subprocess.run([sys.executable, str(d / "tests" / "grade.py"), "--workspace", str(ws), "--snapshots",
                        str(tmp_path / "none"), "--tripwire", str(tripwire), "--out", str(out)], check=True,
                       timeout=1800, env={**os.environ, iso.LOCAL_ENV: "1"})
        time.sleep(1.0)  # a surviving daemon rewrites reward.json within 0.05 s
        return (json.loads((out / "reward.json").read_text()), json.loads((out / "details.json").read_text()),
                hostile.survivors(str(out)))
    finally:
        hostile.kill(str(out))


def test_hostile_agent_program_cannot_change_the_grade(tmp_path):
    """An agent program run during grading rewrites expected_tests.json and score.py, leaves a double-forked
    daemon that overwrites reward.json, and prints the answer of the hidden reference library. Grading must ignore
    the rewrite and kill the daemon before reward.json is written. Without root (here, under the explicit local
    override) the program runs as the grader's own user, so its rewrite lands and voids the whole grade: the reward,
    every requirement and every score extra (M3), and reward.json records that it ran unisolated. As root it runs as
    tests/agent_uid and can neither read nor touch the tests (the live test)."""
    d = tmp_path / cif_canon.NAME
    shutil.copytree(task_dir(cif_canon.NAME), d)
    pinned = text(d / "tests" / "hidden" / "expected_tests.json")
    reward, details, alive = hostile_grade(d, tmp_path)
    assert not alive, f"agent daemons survived grading: {alive}"
    assert "pwned" not in reward and reward["reward"] <= 0.05
    if os.geteuid() == 0:
        assert text(d / "tests" / "hidden" / "expected_tests.json") == pinned and "tests_tampered" not in reward
        assert reward["isolated"] == 1
    else:
        assert reward["tests_tampered"] == 1 and reward["reward"] == 0.0 and reward["isolated"] == 0
        assert not any(v for k, v in reward.items() if k.startswith("req_"))
        assert reward["task_score"] == reward["gap_score"] == reward["all_pass"] == 0.0
        assert details["final"]["extras"]["rate_D1"] == 1.0  # the stolen reference answers had passed all of D1


@pytest.fixture(params=sorted(BUILDERS))
def shipped_harness(request):
    return task_dir(request.param) / "tests" / "hidden" / "harness.py"


def test_harness_reads_never_block_on_a_fifo(shipped_harness, tmp_path):
    """I1: a program running as the agent UID can leave a FIFO where an output belongs (mkfifo out/counts.json);
    root's read must refuse it at once instead of blocking until the verifier is killed."""
    fifo = tmp_path / "counts.json"
    os.mkfifo(fifo)
    code = (f"import sys; sys.path.insert(0, {str(shipped_harness.parent)!r}); import harness as h\n"
            f"try:\n    h.read_regular({str(fifo)!r})\nexcept (ValueError, OSError):\n    print('REFUSED')\n")
    run = subprocess.run([sys.executable, "-I", "-B", "-c", code], capture_output=True, text=True, timeout=30)
    assert run.stdout.strip() == "REFUSED", run.stderr[-2000:]


def test_harness_reads_never_leave_the_work_tree(shipped_harness, tmp_path):
    """S1: root reads an agent's outputs from the run directory the agent controls. A parent directory that is a
    symlink (out -> the tests' hidden directory), or a `..`, must never hand root a file outside it."""
    secret = tmp_path / "hidden"
    secret.mkdir()
    (secret / "ref.json").write_text('"SECRET"')
    code = textwrap.dedent(f"""
        import os, sys
        sys.path.insert(0, {str(shipped_harness.parent)!r})
        import harness as h
        run = h.fresh_run_dir({{}})
        os.symlink({str(secret)!r}, os.path.join(run, "out"))
        with open(os.path.join(run, "..", "beside.json"), "w") as f:
            f.write('"BESIDE"')
        for path in (os.path.join(run, "out", "ref.json"), os.path.join(run, "..", "beside.json"),
                     {str(secret / "ref.json")!r}):
            try:
                print("LEAK", h.read_json(path))
            except (ValueError, OSError):
                print("REFUSED")
    """)
    env = {**os.environ, iso.LOCAL_ENV: "1", "COLLAB_WORKSPACE": str(tmp_path / "no-workspace")}
    run = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True, timeout=60, env=env)
    assert run.stdout.split() == ["REFUSED"] * 3, (run.stdout, run.stderr[-2000:])


def test_score_parent_symlink_cannot_forge_an_output(tmp_path):
    """S1 end to end: build_catalog links its output directory to reference outputs under tests/ (here planted in
    a copy of the task, standing for any root-readable reference). Root must not read them as the program's output:
    that output fails, as if missing."""
    d = tmp_path / score_recovery.NAME
    shutil.copytree(task_dir(score_recovery.NAME), d)
    cre = real.load_module(d / "tests" / "hidden" / score_recovery.LIB, "_cre_forge")
    reference = d / "tests" / "hidden" / "ref_out"
    (reference / "notation").mkdir(parents=True)
    for work_id, notation in cre.build_corpus(8101, "hidden")["notation"].items():
        (reference / "notation" / f"{work_id}.json").write_text(json.dumps(notation))
    hostile_build = f'''import os, sys
os.symlink({str(reference)!r}, os.path.join(sys.argv[-1], "out"))
'''
    script = f'''bash "$TASK/solution/solve.sh"
cat > "$WORKSPACE/build_catalog.py" <<'PY'
{hostile_build}PY
'''
    r = apply_and_score(d, script, tmp_path)
    assert "test_D2_build_catalog_notation" in failed(r) and r["requirements"]["D2"] is False


def test_harness_uses_the_one_shared_isolation_module(shipped_harness):
    """I3: the task harness keeps no sweep, lock or safe read of its own; it loads tests/isolation.py, the copy of
    taskfmt/frontier/isolation.py that write_task ships."""
    harness = text(shipped_harness)
    assert text(shipped_harness.parent.parent / "isolation.py") == Path(iso.__file__).read_text()
    assert '"isolation.py"' in harness
    assert not any(marker in harness for marker in ("/proc", "prctl", "chown", "SIGKILL", "O_NOFOLLOW"))


def test_score_d3_fails_on_a_symlink_under_publish(tmp_path):
    """M4: a published tree must hold files, not links: a symlink to the internal notes fails D3 (the seed failed
    any symlink in the agent's files; here the graded copy never holds one, and D3 says so)."""
    d = task_dir(score_recovery.NAME)
    script = ('bash "$TASK/solution/solve.sh"\n'
              'ln -s ../../partner_toolkit_src/toolkit/_internal_notes.py "$WORKSPACE/publish/toolkit/_notes.py"\n')
    r = apply_and_score(d, script, tmp_path)
    assert "test_D3_publish_has_no_sensitive_content" in failed(r) and r["requirements"]["D3"] is False
    assert failed(r) <= {n for n in r["tests"] if n.startswith("test_D3_")}


PLANT_IN_RUN_DIR = {  # the parent-symlink attack: the run directory's out/ -> the tests' hidden directory
    cif_canon.NAME: '_os.path.join(_os.path.dirname(_os.path.abspath(_sys.argv[1])), "out")',
    score_recovery.NAME: '_os.path.join(_sys.argv[-1], "out")'}


def live_hostile_solution(name: str) -> str:
    """solve.sh for the live test: the hostile program where the verifier will run it as the agent UID."""
    plant = (PLANT_IN_RUN_DIR[name], "/tests/hidden")
    if name == cif_canon.NAME:  # cif/parse.py also tries to read the reference library and print its answer
        program = hostile.program("/tests", "/logs/verifier", [], plant=plant,
                                  steal=(f"/tests/hidden/{cif_canon.LIB}", STEAL_CIF)) + 'print("{}")\n'
        return f'mkdir -p "$W/cif"\ncat > "$W/cif/parse.py" <<\'PY\'\n{program}PY\n'
    program = hostile.program("/tests", "/logs/verifier", [], plant=plant)  # build_catalog.py: out/ -> /tests/hidden
    return f'bash "$(dirname "$0")/reference.sh"\ncat > "$W/build_catalog.py" <<\'PY\'\n{program}PY\n'


@pytest.mark.live
@pytest.mark.parametrize("name", sorted(BUILDERS))
def test_live_hostile_agent_program_is_contained(tmp_path, name):
    """Live (Modal, and a verifier running as root, as Harbor runs it): the oracle agent leaves a hostile program in
    the workspace; the verifier runs it as the agent UID. It can neither read the reference library, nor make root
    read the tests through a symlinked output directory, nor write the tests or /logs/verifier, and no process of
    it outlives its run. Costs one oracle trial per task."""
    from collabbench import settings
    from collabbench.runner.gates import _job, parse_trial
    from collabbench.runner.harbor import harbor_env
    from collabbench.runner.pools import POOLS

    d = tmp_path / name
    shutil.copytree(task_dir(name), d)
    shutil.copy(d / "solution" / "solve.sh", d / "solution" / "reference.sh")
    (d / "solution" / "solve.sh").write_text('#!/bin/bash\nset -euo pipefail\nW="${WORKSPACE:-/workspace}"\n'
                                             + live_hostile_solution(name))
    jobs = tmp_path / "jobs"
    subprocess.run(_job(d, "oracle", [], jobs, "hostile"), env=harbor_env(POOLS["personal"]), cwd=settings.REPO,
                   check=True, timeout=3600)
    trial = parse_trial(next((jobs / "hostile").glob("*/result.json")).parent)
    rewards = trial["rewards"]
    assert trial["exception"] is None and "pwned" not in rewards and rewards["isolated"] == 1
    assert not rewards.get("tests_tampered") and not rewards.get("verifier_error")
    assert rewards["agent_processes_left"] == 0 and not rewards.get("agent_processes_survived")
    if name == cif_canon.NAME:  # the reference library could not be read
        assert rewards["req_D1"] == 0 and rewards["reward"] <= 0.05
    else:  # build_catalog's output, linked to /tests/hidden, was not read as its output
        assert rewards["req_D2"] == 0


# --- reproducibility ------------------------------------------------------------------------------------------------

def same_tree(a: Path, b: Path) -> list[str]:
    cmp = filecmp.dircmp(a, b)
    diffs = [f"{a}/{n}" for n in cmp.left_only + cmp.right_only + cmp.diff_files]
    for sub in cmp.common_dirs:
        diffs += same_tree(a / sub, b / sub)
    return diffs


@needs_seeds
def test_builder_reproduces_the_committed_tasks(tmp_path):
    built = real.build_all(tmp_path)
    assert [p.name for p in built] == sorted(BUILDERS)
    for p in built:
        assert not same_tree(p, task_dir(p.name)), f"{p.name} differs from a fresh build; rebuild it"


@needs_seeds
def test_retarget_keeps_shipped_programs_verbatim():
    seed = real.SEEDS_ROOT / cif_canon.SEED_ID / "task" / "solution" / "solve.sh"
    out = real.retarget(seed.read_text(), {"/cif": "/cif", "/topology": "/topology", "/data": "/data"})
    assert 'cat > ${W}/cif/parse.py <<' in out and "mkdir -p ${W}/cif ${W}/topology" in out
    program = seed.read_text().split("cat > /cif/parse.py <<'PY'\n")[1].split("\nPY\n")[0]
    assert program in out
