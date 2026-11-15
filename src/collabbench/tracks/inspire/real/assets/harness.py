"""How the hidden tests run the agents' programs: the taskmaker.frontier verifier kit (harness.py), adapted to the
CollabBench verifier.

Isolation (as the seed kit had it). The task names a dedicated unprivileged UID in tests/agent_uid. When the verifier
runs as root, as it does in the verifier container:
- every agent program runs as that UID and GID with no supplementary groups;
- the tests directory (graders, reference libraries, expected_tests.json, score modules) is made root-owned and
  unreadable and unwritable for that UID, and so is /logs/verifier for writing, before any agent program runs;
- each run gets a fresh directory filled first and then chowned to that UID; nothing else is chowned;
- the graded workspace is copied first into a root-owned, read-only tree that the programs run from, so a program
  can neither change what is graded nor write next to it;
- after every run, every process the UID owns is killed (and every descendant of this process, which is a child
  subreaper, so a double-forked daemon cannot escape), and the run returns only once none is left.
Without root (local checks) the programs run as the current user; only the descendant reaping and the read-only
workspace copy apply, and the kit's grade.py detects a changed tests directory instead of preventing it.

One addition: the kit gives a whole score 900 s, so a program that hangs must not take every other deliverable's
credit with it. run_agent takes an optional `budget` (a name and seconds): time lost to that program's timeouts is
charged to it, and once the budget is spent its remaining runs fail as timeouts without being started.
"""

import atexit
import ctypes
import hashlib
import json
import os
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TESTS = Path(__file__).resolve().parent.parent  # tests/: score.py, pytest_score.py, grade.py, hidden/
ORIGINAL = os.environ.get("COLLAB_WORKSPACE", "/workspace")  # the workspace grade.py asked us to score
PYTHON = sys.executable  # the verifier's Python 3.12, standard library plus pytest and numpy
LOGS = Path("/logs/verifier")


def _agent_uid():
    try:
        return int((TESTS / "agent_uid").read_text().strip())
    except (OSError, ValueError):
        return None


AGENT_UID = _agent_uid()
ISOLATED = AGENT_UID is not None and os.geteuid() == 0
WORKSPACE = ORIGINAL  # replaced by the read-only copy in setup_work
_root = [None]
_counter = [0]
_budgets = {}


def ws(*parts):
    """A path inside the (copied) workspace being graded."""
    return os.path.join(WORKSPACE, *parts)


# --- processes ------------------------------------------------------------------------------------------------------

def _become_subreaper():
    try:  # PR_SET_CHILD_SUBREAPER: orphans of our children are reparented to us, not to init
        ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)
    except Exception:  # noqa: BLE001 - not Linux; the UID sweep still applies
        pass


def _procs():
    """{pid: (ppid, uid, state)} for every live process."""
    out = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat") as f:
                fields = f.read().rsplit(")", 1)[1].split()
            out[int(name)] = (int(fields[1]), os.stat(f"/proc/{name}").st_uid, fields[0])
        except (OSError, IndexError, ValueError):
            pass
    return out


def _targets(uid):
    procs = _procs()
    me = os.getpid()
    children = {}
    for pid, (ppid, _, _) in procs.items():
        children.setdefault(ppid, []).append(pid)
    found, stack = set(), list(children.get(me, []))
    while stack:
        pid = stack.pop()
        if pid not in found:
            found.add(pid)
            stack.extend(children.get(pid, []))
    if uid is not None:
        found |= {pid for pid, (_, owner, _) in procs.items() if owner == uid}
    return {pid for pid in found if pid != me and procs.get(pid, (0, 0, "Z"))[2] != "Z"}


def reap(uid=None, rounds=100):
    """Kill every descendant of this process and, when isolated, every process the agent UID owns; return once none
    is alive. Raises if some survive (grading must not go on next to agent code)."""
    uid = AGENT_UID if uid is None and ISOLATED else uid
    for _ in range(rounds):
        alive = _targets(uid)
        while True:  # collect zombies reparented to us
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                break
            if pid == 0:
                break
        if not alive:
            return
        for pid in alive:
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.02)
    raise RuntimeError(f"agent processes survive: {sorted(_targets(uid))}")


# --- the filesystem -------------------------------------------------------------------------------------------------

def _lock(path, mode_mask, recursive=True, strict=True):
    """Root-own `path` (recursively) and clear `mode_mask` from every entry's mode; symlinks are left alone.
    strict=False tolerates a mount that refuses the change (grade.py replaces the reward files anyway)."""
    path = Path(path)
    if not path.exists() or path.is_symlink():
        return
    entries = [path] + (list(path.rglob("*")) if recursive and path.is_dir() else [])
    for p in entries:
        if p.is_symlink():
            continue
        try:
            os.chown(p, 0, 0)
            os.chmod(p, stat.S_IMODE(p.stat().st_mode) & ~mode_mask)
        except OSError:
            if strict:
                raise


