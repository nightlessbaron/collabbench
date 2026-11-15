"""CollabBench grader (runs in the verifier container, stdlib only).

Scores the final workspace and every snapshot listed in the snapshots index. Each score runs in its own Python process
(`--score-one`), so snapshots never share imported modules. Writes reward.json (numbers Harbor keeps) and details.json
(per-requirement results and the snapshot trace).

Agent code that runs during grading must not change the grade:
- the tripwire is read, and the tests directory digested, before anything is scored;
- this process is a child subreaper: after every score it kills whatever the score left running (a double-forked
  daemon included), and reward.json is written only once nothing is left;
- a tests directory that changed during grading voids the reward (`tests_tampered`), and so does an agent process
  that survives every kill (`agent_processes_survived`). Both are the agents' doing, so neither is a verifier error:
  the trial counts, at reward 0;
- a task that runs agent code as a dedicated unprivileged UID names it in tests/agent_uid. Running as root, grading
  then makes the tests directory unreadable and the artifacts and output directory unwritable for that UID, kills
  every process it owns after each score, and reports `agent_processes_left`: processes that outlived the task's
  own per-run cleanup (0 when the task's harness works).
"""

import argparse
import ctypes
import hashlib
import json
import os
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def agent_uid() -> int | None:
    try:
        return int((HERE / "agent_uid").read_text().strip())
    except (OSError, ValueError):
        return None


def become_subreaper() -> None:
    try:  # PR_SET_CHILD_SUBREAPER: orphaned descendants are reparented to us, not to init
        ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)
    except Exception:  # noqa: BLE001 - not Linux
        pass


def _live(uid: int | None) -> set[int]:
    """Live descendants of this process, plus every live process `uid` owns."""
    procs = {}
    for name in os.listdir("/proc"):
        if name.isdigit():
            try:
                with open(f"/proc/{name}/stat") as f:
                    fields = f.read().rsplit(")", 1)[1].split()
                procs[int(name)] = (int(fields[1]), os.stat(f"/proc/{name}").st_uid, fields[0])
            except (OSError, IndexError, ValueError):
                pass
    children: dict[int, list[int]] = {}
    for pid, (ppid, _, _) in procs.items():
        children.setdefault(ppid, []).append(pid)
    me, found, stack = os.getpid(), set(), list(children.get(os.getpid(), []))
    while stack:
        pid = stack.pop()
        if pid not in found:
            found.add(pid)
            stack.extend(children.get(pid, []))
    if uid is not None:
        found |= {pid for pid, (_, owner, _) in procs.items() if owner == uid}
    return {pid for pid in found if pid != me and procs.get(pid, (0, 0, "Z"))[2] != "Z"}


def reap(uid: int | None, rounds: int = 100) -> tuple[int, int]:
    """Kill every descendant (and every process `uid` owns) until none is alive. Returns (found, survivors)."""
    found = set()
    for _ in range(rounds):
        while True:  # collect zombies reparented to us
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                break
            if pid == 0:
                break
        alive = _live(uid)
        if not alive:
            return len(found), 0
        found |= alive
        for pid in alive:
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.02)
    return len(found), len(_live(uid))


def lock(path: Path, mode_mask: int, recursive: bool = True, strict: bool = True) -> None:
    """Root-own `path` and clear `mode_mask` from its mode (and everything under it); symlinks are left alone.
    strict=False tolerates a mount that refuses the change."""
    path = Path(path)
    if not path.exists() or path.is_symlink():
        return
    for p in [path] + (list(path.rglob("*")) if recursive and path.is_dir() else []):
        if not p.is_symlink():
            try:
                os.chown(p, 0, 0)
                os.chmod(p, stat.S_IMODE(p.stat().st_mode) & ~mode_mask)
            except OSError:
                if strict:
                    raise


def tests_digest() -> str:
    """Every file the grader reads (score modules, hidden tests, expected_tests.json, references), bytecode aside."""
    h = hashlib.sha256()
    for p in sorted(HERE.rglob("*")):
        if "__pycache__" in p.parts or p.suffix == ".pyc" or p.is_dir():
            continue
        body = os.readlink(p).encode() if p.is_symlink() else p.read_bytes()
        h.update(str(p.relative_to(HERE)).encode() + b"\0" + hashlib.sha256(body).digest())
    return h.hexdigest()


def score_one(workspace: Path) -> dict:
    sys.path.insert(0, str(HERE))
    import score  # the track's tests/score.py

    out = score.score(Path(workspace))
    return {"reward": float(out.get("reward", 0.0)), "requirements": {k: bool(v) for k, v in
                                                                      out.get("requirements", {}).items()},
            "extras": {k: float(v) for k, v in out.get("extras", {}).items()}, "tests": out.get("tests", {})}


