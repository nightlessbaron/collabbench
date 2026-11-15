"""How the hidden tests run the agents' programs: the taskmaker.frontier verifier kit (harness.py), adapted to the
CollabBench verifier.

The seed kit ran agent code as an unprivileged user (setpriv, chown, a reaper). The CollabBench verifier runs the
hidden suite as one user, so agent code runs as that user, with these guards kept: a fresh directory per run filled
before the run, a clean environment, its own session, and the whole process group killed after each run. Files the
agents left are read without following symlinks, and nothing they wrote is imported by the tests.

One addition: the kit gives a whole score 900 s, so a program that hangs must not take every other deliverable's
credit with it. run_agent takes an optional `budget` (a name and seconds): time lost to that program's timeouts is
charged to it, and once the budget is spent its remaining runs fail as timeouts without being started.
"""

import hashlib
import json
import os
import shutil
import signal
import stat
import subprocess
import sys
import tempfile

WORKSPACE = os.environ.get("COLLAB_WORKSPACE", "/workspace")
PYTHON = sys.executable  # the verifier's Python 3.12, standard library plus pytest and numpy
_root = [None]
_counter = [0]
_budgets = {}


def ws(*parts):
    """A path inside the workspace being graded."""
    return os.path.join(WORKSPACE, *parts)


def setup_work():
    """Call once per session (a session-scoped autouse fixture) before any run_agent."""
    if _root[0] is None:
        _root[0] = tempfile.mkdtemp(prefix="verify_work_")


def _env():
    bindir = os.path.dirname(PYTHON)
    return {"PATH": f"{bindir}:/usr/local/bin:/usr/bin:/bin", "HOME": _root[0], "LANG": "C.UTF-8",
            "PYTHONDONTWRITEBYTECODE": "1"}


def _kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_agent(cmd, cwd, timeout, stdin=None, budget=None):
    """Run agent code (an argv list) in `cwd`; nothing it started survives the call. Returns the CompletedProcess;
    raises subprocess.TimeoutExpired past `timeout` seconds, or at once when `budget` = (name, seconds) is spent."""
    if budget is not None:
        name, seconds = budget
        if _budgets.setdefault(name, float(seconds)) <= 0:
            raise subprocess.TimeoutExpired(cmd, 0)
    proc = subprocess.Popen(cmd, cwd=cwd, env=_env(), text=True, start_new_session=True,
                            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = proc.communicate(input=stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_group(proc)
        proc.communicate()
        if budget is not None:
            _budgets[budget[0]] -= timeout
        raise
    finally:
        _kill_group(proc)
    return subprocess.CompletedProcess(cmd, proc.returncode, out, err)


def fresh_run_dir(files=None):
    """A new directory, filled with {relative name: bytes | str (a path to copy)}. Pass agent programs' inputs here,
    never the agents' own directories."""
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
    return d


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
