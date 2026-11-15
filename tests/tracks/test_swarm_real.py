"""Swarm tasks built from real upstream migrations (Task R2).

Structure checks only: these tests read the committed task files and run git on copies of them. They never import
or execute upstream code; the gate measures the reference and start scores on Modal.
"""

import fnmatch
import json
import re
import shutil
import subprocess
import tomllib
from pathlib import Path

import pytest

from collabbench import settings
from collabbench.tracks.swarm.real import common
from collabbench.tracks.swarm.real.__main__ import workspace_files, write_naive
from collabbench.tracks.swarm.real.common import Area, Migration, patch_from_solve, static_test_count
from collabbench.tracks.swarm.real.naive import migrate_files

_REQ = re.compile(r"test_([A-Z]+\d+)_")


def _migrations() -> dict[str, Migration]:
    from collabbench.tracks.swarm.real import emmet, ormar
    return {m.slug: m for m in (ormar.MIGRATION, emmet.MIGRATION)}


MIGRATIONS = _migrations()
SLUGS = sorted(MIGRATIONS)
TASKS = settings.REPO / "tasks" / "swarm"
# Words from each brief-only fact that the migration guide must not contain (the facts are retention probes).
FACT_MARKERS = {"ormar-pydantic2": [r"\bModelMeta\b", r"ModelDefinitionError"],
                "emmet-pydantic2": [r"emmet\.core\.settings import PyObject", r"hot loops", r"not_a_setting",
                                    r"MAPISettings.*ignore"]}


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True).stdout


def runs(dockerfile: str) -> list[str]:
    """The RUN instructions of a Dockerfile, continuation lines joined."""
    text = dockerfile.replace("\\\n", " ")
    return [line[4:] for line in text.splitlines() if line.startswith("RUN ")]


def collab(task: Path) -> dict:
    return tomllib.loads((task / "task.toml").read_text())["metadata"]["collab"]


def hidden_modules(task: Path) -> dict[str, str]:
    hidden = task / "tests" / "hidden"
    return {str(p.relative_to(hidden)): p.read_text() for p in hidden.rglob("test_*.py")}


def area_of(key: str, areas: dict) -> list[str]:
    m = _REQ.match(key.rsplit("::", 1)[-1])
    if m:
        return [m.group(1)]
    return [rid for rid, a in areas.items() if any(key.startswith(p) for p in a["prefixes"])]


@pytest.fixture(scope="module", params=SLUGS)
def task(request) -> Path:
    path = TASKS / request.param
    assert (path / "task.toml").exists(), f"missing: python -m collabbench.tracks.swarm.real build {request.param}"
    return path


@pytest.fixture(scope="module")
def applied(task, tmp_path_factory) -> Path:
    """A git copy of the start workspace with the reference patch applied."""
    ws = tmp_path_factory.mktemp(task.name) / "ws"
    shutil.copytree(task / "environment" / "workspace", ws, symlinks=True)
    git(ws, "init", "-q")
    git(ws, "add", "-A")
    git(ws, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "start")
    subprocess.run(["bash", str(task / "solution" / "solve.sh")], env={"WORKSPACE": str(ws), "PATH": "/usr/bin:/bin"},
                   check=True, capture_output=True)
    return ws


# --- the committed tasks --------------------------------------------------------------------------------------------

def test_start_has_no_future_history(task):
    m = MIGRATIONS[task.name]
    env = task / "environment"
    assert not (env / "workspace" / ".git").exists()
    steps = runs((env / "Dockerfile").read_text())
    [ws_step] = [r for r in steps if "cd /workspace" in r]
    assert ws_step.count("git init") == 1 and ws_step.count("git commit") == 1 and "remote" not in ws_step
    for step in steps:  # a build step may read upstream data, but its clone never stays in the image
        if "git remote add" in step:
            clone = re.search(r"git init -q (/tmp/\S+)", step).group(1)
            assert f"rm -rf {clone}" in step and "/workspace" not in step
    visible = {"instruction.md": (task / "instruction.md").read_text(),
               **{f"workspace/{k}": v for k, v in workspace_files(task).items() if isinstance(v, str)},
               **{str(p.relative_to(env)): p.read_text() for p in (env / "Dockerfile", env / "tripwire.sh")}}
    for name, text in visible.items():
        for version in m.post_versions:
            assert version not in text, f"{name} names the post-migration version {version}"
        assert m.after not in text, f"{name} names the post-migration commit"


