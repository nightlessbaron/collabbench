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
import tomllib
from pathlib import Path

import pytest

from collabbench.taskfmt.localcheck import score_locally
from collabbench.tracks.inspire import real
from collabbench.tracks.inspire.real import cif_canon, score_recovery

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
    try:
        spec = importlib.util.spec_from_file_location(f"score_{d.name.replace('-', '_')}", tests / "score.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(tests))
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
    assert reference["extras"]["hint_capture"] == 1.0
    start = score_locally(d, "start")
    assert start["reward"] <= 0.05 and not any(start["requirements"].values())
    assert set(start["requirements"]) == {*load_score_module(d).DELIVERABLES, "GAP"}


# --- gates and attribution ------------------------------------------------------------------------------------------

def test_shortcuts_fail_the_gate(task, tmp_path, capsys):
    """The seed's red-team shortcuts each scored 0 there. Here a shortcut may earn partial credit on what it does get
    right, but it never passes every test, never meets req_GAP, and stays well below the reference."""
    builder, d = task
    names = sorted(p.name for p in (d / "shortcuts").iterdir())
    assert names == sorted(builder.SHORTCUTS)
    rewards = {}
    for name in names:
        r = apply_and_score(d, f'bash "$TASK/shortcuts/{name}/solve.sh"', tmp_path, name)
        rewards[name] = round(r["reward"], 3)
        assert r["extras"]["all_pass"] == 0.0 and r["requirements"]["GAP"] is False, name
        assert r["reward"] <= 0.7, (name, r["reward"])
    with capsys.disabled():
        print(f"\n{d.name} shortcut rewards: {rewards}")


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
    assert gap <= failed(r) and r["extras"]["hint_capture"] == 0.0
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
    """The reference with read_score.py replaced by the shipped reference reader under one of its alternative rules."""
    return f'''bash "$TASK/solution/solve.sh"
cp "$TASK/tests/hidden/crelib.py" "$WORKSPACE/_crelib.py"
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