def _skip(directory, names):
    """.git, and anything that is not a directory, regular file or symlink (a FIFO would hang the copy)."""
    out = []
    for n in names:
        mode = os.lstat(os.path.join(directory, n)).st_mode
        if n == ".git" or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
            out.append(n)
    return out


def _readonly_copy(src, dst):
    """Copy the graded workspace to a root-owned tree the agent UID can read and run but not change."""
    shutil.copytree(src, dst, symlinks=True, ignore=_skip)
    for p in [Path(dst)] + list(Path(dst).rglob("*")):
        if p.is_symlink():
            continue
        if ISOLATED:
            os.chown(p, 0, 0)
        mode = stat.S_IMODE(p.stat().st_mode)
        if p.is_dir():
            os.chmod(p, 0o755)
        else:
            os.chmod(p, 0o755 if mode & 0o111 else 0o644)


def setup_work():
    """Call once per session (a session-scoped autouse fixture) before any run_agent."""
    global WORKSPACE
    if _root[0] is not None:
        return
    _become_subreaper()
    if ISOLATED:
        _lock(TESTS, 0o077)  # graders and references: neither readable nor writable by the agent UID
        _lock(LOGS.parent, 0o022, recursive=False, strict=False)
        _lock(LOGS, 0o022, strict=False)
    root = tempfile.mkdtemp(prefix="verify_work_")
    atexit.register(shutil.rmtree, root, True)  # the copy and every run directory go with the session
    os.chmod(root, 0o755)
    _root[0] = root
    if os.path.isdir(ORIGINAL):
        WORKSPACE = os.path.join(root, "workspace")
        _readonly_copy(ORIGINAL, WORKSPACE)


def _env():
    bindir = os.path.dirname(PYTHON)
    return {"PATH": f"{bindir}:/usr/local/bin:/usr/bin:/bin", "HOME": _root[0], "LANG": "C.UTF-8",
            "PYTHONDONTWRITEBYTECODE": "1"}


def run_agent(cmd, cwd, timeout, stdin=None, budget=None):
    """Run agent code (an argv list) in `cwd`, as the agent UID when isolated; nothing it started survives the call.
    Returns the CompletedProcess; raises subprocess.TimeoutExpired past `timeout` seconds, or at once when
    `budget` = (name, seconds) is spent."""
    setup_work()
    if budget is not None:
        name, seconds = budget
        if _budgets.setdefault(name, float(seconds)) <= 0:
            raise subprocess.TimeoutExpired(cmd, 0)
    who = {"user": AGENT_UID, "group": AGENT_UID, "extra_groups": []} if ISOLATED else {}
    proc = subprocess.Popen(cmd, cwd=cwd, env=_env(), text=True, start_new_session=True,
                            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, **who)
    try:
        out, err = proc.communicate(input=stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        reap()  # first: a leftover process could hold the output pipes open
        proc.communicate()
        if budget is not None:
            _budgets[budget[0]] -= timeout
        raise
    finally:
        reap()
    return subprocess.CompletedProcess(cmd, proc.returncode, out, err)


def fresh_run_dir(files=None):
    """A new directory, filled with {relative name: bytes | str (a path to copy)} and then handed to the agent UID.
    Pass agent programs' inputs here, never the agents' own directories."""
    setup_work()
    _counter[0] += 1
    d = os.path.join(_root[0], f"run{_counter[0]}")
    os.makedirs(d)
    for name, content in (files or {}).items():
        p = os.path.join(d, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if isinstance(content, bytes):
            with open(p, "wb") as f:
                f.write(content)
        else:
            shutil.copyfile(content, p)
    if ISOLATED:
        for dirpath, dirs, fs in os.walk(d):
            for n in dirs + fs:
                os.lchown(os.path.join(dirpath, n), AGENT_UID, AGENT_UID)
        os.lchown(d, AGENT_UID, AGENT_UID)
    os.chmod(d, 0o755)
    return d


# --- reading what the agents left -----------------------------------------------------------------------------------

def read_regular(path, limit=64 << 20):
    """Bytes of a regular file the agents left; never through a symlink, never more than `limit`."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError(f"{path} is not a regular file")
        return os.read(fd, limit)
    finally:
        os.close(fd)


def read_text(path, limit=64 << 20):
    return read_regular(path, limit).decode("utf-8", errors="replace")


def read_json(path):
    return json.loads(read_regular(path))


def sha256(path):
    return hashlib.sha256(read_regular(path, 1 << 30)).hexdigest()


def close(got, want, rel=0.005, abs_tol=1e-9):
    """Agreement within a relative tolerance (default 0.5%), for numbers the agent's program reports."""
    return abs(got - want) <= rel * abs(want) + abs_tol