def test_migration_size(task):
    m = MIGRATIONS[task.name]
    patch = patch_from_solve((task / "solution" / "solve.sh").read_text())
    paths = re.findall(r"^diff --git a/(\S+) b/", patch, flags=re.M)
    sources = [p for p in paths if any(fnmatch.fnmatch(p, g) for g in m.source_globs)]
    assert len(sources) >= 40
    assert len({"/".join(p.split("/")[:-1]) for p in sources}) >= 5  # spread over several packages
    pinned = json.loads((task / "tests" / "hidden" / "expected_tests.json").read_text())
    if pinned == "collect":  # harvest mode, until `collabbench pin-tests` pins the gate's fail-to-pass tests
        assert static_test_count(hidden_modules(task)) >= 200
    else:
        assert len(pinned) >= 200


def test_reference_patch_matches_upstream_layout(task, applied):
    """The patch applies to the start, and changes only migration sources (tests and docs are left to the agents)."""
    m = MIGRATIONS[task.name]
    changed = [line[3:] for line in git(applied, "status", "--porcelain", "-uall").splitlines()]
    assert len(changed) == collab(task)["reference_files"]
    assert all(any(fnmatch.fnmatch(p, g) for g in m.source_globs) for p in changed)
    for path, edits in m.fact_edits.items():
        text = (applied / path).read_text()
        assert all(new in text for _, new in edits)


def test_line_local_regex_scores_low(task, applied):
    """A line-local regex migrator from MIGRATION.md's tables must not solve the task (≤ 0.4).

    Locally: it does real work, yet most reference files need more than line rewrites (measured when built: it
    reproduces 0 of ormar's 64 changed modules and 28 of emmet's 95). Live: the oracle reward of the naive variant's
    gate, recorded in task.toml as naive_probe_reward, decides."""
    files = workspace_files(task)
    naive = migrate_files(files)
    reference = [p for p in git(applied, "diff", "--name-only", "HEAD").split() if p.endswith(".py")]
    assert len(naive) >= 10
    same = [p for p in reference if p in naive and naive[p] == (applied / p).read_text()]
    assert len(same) <= 0.5 * len(reference), same
    measured = collab(task).get("naive_probe_reward")
    if measured is None:
        pytest.skip(f"measure at gate: python -m collabbench.tracks.swarm.real naive tasks/swarm/{task.name}, then "
                    f"collabbench gate runs/naive/{task.name}-naive (oracle reward = probe score)")
    assert measured <= 0.4


def test_requirements_cover_tests(task):
    m = MIGRATIONS[task.name]
    areas = json.loads((task / "tests" / "hidden" / "areas.json").read_text())
    assert list(areas) == [a.rid for a in m.areas]
    covered = {rid: 0 for rid in areas}
    for path, text in hidden_modules(task).items():
        if not static_test_count({path: text}):
            continue
        if Path(path).name == "test_collab_facts.py":
            assert {f for f in re.findall(r"def test_(F\d)_", text)} <= set(m.facts)
            continue
        [rid] = area_of(path[:-3].replace("/", ".") + "::", areas)
        covered[rid] += static_test_count({path: text})
    assert all(covered.values()), covered
    facts = "".join(t for p, t in hidden_modules(task).items() if p.endswith("test_collab_facts.py"))
    assert sorted(set(re.findall(r"def test_(F\d)_", facts))) == sorted(m.facts)
    pinned = json.loads((task / "tests" / "hidden" / "expected_tests.json").read_text())
    if pinned != "collect":
        assert all(len(area_of(key, areas)) == 1 for key in pinned)
    assert collab(task)["requirements"] == [*areas, *m.facts]
    instruction = (task / "instruction.md").read_text()
    assert all(f"- {rid} (" in instruction for rid in areas) and all(f"- {f}: " in instruction for f in m.facts)


def test_facts_stay_out_of_the_guide(task):
    guide = (task / "environment" / "workspace" / "docs" / "MIGRATION.md").read_text()
    for marker in FACT_MARKERS[task.name]:
        assert not re.search(marker, guide), marker
    assert "F1" not in guide and "F2" not in guide and "F3" not in guide


