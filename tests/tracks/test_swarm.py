import ast
import filecmp
import io
import json
import keyword
import re
import shutil
import subprocess
import tokenize

import pytest

from collabbench.taskfmt.localcheck import score_locally
from collabbench.tracks.swarm.generator import fact_ablations, generate, migrate_subset, module_names, modules
from tests.tracks.swarm_naive import line_local_migrate

SEEDS = range(1, 7)


@pytest.fixture(scope="module")
def tasks(tmp_path_factory):
    out = tmp_path_factory.mktemp("swarm")
    return {s: generate(s, out) for s in SEEDS}


def write(ws, files):
    for rel, text in files.items():
        (ws / rel).parent.mkdir(parents=True, exist_ok=True)
        (ws / rel).write_text(text)


def test_deterministic(tmp_path, tasks):
    cmp = filecmp.dircmp(tasks[2], generate(2, tmp_path))

    def same(c):
        return not (c.left_only or c.right_only or c.diff_files) and all(same(s) for s in c.subdirs.values())

    assert same(cmp)


@pytest.mark.parametrize("seed", SEEDS)
def test_size_and_manifest(tasks, seed):
    d = tasks[seed]
    names = module_names(seed)
    assert 24 <= len(names) <= 40 and len(set(names)) == len(names)
    m = json.loads((d / "environment" / "private" / "_harness" / "manifest.json").read_text())
    assert m["roles"] == ["lead"] and m["workspace"] == "worktrees"
    brief = (d / "instruction.md").read_text()
    assert all(f"R{i}" in brief for i in range(1, len(names) + 1)) and "scripts/release.sh" in brief
    assert all(f in brief for f in ("F1", "F2", "F3"))
    assert not re.search(r"collaborat|teammate|parallel|together|subagent|helper", brief, re.I)
    for f in ("F1:", "F2:", "F3:"):  # brief-only facts: not in the migration guide
        assert f not in (d / "environment" / "workspace" / "docs" / "MIGRATION.md").read_text()


@pytest.mark.parametrize("seed", SEEDS)
def test_reference_scores_one(tasks, seed):
    r = score_locally(tasks[seed], "reference")
    assert r["reward"] == 1.0
    assert {"F1", "F2", "F3"} <= set(r["requirements"]) and f"R{len(module_names(seed))}" in r["requirements"]


@pytest.mark.parametrize("seed", SEEDS)
def test_start_scores_at_most_0_05(tasks, seed):
    assert score_locally(tasks[seed], "start")["reward"] <= 0.05


@pytest.mark.parametrize("seed", SEEDS)
def test_one_module_migrated_scores_its_requirement(tasks, seed, tmp_path):
    first = module_names(seed)[0]
    ws = tmp_path / "ws"
    shutil.copytree(tasks[seed] / "environment" / "workspace", ws)
    write(ws, migrate_subset(seed, {first}))
    r = score_locally(tasks[seed], "start", workspace=ws)
    assert r["requirements"]["R1"] is True and 0 < r["reward"] < 0.2


@pytest.mark.parametrize("seed", SEEDS)
def test_modules_not_identical(tasks, seed):
    ref = migrate_subset(seed, set(module_names(seed)))
    bodies = {}
    for name in module_names(seed):
        entity = name.split("_")[0]
        body = ref[f"acme/{name}.py"].replace(entity, "ENT")
        assert body not in bodies.values(), f"{name} duplicates {[k for k, v in bodies.items() if v == body]}"
        bodies[name] = body


def test_shared_files_conflict(tmp_path, tasks):
    seed, (m1, m2) = 1, module_names(1)[:2]
    ws = tmp_path / "repo"
    shutil.copytree(tasks[seed] / "environment" / "workspace", ws)
    git = lambda *a: subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", *a], cwd=ws,  # noqa: E731
                                    capture_output=True, text=True)
    git("init", "-q", "-b", "main"), git("add", "-A"), git("commit", "-qm", "start")
    for branch, mod in (("a", m1), ("b", m2)):
        git("checkout", "-q", "-b", branch, "main")
        start = {p: (ws / p).read_text() for p in ("acme/registry.py", "CHANGELOG.md", f"acme/{mod}.py")}
        changed = {p: t for p, t in migrate_subset(seed, {mod}).items() if p in start}
        write(ws, changed)
        git("commit", "-qam", f"migrate {mod}")
    git("checkout", "-q", "a")
    merge = git("merge", "--no-edit", "b")
    assert merge.returncode != 0 and "CONFLICT" in merge.stdout
    assert "registry.py" in merge.stdout or "CHANGELOG.md" in merge.stdout


@pytest.mark.parametrize("seed", SEEDS)
def test_facts_tested(tasks, seed, tmp_path):
    for fid, files in fact_ablations(seed).items():
        ws = tmp_path / fid
        shutil.copytree(tasks[seed] / "environment" / "workspace", ws)
        write(ws, files)
        r = score_locally(tasks[seed], "start", workspace=ws)
        assert r["requirements"][fid] is False and r["reward"] < 1.0, f"seed {seed}: ablating {fid} passes"
        assert all(ok for k, ok in r["requirements"].items() if k.startswith("R")), f"{fid} ablation broke an R"