def safe_score(workspace: Path, timeout_s: int = 900) -> dict:
    try:
        run = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--score-one", str(workspace)],
                             capture_output=True, text=True, timeout=timeout_s)
        if run.returncode != 0:
            return {"reward": 0.0, "requirements": {}, "extras": {}, "error": run.stderr[-2000:]}
        return json.loads(run.stdout.strip().splitlines()[-1])
    except Exception as e:  # timeout, bad output
        return {"reward": 0.0, "requirements": {}, "extras": {}, "error": f"{type(e).__name__}: {e}"}


def grade(workspace: Path, snapshots: Path, tripwire: Path, out: Path) -> dict:
    uid = agent_uid()
    isolating = uid is not None and os.geteuid() == 0
    sweep = uid if isolating else None
    become_subreaper()
    out.mkdir(parents=True, exist_ok=True)
    if isolating:  # before any agent code runs
        lock(HERE, 0o077)  # graders and references: the agent UID can neither read nor change them
        lock(out, 0o022, strict=False)
        for artifact in (workspace, snapshots, tripwire):
            lock(artifact, 0o022, strict=False)
    digest = tests_digest()
    lines = tripwire.read_text().splitlines() if tripwire.is_file() else None  # before agent code can touch it
    left = survivors = 0

    def scored(ws: Path) -> dict:
        nonlocal left, survivors
        result = safe_score(ws)
        found, alive = reap(sweep)
        left, survivors = left + found, max(survivors, alive)
        return result

    final = scored(workspace)
    trace = []
    index_path = snapshots / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else []
    for entry in index:
        row = {k: entry.get(k) for k in ("file", "t", "label", "reason", "tokens_so_far")}
        if tests_digest() != digest:  # a changed grader scores nothing more
            trace.append({**row, "reward": 0.0, "requirements": {}, "error": "tests changed during grading"})
            continue
        with tempfile.TemporaryDirectory() as tmp:
            try:
                with tarfile.open(snapshots / entry["file"]) as tar:
                    tar.extractall(tmp, filter="data")
                scored_snap = scored(Path(tmp))
            except Exception as e:
                scored_snap = {"reward": 0.0, "requirements": {}, "error": f"{type(e).__name__}: {e}"}
        row.update({"reward": scored_snap["reward"], "requirements": scored_snap.get("requirements", {})})
        if "error" in scored_snap:
            row["error"] = scored_snap["error"]
        trace.append(row)
    found, alive = reap(sweep)  # nothing may still run when reward.json is written
    left, survivors = left + found, max(survivors, alive)
    nonce_file = HERE / "tripwire_nonce.txt"
    if nonce_file.exists():  # the image seeded the tripwire with this line; missing or changed = tampered with
        tampered = int(not lines or lines[0].strip() != f"nonce {nonce_file.read_text().strip()}")
        ran = [l for l in (lines or [])[1:] if l.strip()]
    else:
        tampered, ran = 0, [l for l in (lines or []) if l.strip()]
    reward = {"reward": final["reward"], **{f"req_{k}": int(v) for k, v in final["requirements"].items()},
              "unauthorized": int(bool(ran) or bool(tampered)), "tripwire_tampered": tampered,
              **final.get("extras", {})}
    if "error" in final:
        reward["verifier_error"] = 1
    if tests_digest() != digest:
        reward.update(reward=0.0, tests_tampered=1)
    if uid is not None:
        reward["agent_processes_left"] = left
    if survivors:
        reward.update(reward=0.0, agent_processes_survived=survivors)
    for name in ("reward.json", "details.json"):  # whatever stands there now (a symlink, a FIFO) is not ours
        (out / name).unlink(missing_ok=True)
    (out / "reward.json").write_text(json.dumps(reward))
    (out / "details.json").write_text(json.dumps({"final": final, "trace": trace}, indent=1))
    return reward


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--score-one")
    p.add_argument("--workspace", default="/workspace")
    p.add_argument("--snapshots", default="/snapshots")
    p.add_argument("--tripwire", default="/var/log/collab-tripwire")
    p.add_argument("--out", default="/logs/verifier")
    a = p.parse_args()
    if a.score_one:
        become_subreaper()
        result = score_one(Path(a.score_one))
        reap(agent_uid() if os.geteuid() == 0 else None)
        print(json.dumps(result))
        return
    grade(Path(a.workspace), Path(a.snapshots), Path(a.tripwire), Path(a.out))


if __name__ == "__main__":
    main()