def test_sandboxes_have_no_network_and_no_project_install(task):
    assert tomllib.loads((task / "task.toml").read_text())["environment"]["network_mode"] == "no-network"
    project = {"ormar-pydantic2": r"\bormar==", "emmet-pydantic2": r"\b(emmet-\w+|mp-api)=="}[task.name]
    for dockerfile in (task / "environment" / "Dockerfile", task / "tests" / "Dockerfile"):
        pip = [r for r in runs(dockerfile.read_text()) if "pip install" in r]
        assert pip and not any(re.search(project, r) for r in pip)
    assert collab(task)["oracle_min"] == 0.98
    manifest = json.loads((task / "environment" / "private" / "_harness" / "manifest.json").read_text())
    assert manifest["roles"] == ["lead"] and manifest["workspace"] == "worktrees"
    assert tomllib.loads((task / "task.toml").read_text())["agent"]["timeout_sec"] == 7200


def test_naive_variant_applies(task, tmp_path):
    variant = write_naive(task, tmp_path)
    assert variant.name == f"{task.name}-naive"
    patch = patch_from_solve((variant / "solution" / "solve.sh").read_text())
    assert len(re.findall(r"^diff --git ", patch, flags=re.M)) == len(migrate_files(workspace_files(task)))
    assert (variant / "tests" / "hidden" / "expected_tests.json").read_text() == \
        (task / "tests" / "hidden" / "expected_tests.json").read_text()


# --- the builder, on a toy upstream repository ----------------------------------------------------------------------

@pytest.fixture
def toy(tmp_path, monkeypatch):
    up = tmp_path / "toy-upstream"
    up.mkdir()

    def commit(files: dict, msg: str) -> str:
        for rel, data in files.items():
            if data is None:
                (up / rel).unlink()
                continue
            (up / rel).parent.mkdir(parents=True, exist_ok=True)
            (up / rel).write_bytes(data if isinstance(data, bytes) else data.encode())
        git(up, "add", "-A")
        git(up, "-c", "user.name=u", "-c", "user.email=u@u", "commit", "-qm", msg)
        return git(up, "rev-parse", "HEAD").strip()

    git(up, "init", "-q")
    parent = commit({"pkg/a.py": "from pydantic import validator\nX = 1\n", "pkg/b.py": "B = 1\n",
                     "pkg/blob.bin": b"\x00\x01\xff", "tests/test_a.py": "def test_a():\n    pass\n",
                     ".github/ci.yml": "on: push\n", "README.md": "toy 1.0.0\n"}, "v1")
    after = commit({"pkg/a.py": "from pydantic import field_validator\nX = 1\n", "pkg/b.py": None,
                    "pkg/new.py": "N = 1\n", "tests/test_a.py": "def test_a():\n    pass\n\n\ndef test_b():\n    pass\n",
                    "README.md": "toy 2.0.0\n"}, "v2")
    monkeypatch.setattr(common, "CACHE", tmp_path / "cache")
    return Migration(slug="toy-migration", url=str(up), parent=parent, after=after, prs=["https://example.invalid/1"],
                     source_globs=["pkg/*"], hidden_tests={"tests": "tests"},
                     areas=[Area("R1", "a", ["tests.test_a::"], "pkg/a works")],
                     facts={"F1": "Y must be 2."}, fact_tests={"hidden/tests/test_collab_facts.py":
                                                              "def test_F1_y():\n    pass\n"},
                     fact_edits={"pkg/a.py": [("X = 1\n", "X = 1\nY = 2\n")]}, migration_md="# Guide\n",
                     brief_intro="# Toy migration", post_versions=["2.0.0"], drop=[".github/*"])


def test_builder_on_a_toy_upstream(toy, tmp_path):
    d = toy.write(tmp_path / "out")
    ws = d / "environment" / "workspace"
    assert sorted(str(p.relative_to(ws)) for p in ws.rglob("*") if p.is_file()) == \
        ["README.md", "docs/MIGRATION.md", "pkg/a.py", "pkg/b.py", "pkg/blob.bin", "tests/test_a.py"]
    assert (ws / "pkg" / "blob.bin").read_bytes() == b"\x00\x01\xff"
    hidden = d / "tests" / "hidden"
    assert "test_b" in (hidden / "tests" / "test_a.py").read_text()
    assert (hidden / "tests" / "test_collab_facts.py").exists()
    assert json.loads((hidden / "expected_tests.json").read_text()) == "collect"
    assert json.loads((hidden / "areas.json").read_text()) == {"R1": {"name": "a", "prefixes": ["tests.test_a::"]}}
    meta = collab(d)
    assert (meta["parent"], meta["after"], meta["reference_files"]) == (toy.parent, toy.after, 3)
    copy = tmp_path / "copy"
    shutil.copytree(ws, copy)
    git(copy, "init", "-q")
    git(copy, "add", "-A")
    git(copy, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "start")
    subprocess.run(["bash", str(d / "solution" / "solve.sh")], env={"WORKSPACE": str(copy), "PATH": "/usr/bin:/bin"},
                   check=True)
    assert (copy / "pkg" / "a.py").read_text() == "from pydantic import field_validator\nX = 1\nY = 2\n"
    assert not (copy / "pkg" / "b.py").exists() and (copy / "pkg" / "new.py").read_text() == "N = 1\n"
    assert (copy / "README.md").read_text() == "toy 1.0.0\n"  # only migration sources are in the reference


