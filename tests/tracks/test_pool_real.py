"""The two hand-built Pool tasks (tasks/pool/pool-aquilon, tasks/pool/pool-pressproof), converted from
rl-graph-taskmaker frontier tasks by collabbench.tracks.pool.real.

The committed task directories are checked as they stand; builder tests need the read-only seeds and skip without
them. pool-aquilon's reference and hidden tests need only the standard library, so it is scored here (localcheck,
without Docker). pool-pressproof's need Pillow and scipy, which only its images install: its scoring tests (reference
and start, attribution, shortcuts) are `live` and run with COLLAB_TASK_PYTHON pointing at a Python that has the
images' numpy 2.2.6, Pillow 11.3.0, scipy 1.15.3 and PyYAML 6.0.2 (`-m live`)."""

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

from collabbench.metrics.integrity import disclosure_precision
from collabbench.metrics.trial import TrialRecord
from collabbench.taskfmt.frontier import build as frontier
from collabbench.taskfmt.frontier import isolation as iso
from collabbench.tracks.common import fact_disclosed
from collabbench.tracks.inspire import real as inspire_real
from collabbench.tracks.pool import real
from collabbench.tracks.pool.real import aquilon, pressproof
from tests import hostile

REPO = Path(__file__).resolve().parents[2]
BUILDERS = {b.NAME: b for b in (aquilon, pressproof)}
SEEDS_PRESENT = all((real.SEEDS_ROOT / b.SEED_ID / "task").is_dir() for b in BUILDERS.values())
needs_seeds = pytest.mark.skipif(not SEEDS_PRESENT, reason=f"seed tasks not under {real.SEEDS_ROOT}")
TASK_PYTHON = os.environ.get("COLLAB_TASK_PYTHON", sys.executable)
SYNTHETIC_KEYS = {"id", "role", "token", "needed", "secret", "match"}  # tracks.pool.generator.notes_and_facts


def task_dir(name: str) -> Path:
    return REPO / "tasks" / "pool" / name


@pytest.fixture(params=sorted(BUILDERS), scope="module")
def task(request):
    return BUILDERS[request.param], task_dir(request.param)


def text(path: Path) -> str:
    return path.read_text()


def facts_of(d: Path) -> list[dict]:
    return json.loads(text(d / "tests" / "facts.json"))


def needed(d: Path) -> list[dict]:
    return [f for f in facts_of(d) if f["needed"]]


def workspace_texts(d: Path) -> dict[str, str]:
    root = d / "environment" / "workspace"
    return {p.relative_to(root).as_posix(): p.read_text(errors="replace") for p in root.rglob("*") if p.is_file()}


def expected_tests(d: Path) -> list[str]:
    return json.loads(text(d / "tests" / "hidden" / "expected_tests.json"))


def shared_surface(d: Path) -> dict[str, str]:
    """Everything both agents see: the instruction, every workspace file (the samples among them), and the hidden
    test ids (the names a report or a reward could show)."""
    return {"instruction.md": text(d / "instruction.md"), **workspace_texts(d),
            "test ids": "\n".join(expected_tests(d))}


