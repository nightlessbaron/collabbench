import filecmp
import json
import re
import shutil
import subprocess

import pytest

from collabbench.taskfmt.localcheck import score_locally
from collabbench.tracks.swarm.generator import fact_ablations, generate, migrate_subset, module_names

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