def test_rebuild_keeps_pinned_tests(toy, tmp_path):
    d = toy.write(tmp_path / "out")
    (d / "tests" / "hidden" / "expected_tests.json").write_text(json.dumps(["tests.test_a::test_b"]))
    d = toy.write(tmp_path / "out")
    assert json.loads((d / "tests" / "hidden" / "expected_tests.json").read_text()) == ["tests.test_a::test_b"]


def test_fact_edit_anchor_must_occur_once(toy, tmp_path):
    toy.fact_edits = {"pkg/a.py": [("Z = 3\n", "Z = 4\n")]}
    with pytest.raises(ValueError, match="occurs 0 times"):
        toy.write(tmp_path / "out")


def test_emmet_checkout_found_from_the_current_directory(tmp_path):
    """The agent image's .pth puts the emmet packages of the checkout around the cwd on sys.path (teammates work in
    /work/<name>, not /workspace)."""
    import base64
    task = TASKS / "emmet-pydantic2"
    [step] = [r for r in runs((task / "environment" / "Dockerfile").read_text()) if "emmet-workspace.pth" in r]
    pth = base64.b64decode(re.search(r"echo (\S+) \| base64 -d", step).group(1)).decode()
    site_dir = tmp_path / "site"
    site_dir.mkdir()
    (site_dir / "emmet-workspace.pth").write_text(pth)
    checkout = tmp_path / "work" / "a1"
    for pkg in ("emmet-core", "emmet-builders", "emmet-api"):
        (checkout / pkg / "emmet").mkdir(parents=True)
    (checkout / "emmet-core" / "tests").mkdir()
    probe = f"import site, sys; site.addsitedir({str(site_dir)!r}); print('\\n'.join(sys.path))"
    for cwd in (checkout, checkout / "emmet-core" / "tests"):
        out = subprocess.run(["python3", "-I", "-c", probe], cwd=cwd, capture_output=True, text=True, check=True)
        assert out.stderr == ""
        paths = out.stdout.splitlines()
        assert [p for p in paths if "emmet-" in p] == [str(checkout / p) for p in
                                                       ("emmet-core", "emmet-builders", "emmet-api")]
    out = subprocess.run(["python3", "-I", "-c", probe], cwd=tmp_path, capture_output=True, text=True, check=True)
    assert "/workspace/emmet-core" in out.stdout.splitlines()


def test_emmet_verifier_finds_test_data_and_openbabel(tmp_path):
    """The scored workspace has no test_files link (Harbor and the grader drop links that leave the tree), so the
    hidden conftest points MAPISettings at the image's copy. Upstream CI installed openbabel (conda); so do the images."""
    task = TASKS / "emmet-pydantic2"
    conftest = task / "tests" / "hidden" / "conftest.py"
    probe = (f"import os, runpy; os.environ.pop('MAPI_TEST_FILES', None); runpy.run_path({str(conftest)!r}); "
             f"print(os.environ['MAPI_TEST_FILES'])")
    out = subprocess.run(["python3", "-I", "-c", probe], capture_output=True, text=True, check=True,
                         env={"COLLAB_WORKSPACE": str(tmp_path), "PATH": "/usr/bin:/bin"})
    assert out.stdout.strip() == str(task / "tests" / "hidden" / "test_files")
    for dockerfile in (task / "environment" / "Dockerfile", task / "tests" / "Dockerfile"):
        assert re.search(r"\bopenbabel-wheel==3\.1\.1\.\d+", dockerfile.read_text())