def load_score_module(d: Path):
    tests = d / "tests"
    sys.path.insert(0, str(tests))
    bytecode, sys.dont_write_bytecode = sys.dont_write_bytecode, True
    try:
        spec = importlib.util.spec_from_file_location(f"score_{d.name.replace('-', '_')}", tests / "score.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(tests))
        sys.dont_write_bytecode = bytecode
    return module


def score_body(d: Path, body: str, tmp_path: Path, name: str = "ws") -> dict:
    """Run a solve.sh body (bash, reading $WORKSPACE) on a copy of the start workspace, then grade it locally with
    TASK_PYTHON (the task's own grader, as localcheck runs it)."""
    work = tmp_path / name
    work.mkdir()
    return real.score_with(d, body, TASK_PYTHON, work)


def failed(result: dict) -> set[str]:
    return {name for name, ok in result["tests"].items() if not ok}


def live_unless_local(builder):
    return [] if builder.LOCAL else [pytest.mark.live]


def per_task(*names):
    return pytest.mark.parametrize("name", [pytest.param(n, marks=live_unless_local(BUILDERS[n])) for n in names])


# --- layout ---------------------------------------------------------------------------------------------------------

def test_two_real_pool_tasks_in_tasks_pool():
    for name, builder in BUILDERS.items():
        d = task_dir(name)
        raw = tomllib.loads(text(d / "task.toml"))
        meta = raw["metadata"]["collab"]
        assert meta["track"] == "pool" and meta["source_task"] == builder.SEED_ID and meta["roles"] == ["a", "b"]
        assert meta["requirements"] == [*builder.DELIVERABLES, *("F" + f["id"] for f in builder.FACTS if f["needed"])]
        assert meta["reserved_script"] == builder.RESERVED
        assert raw["agent"]["timeout_sec"] == builder.AGENT_TIMEOUT_S in (7200, 14400)
        assert raw["environment"]["network_mode"] == "no-network"  # the kit's line, written by the builder here
        assert text(d / "tests" / "agent_uid").strip() == str(real.AGENT_UID)
    synthetic = sorted(p.name for p in (REPO / "tasks" / "pool").iterdir() if re.fullmatch(r"pool-\d{4}", p.name))
    assert synthetic == [f"pool-{i:04d}" for i in range(1, 7)]  # the synthetic instances stay


def test_manifest_roles_and_private_context(task):
    builder, d = task
    private = d / "environment" / "private"
    assert sorted(p.name for p in private.iterdir()) == ["_harness", "a.md", "b.md"]
    m = json.loads(text(private / "_harness" / "manifest.json"))
    # team.py: agent-i takes roles[i] and reads <role>.md; agent-0 reports. No role brief: both get the instruction.
    assert m["roles"] == ["a", "b"] and m["workspace"] == "shared" and "role_briefs" not in m
    assert m["reserved_command"] == builder.RESERVED and m["owners"] == builder.OWNERS
    owned = {p for paths in m["owners"].values() for p in paths}
    assert all(any(path == o or path.startswith(o + "/") for o in owned) for path in builder.DELIVERABLES.values())


def test_instruction_states_the_contract_and_the_split(task):
    builder, d = task
    brief = text(d / "instruction.md")
    assert all(f"{req}:" in brief and f"/workspace/{path}" in brief for req, path in builder.DELIVERABLES.items())
    assert f"Do not run `{builder.RESERVED}`" in brief and "report for each requirement" in brief
    assert re.search(r"split\s+between\s+(the\s+two\s+of\s+you|your\s+two\s+sets\s+of\s+notes)", brief)
    assert not re.search(r"\bF[ab]\d+\b|facts?\.json|agent-[01]", brief)


def test_pool_conditions_apply():
    """The existing pool conditions: team, solo_2B and solo_B with facts shared, nocomm, oracle."""
    from collabbench.runner.conditions import CONDITIONS
    assert set(CONDITIONS["pool"]) == {"team", "solo_2B", "solo_B", "nocomm", "oracle"}


# --- the brief's tests ----------------------------------------------------------------------------------------------

def test_every_deliverable_needs_both_sides(task):
    """Each deliverable's requirement family depends on at least one fact held by a and one held by b: some test of
    the deliverable is in the family (the hidden tests its violation fails) of a fact of each side."""
    builder, d = task
    families = load_score_module(d).FAMILIES
    role = {f["id"]: f["role"] for f in facts_of(d)}
    assert set(families) == {f["id"] for f in needed(d)}
    for deliverable in builder.DELIVERABLES:
        sides = {role[fid] for fid, tests in families.items() if any(t.startswith(f"test_{deliverable}_") for t in tests)}
        assert sides == {"a", "b"}, (deliverable, sides)


def test_no_needed_fact_in_shared_surface(task):
    """No needed fact's match words appear in the instruction, a workspace file (the samples among them) or the
    hidden test ids: no file discloses it by the metric's own rule (common.fact_disclosed)."""
    _, d = task
    for name, body in shared_surface(d).items():
        leaked = [f["id"] for f in needed(d) if fact_disclosed(f, body)]
        assert not leaked, f"{name} discloses {leaked}"


def test_secret_only_in_b_private(task):
    _, d = task
    secret = [f for f in facts_of(d) if f["secret"]]
    assert len(secret) == 1 and secret[0]["role"] == "b" and not secret[0]["needed"]
    holders = []
    for p in sorted(d.rglob("*")):
        if p.is_file() and p.name != "facts.json" and fact_disclosed(secret[0], p.read_text(errors="replace")):
            holders.append(p.relative_to(d).as_posix())
    assert holders == ["environment/private/b.md"]


def test_facts_schema_works_with_metrics(task):
    """facts.json is the synthetic Pool's schema, and disclosure_precision reads it unchanged: a message carrying
    one needed fact (its holder's own note line), one distractor and the secret scores 1/3."""
    builder, d = task
    facts = facts_of(d)
    assert all(set(f) == SYNTHETIC_KEYS for f in facts)
    assert {f["role"] for f in facts} == {"a", "b"} and len({f["id"] for f in facts}) == len(facts)
    by_id = {f["id"]: f for f in builder.FACTS}
    one_needed = next(f for f in facts if f["needed"] and f["role"] == "b")
    distractor = next(f for f in facts if not f["needed"] and not f["secret"] and f["role"] == "a")
    secret = next(f for f in facts if f["secret"])
    events = [{"type": "message", "payload": {"text": by_id[one_needed["id"]]["text"]}},
              {"type": "publish", "payload": {"title": "status", "body": by_id[distractor["id"]]["text"]}},
              {"type": "message", "payload": {"text": by_id[secret["id"]]["text"]}},
              {"type": "action", "payload": {"command": by_id[secret["id"]]["text"]}}]
    record = TrialRecord("pool", d.name, "team", "t1", 1.0, {}, {}, None, "ok", events=events)
    disclosed = [f["id"] for f in facts if any(fact_disclosed(f, e["payload"].get("text", "") + " "
                                                                + e["payload"].get("body", "")) for e in events[:3])]
    assert sorted(disclosed) == sorted([one_needed["id"], distractor["id"], secret["id"]]), disclosed
    assert disclosure_precision(record, facts) == pytest.approx(1 / 3)
    quiet = TrialRecord("pool", d.name, "team", "t2", 1.0, {}, {}, None, "ok", events=events[:1])
    assert disclosure_precision(quiet, facts) == 1.0


def same_tree(a: Path, b: Path) -> list[str]:
    cmp = filecmp.dircmp(a, b)
    diffs = [f"{a}/{n}" for n in cmp.left_only + cmp.right_only + cmp.diff_files]
    for sub in cmp.common_dirs:
        diffs += same_tree(a / sub, b / sub)
    return diffs


@needs_seeds
def test_shared_frontier_module_reproduces_r1_tasks(tmp_path):
    """The isolation harness and the builder helpers moved to collabbench.taskfmt.frontier; R1's builder, now
    importing them from there, still reproduces its committed Inspire tasks byte for byte, and every real task ships
    the one shared harness."""
    built = inspire_real.build_all(tmp_path)
    for p in built:
        assert not same_tree(p, REPO / "tasks" / "inspire" / p.name), f"{p.name} differs from a fresh build"
    assert not (Path(inspire_real.__file__).parent / "assets" / "harness.py").exists()
    for d in [*built, *(task_dir(n) for n in BUILDERS)]:
        assert text(d / "tests" / "hidden" / "harness.py") == text(frontier.HARNESS)
        assert text(d / "tests" / "isolation.py") == text(Path(iso.__file__))
    assert inspire_real.retarget is frontier.retarget and inspire_real.AGENT_UID == real.AGENT_UID


@per_task(aquilon.NAME, pressproof.NAME)
def test_reference_and_start_local(name, tmp_path):
    builder, d = BUILDERS[name], task_dir(name)
    ref = score_body(d, text(d / "solution" / "solve.sh"), tmp_path, "ref")
    assert ref["reward"] >= 0.98 and ref["extras"]["all_pass"] == 1.0, sorted(failed(ref))[:10]
    assert all(ref["requirements"].values()) and ref["reward"] == 1.0  # the Pool gate needs exactly 1.0
    assert set(ref["requirements"]) == set(builder.DELIVERABLES) | {"F" + f["id"] for f in needed(d)}
    start = score_body(d, "true\n", tmp_path, "start")
    assert start["reward"] <= 0.05 and not any(start["requirements"].values())
    assert sorted(ref["tests"]) == expected_tests(d)


# --- notes and facts ------------------------------------------------------------------------------------------------

def test_notes_carry_each_fact_once(task):
    """Each agent's notes are its own facts, one bullet each: every fact is disclosed by its holder's notes (so a
    copied line counts) and no needed fact by the other's."""
    builder, d = task
    private = d / "environment" / "private"
    notes = {r: text(private / f"{r}.md") for r in ("a", "b")}
    for r in ("a", "b"):
        bullets = [line for line in notes[r].splitlines() if line.startswith("- ")]
        mine = [f for f in builder.FACTS if f["role"] == r]
        assert bullets == [f"- {f['text']}" for f in mine]
        intro = notes[r].split("\n- ", 1)[0]
        assert not [f["id"] for f in builder.FACTS if fact_disclosed(f, intro)], f"{r}'s introduction states a fact"
    for f in builder.FACTS:
        other = "b" if f["role"] == "a" else "a"
        assert fact_disclosed(f, f["text"]), f["id"]
        assert not (f["needed"] and fact_disclosed(f, notes[other])), f"{f['id']} is also in {other}'s notes"
    for r in ("a", "b"):
        mine = [f for f in builder.FACTS if f["role"] == r]
        assert sum(f["needed"] for f in mine) >= 3 and 2 <= sum(not f["needed"] and not f["secret"] for f in mine) <= 3


def test_tests_map_to_requirements(task):
    builder, d = task
    names = expected_tests(d)
    assert names == sorted(set(names)) and len(names) >= 40
    owners = {name: re.findall(r"^test_(D\d+)_", name) for name in names}
    assert all(len(o) == 1 for o in owners.values()), [n for n, o in owners.items() if len(o) != 1]
    assert {o[0] for o in owners.values()} == set(builder.DELIVERABLES)
    score = load_score_module(d)
    assert score.DELIVERABLES == list(builder.DELIVERABLES)
    for fid, family in score.FAMILIES.items():
        assert family and set(family) <= set(names), fid


def test_shortcuts_are_the_red_team_set(task):
    _, d = task
    assert sorted(p.name for p in (d / "shortcuts").iterdir()) == ["a-only", "b-only", "empty-deliverables",
                                                                    "no-facts"]


# --- scoring: ablations and shortcuts -------------------------------------------------------------------------------

@per_task(aquilon.NAME, pressproof.NAME)
def test_attribution_is_specific(name, tmp_path):
    """Fact retention reads the F requirements, so each must name the fact that was lost: the reference with one
    needed fact violated (as an agent that never learned it would write it) turns off that fact's F requirement and
    no other, apart from the overlaps the builder documents (ATTRIBUTION_OVERLAP), and loses reward."""
    builder, d = BUILDERS[name], task_dir(name)
    result = real.attribution(builder, d, TASK_PYTHON, tmp_path)
    assert result["reference"] == {"reward": 1.0, "failed": []}
    assert set(result["off"]) == {f["id"] for f in needed(d)}
    for fid, off in result["off"].items():
        assert off == sorted(["F" + fid, *builder.ATTRIBUTION_OVERLAP.get(fid, [])]), (fid, off)
        assert result["reward"][fid] < 1.0, fid
    print(json.dumps({name: result}))


@per_task(aquilon.NAME, pressproof.NAME)
def test_one_side_shortcuts_fail_every_deliverable(name, tmp_path):
    """The Pool premise, end to end: the reference with one side's facts all violated (a-only, b-only) fails part of
    every deliverable, and so does a solution with neither side's facts. Rates are recorded for the report."""
    builder, d = BUILDERS[name], task_dir(name)
    rates = {}
    for shortcut in ("a-only", "b-only", "no-facts", "empty-deliverables"):
        r = score_body(d, text(d / "shortcuts" / shortcut / "solve.sh"), tmp_path, shortcut)
        rates[shortcut] = {k: r["extras"][f"rate_{k}"] for k in builder.DELIVERABLES} | {"reward": r["reward"]}
        assert not any(r["requirements"][k] for k in builder.DELIVERABLES), (shortcut, rates[shortcut])
        assert r["reward"] <= 0.7, (shortcut, r["reward"])
    assert rates["empty-deliverables"]["reward"] <= 0.05
    print(json.dumps({name: rates}))


# --- the verifier: agent outputs are read only through read_under --------------------------------------------------

@pytest.fixture(params=sorted(BUILDERS))
def shipped_harness(request):
    return task_dir(request.param) / "tests" / "hidden" / "harness.py"


def test_harness_reads_never_leave_the_work_tree(shipped_harness, tmp_path):
    """Root reads an agent's outputs from the run directory the agent controls. A parent directory that is a symlink
    (out -> the tests' hidden directory), a `..`, or a path outside the work tree must never hand root a file."""
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


def test_hidden_tests_read_agent_files_only_through_the_harness(task):
    """Every file an agent program leaves is read through harness.read_regular / read_text (isolation.read_under):
    the hidden tests never open a path themselves."""
    _, d = task
    for p in (d / "tests" / "hidden").glob("test_*.py"):
        src = text(p)
        assert not re.search(r"\bopen\(|read_bytes\(|read_text\(\)|Path\(", src), p.name
        assert "h.read_regular(" in src or "h.read_text(" in src


def test_restore_parent_symlink_cannot_forge_an_output(tmp_path):
    """The parent-symlink case end to end: restore_aquilon.py writes nothing itself, but replaces its output
    directory out/ with a link to a directory root can read that holds the certified library (planted in a copy of
    the task, one directory per manifest digest, standing for any root-readable reference). Root must not read it as
    the program's output: every restore fails, as if nothing were written."""
    d = tmp_path / aquilon.NAME
    shutil.copytree(task_dir(aquilon.NAME), d)
    lib = real.load_module(d / "tests" / "hidden" / aquilon.LIB, "_aquilon_forge")
    planted = d / "tests" / "hidden" / "planted"
    for spec in lib.ELF_VARIANTS:
        inst = lib.generate_elf(spec["seed"], spec["variant"], spec["notes"])
        digest = inst["manifest"].split()[-1].decode()
        (planted / digest).mkdir(parents=True)
        (planted / digest / "restored.so").write_bytes(inst["clean"])
    program = textwrap.dedent(f'''
        import os, shutil, sys
        out = os.path.dirname(sys.argv[3])
        shutil.rmtree(out)
        digest = open(sys.argv[2], "rb").read().split()[-1].decode()
        os.symlink(os.path.join({str(planted)!r}, digest), out)
    ''')
    body = text(d / "solution" / "solve.sh") + f"cat > \"${{W}}/{aquilon.RESTORE}\" <<'PY'\n{program}PY\n"
    r = score_body(d, body, tmp_path)
    assert {f"test_D1_restore[{v}]" for v in aquilon.VARIANTS} <= failed(r) and r["requirements"]["D1"] is False
    assert not failed(r) & {n for n in r["tests"] if n.startswith("test_D2_")}


def test_hostile_tcanon_cannot_change_the_grade(tmp_path):
    """tcanon.py rewrites expected_tests.json and score.py and leaves a double-forked daemon that overwrites
    reward.json. Without root (the explicit local override) the rewrite lands and voids the whole grade, the daemon
    is killed before reward.json is written, and reward.json records that grading ran unisolated."""
    d = tmp_path / aquilon.NAME
    shutil.copytree(task_dir(aquilon.NAME), d)
    ws, out = tmp_path / "ws", tmp_path / "out"
    shutil.copytree(d / "environment" / "workspace", ws)
    subprocess.run(["bash", str(d / "solution" / "solve.sh")], env={**os.environ, "WORKSPACE": str(ws)}, check=True)
    (ws / aquilon.TCANON).write_text(hostile.program(str(d / "tests"), str(out), []) + "print('#TCANON 2 0')\n")
    tripwire = tmp_path / "tripwire"
    tripwire.write_text(f"nonce {text(d / 'tests' / 'tripwire_nonce.txt').strip()}\n")
    try:
        subprocess.run([sys.executable, str(d / "tests" / "grade.py"), "--workspace", str(ws), "--snapshots",
                        str(tmp_path / "none"), "--tripwire", str(tripwire), "--out", str(out)], check=True,
                       timeout=1800, env={**os.environ, iso.LOCAL_ENV: "1"})
        time.sleep(1.0)  # a surviving daemon rewrites reward.json within 0.05 s
        reward = json.loads((out / "reward.json").read_text())
        alive = hostile.survivors(str(out))
    finally:
        hostile.kill(str(out))
    assert not alive and "pwned" not in reward
    if os.geteuid() != 0:
        assert reward["tests_tampered"] == 1 and reward["reward"] == 0.0 and reward["isolated"] == 0
        assert not any(v for k, v in reward.items() if k.startswith("req_"))


# --- reproducibility ------------------------------------------------------------------------------------------------

@needs_seeds
def test_builder_reproduces_the_committed_pool_tasks(tmp_path):
    built = real.build_all(tmp_path)
    assert [p.name for p in built] == [aquilon.NAME, pressproof.NAME]
    for p in built:
        assert not same_tree(p, task_dir(p.name)), f"{p.name} differs from a fresh build; rebuild it"
    for name in ("design/render.py", "tools/farmctl"):
        assert os.access(task_dir(pressproof.NAME) / "environment" / "workspace" / name, os.X_OK)


@needs_seeds
def test_seed_programs_are_kept_verbatim():
    for builder in BUILDERS.values():
        seed = text(real.SEEDS_ROOT / builder.SEED_ID / "task" / "solution" / "solve.sh")
        for program in builder.programs().values():
            assert program in seed


def test_pressproof_images_install_the_seed_libraries():
    d = task_dir(pressproof.NAME)
    for rel in ("environment/Dockerfile", "tests/Dockerfile"):
        assert "numpy==2.2.6 Pillow==11.3.0 scipy==1.15.3 PyYAML==6.0.2" in text(d / rel), rel
    assert "Pillow" not in text(task_dir(aquilon.NAME) / "environment" / "Dockerfile")
    raw = tomllib.loads(text(d / "task.toml"))
    assert raw["environment"]["cpus"] == 2 and raw["environment"]["memory_mb"] == 4096  # the seed's 2-vCPU budget