# --- Task 13a: instances sized and varied past one agent's budget ---------------------------------------------------
API = {"get", "put", "scan", "delete", "incr"}
KEEP = API | {"ttl", "default", "key", "value", "amount", "offset", "limit", "start_after"}


def legacy_calls(src: str) -> list[ast.Call]:
    """Every call into legacy.storage, however the module reaches it: plain or aliased imports, imported functions,
    a module-level client variable, or a class instantiated with the client."""
    tree = ast.parse(src)
    recv, fns = set(), set()
    for node in tree.body:
        if isinstance(node, ast.ImportFrom) and node.module == "legacy":
            recv |= {a.asname or a.name for a in node.names if a.name == "storage"}
        elif isinstance(node, ast.ImportFrom) and node.module == "legacy.storage":
            fns |= {a.asname or a.name for a in node.names}
        elif isinstance(node, ast.Import):
            recv |= {a.asname or a.name for a in node.names if a.name == "legacy.storage"}
    for node in tree.body:
        if isinstance(node, ast.Assign) and ast.unparse(node.value) in recv:
            recv |= {ast.unparse(t) for t in node.targets}
    given = {n.func.id for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
             and any(ast.unparse(a) in recv for a in n.args)}
    for cls in (n for n in tree.body if isinstance(n, ast.ClassDef) and n.name in given):
        for init in (f for f in cls.body if isinstance(f, ast.FunctionDef) and f.name == "__init__"):
            params = {a.arg for a in init.args.args}
            for st in ast.walk(init):
                if isinstance(st, ast.Assign) and isinstance(st.value, ast.Name) and st.value.id in params:
                    recv |= {ast.unparse(t) for t in st.targets if ast.unparse(t).startswith("self.")}
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and (
        (isinstance(n.func, ast.Attribute) and n.func.attr in API and ast.unparse(n.func.value) in recv)
        or (isinstance(n.func, ast.Name) and n.func.id in fns))]
    return sorted(calls, key=lambda n: (n.lineno, n.col_offset))


def call_shape(segment: str) -> str:
    """A call site with identifiers, numbers and strings replaced by placeholders; line breaks kept."""
    out = []
    for tok in tokenize.generate_tokens(io.StringIO(segment).readline):
        if tok.type == tokenize.NAME:
            out.append(tok.string if keyword.iskeyword(tok.string) or tok.string in KEEP else "ID")
        elif tok.type == tokenize.NUMBER:
            out.append("N")
        elif tok.type in (tokenize.STRING, tokenize.FSTRING_START, tokenize.FSTRING_MIDDLE, tokenize.FSTRING_END):
            out.append("S")
        elif tok.type == tokenize.OP:
            out.append(tok.string)
        elif tok.type == tokenize.NL:
            out.append("/")
    return " ".join(out)


@pytest.mark.parametrize("seed", SEEDS)
def test_line_local_migrator_scores_low(tasks, seed, tmp_path):
    """A1: rewriting each legacy call line by line from MIGRATION.md alone (plus registry and changelog) must not
    get far: the call sites need code that is not on their line."""
    ws = tmp_path / "ws"
    shutil.copytree(tasks[seed] / "environment" / "workspace", ws)
    line_local_migrate(ws)
    r = score_locally(tasks[seed], "start", workspace=ws)
    assert r["reward"] <= 0.4, f"seed {seed}: the line-local migrator scores {r['reward']:.3f}"


@pytest.mark.parametrize("seed", SEEDS)
def test_instance_size_and_count(tasks, seed):
    acme = tasks[seed] / "environment" / "workspace" / "acme"
    mods = sorted(p for p in acme.glob("*.py") if p.name not in ("__init__.py", "registry.py"))
    assert 60 <= len(mods) <= 90 and [p.stem for p in mods] == module_names(seed)
    total = sum(p.stat().st_size for p in acme.rglob("*") if p.is_file())
    assert 350_000 <= total <= 700_000, f"seed {seed}: acme/ is {total} bytes"
    for p in mods:
        assert 80 <= len(p.read_text().splitlines()) <= 200, f"{p.name}: {len(p.read_text().splitlines())} lines"


@pytest.mark.parametrize("seed", SEEDS)
def test_no_duplicate_call_shapes(tasks, seed):
    acme = tasks[seed] / "environment" / "workspace" / "acme"
    shapes = set()
    for m in modules(seed):
        src = (acme / f"{m.name}.py").read_text()
        calls = legacy_calls(src)
        assert calls, f"{m.name}: no legacy call found"
        shapes.add((m.arch, tuple(call_shape(ast.get_source_segment(src, c)) for c in calls)))
    n = len(module_names(seed))
    assert len(shapes) >= 0.8 * n, f"seed {seed}: {len(shapes)} distinct call-site shapes for {n} modules"
