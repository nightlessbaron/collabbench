import asyncio
import json
import subprocess
import tarfile

from collabbench.harness.events import EventLog
from collabbench.harness.sandbox import Snapshotter, assemble_isolated, prepare_workspace, take_private
from tests.harness.fakes import LocalEnvironment


def git_workspace(root):
    ws = root / "workspace"
    (ws / "app.py").write_text("x = 1\n")
    subprocess.run("git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init",
                   shell=True, cwd=ws, check=True)


def write_private(root, roles=("alpha", "beta"), manifest_extra=None):
    d = root / "opt" / "collab" / "private"
    (d / "_harness").mkdir(parents=True)
    for r in roles:
        (d / f"{r}.md").write_text(f"{r} secret notes")
        (d / f"{r}.placebo.md").write_text(f"{r} placebo notes")
    (d / "_harness" / "manifest.json").write_text(json.dumps({"track": "pool", "roles": list(roles),
                                                              "workspace": "shared", **(manifest_extra or {})}))


async def test_take_private_reads_and_deletes(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    write_private(env.root)
    p = await take_private(env, tmp_path / "local")
    assert p.roles == ["alpha", "beta"] and p.texts["beta"] == "beta secret notes"
    assert p.placebos["alpha"] == "alpha placebo notes" and p.manifest["track"] == "pool"
    assert not (env.root / "opt" / "collab" / "private").exists()


async def test_take_private_absent_returns_empty(tmp_path):
    p = await take_private(LocalEnvironment(tmp_path / "box"), tmp_path / "local")
    assert p.roles == [] and p.manifest == {}


async def test_prepare_workspace_modes(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    git_workspace(env.root)
    assert await prepare_workspace(env, "shared", "agent-1", False) == "/workspace"
    assert await prepare_workspace(env, "worktrees", "lead", True) == "/workspace"
    assert await prepare_workspace(env, "worktrees", "w1", False) == "/work/w1"
    branch = subprocess.run("git branch --show-current", shell=True, cwd=env.root / "work" / "w1",
                            capture_output=True, text=True).stdout.strip()
    assert branch == "w1"
    assert await prepare_workspace(env, "isolated", "agent-0", True) == "/work/agent-0"
    assert (env.root / "work" / "agent-0" / "app.py").read_text() == "x = 1\n"


async def test_assemble_isolated_unit(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    for a, txt in (("agent-0", "A"), ("agent-1", "B")):
        d = env.root / "work" / a / "pkg"
        d.mkdir(parents=True)
        (d / "enc.py").write_text(txt)
        (d / "dec.py").write_text(txt)
    await assemble_isolated(env, {"agent-0": ["pkg/enc.py"], "agent-1": ["pkg/dec.py"]})
    ws = env.root / "workspace" / "pkg"
    assert (ws / "enc.py").read_text() == "A" and (ws / "dec.py").read_text() == "B"


async def test_snapshot_index_unit(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    git_workspace(env.root)
    snap = Snapshotter(env, EventLog(tmp_path / "ev.jsonl"), 999, 24, lambda: {"workspace": "/workspace"},
                       tokens=lambda: 1234)
    await snap.take("status:agent-0")
    index = json.loads((env.root / "snapshots" / "index.json").read_text())
    assert index[0]["label"] == "workspace" and index[0]["reason"] == "status:agent-0"
    assert index[0]["tokens_so_far"] == 1234
    with tarfile.open(env.root / "snapshots" / index[0]["file"]) as tar:
        names = tar.getnames()
    assert "./app.py" in names and not any(".git" in n for n in names)


async def test_snapshotter_run_doubles_interval(tmp_path):
    env = LocalEnvironment(tmp_path / "box")
    snap = Snapshotter(env, EventLog(tmp_path / "ev.jsonl"), 0.05, 2, lambda: {"workspace": "/workspace"})
    stop = asyncio.Event()
    task = asyncio.create_task(snap.run(stop))
    await asyncio.sleep(0.5)
    stop.set()
    await task
    assert 2 <= snap.taken <= 5  # 0.05, 0.05, then 0.1, 0.2: at most a few in 0.5 s
