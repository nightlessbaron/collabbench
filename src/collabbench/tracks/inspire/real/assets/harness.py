"""How the hidden tests run the agents' programs: the taskmaker.frontier verifier kit (harness.py), adapted to the
CollabBench verifier. Every isolation primitive comes from tests/isolation.py, the kit's copy of
collabbench.taskfmt.frontier.isolation, shared with grade.py.

Isolation (as the seed kit had it). The task names a dedicated unprivileged UID in tests/agent_uid. When the verifier
runs as root, as it does in the verifier container (isolation.mode is "isolated"):
- every agent program runs as that UID and GID with no supplementary groups, under isolation.LIMITS;
- before any agent program runs, the tests directory (graders, reference libraries, expected_tests.json, score
  modules) is closed to that UID, and /logs/verifier made unwritable for it (grade.py has done so already, and has
  probed it as the UID);
- each run gets a fresh directory, filled first and then handed to that UID (isolation.give), the only thing it owns;
- the graded workspace is copied first (isolation.copy_tree) into a root-owned, read-only tree that the programs run
  from, so a program can neither change what is graded nor write next to it. The copy holds directories and regular
  files only: symlinks and special files are dropped, and listed in SKIPPED for checks that must fail on them;
- a program's output goes to files, read back at most OUTPUT_LIMIT bytes, so no output size can exhaust memory;
- files the programs leave are read back through isolation.read_under (read_regular, sha256), which has two layers:
  the walk from the work root refuses every symlink by lstat and identity checks on each component (on every
  platform, gVisor included, where a no-follow open alone is not honoured for directories), and the read runs as
  the agent UID, so even a link the walk missed could reach nothing the agents cannot already read: never the
  tests. grade.py checks the walk per trial on the grading platform (reward.json: nofollow_ok);
- after every run, every process of the UID and every descendant of this process (a child subreaper) is killed
  (isolation.reap), and the run returns only once none is left.
Without root, agent programs run only under explicit local grading (isolation.LOCAL_ENV, as localcheck sets it), as
the current user; then only the descendant reaping and the read-only copy apply, and grade.py detects a changed tests
directory instead of preventing it. Otherwise ("refuse") no agent program runs.

One addition: the kit gives a whole score 900 s, so a program that hangs must not take every other deliverable's
credit with it. run_agent takes an optional `budget` (a name and seconds): time lost to that program's timeouts is
charged to it, and once the budget is spent its remaining runs fail as timeouts without being started.
"""

import atexit
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TESTS = Path(__file__).resolve().parent.parent  # tests/: score.py, pytest_score.py, grade.py, isolation.py, hidden/
_spec = importlib.util.spec_from_file_location("isolation", TESTS / "isolation.py")  # by path: never the workspace's
iso = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(iso)

ORIGINAL = os.environ.get("COLLAB_WORKSPACE", "/workspace")  # the workspace grade.py asked us to score
PYTHON = sys.executable  # the verifier's Python 3.12, standard library plus pytest and numpy
LOGS = Path("/logs/verifier")
OUTPUT_LIMIT = 16 << 20

AGENT_UID = iso.agent_uid(TESTS)
MODE = iso.mode(AGENT_UID)
ISOLATED = MODE == "isolated"
WORKSPACE = ORIGINAL  # replaced by the read-only copy in setup_work
SKIPPED = []  # workspace paths the copy dropped: symlinks and special files
_root = [None]
_counter = [0]
_budgets = {}


def ws(*parts):
    """A path inside the (copied) workspace being graded."""
    return os.path.join(WORKSPACE, *parts)


def skipped(prefix):
    """Paths under workspace directory `prefix` that the graded copy dropped (symlinks, FIFOs, devices)."""
    return [p for p in SKIPPED if p == prefix or p.startswith(prefix.rstrip("/") + "/")]


def setup_work():
    """Call once per session (a session-scoped autouse fixture) before any run_agent."""
    global WORKSPACE
    if _root[0] is not None:
        return
    iso.become_subreaper()
    if ISOLATED:
        iso.lockdown(TESTS, [LOGS])
    root = tempfile.mkdtemp(prefix="verify_work_")
    os.chmod(root, 0o755)
    _root[0] = root
    if os.path.isdir(ORIGINAL):
        WORKSPACE = os.path.join(root, "workspace")
        SKIPPED[:] = iso.copy_tree(ORIGINAL, WORKSPACE, root_owned=ISOLATED)


def _cleanup():
    if _root[0] is not None:
        shutil.rmtree(_root[0], ignore_errors=True)


atexit.register(_cleanup)  # the copy and every run directory go with the session


def _env():
    bindir = os.path.dirname(PYTHON)
    return {"PATH": f"{bindir}:/usr/local/bin:/usr/bin:/bin", "HOME": _root[0], "LANG": "C.UTF-8",
            "PYTHONDONTWRITEBYTECODE": "1"}


def reap():
    found, survivors = iso.reap(AGENT_UID if ISOLATED else None)
    if survivors:
        raise RuntimeError(f"{survivors} agent processes survive every kill")


def _read_back(f):
    f.seek(0)
    data = f.read(OUTPUT_LIMIT)
    return data.decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "\n")


def run_agent(cmd, cwd, timeout, stdin=None, budget=None):
    """Run agent code (an argv list) in `cwd`, as the agent UID when isolated; nothing it started survives the call.
    Returns a CompletedProcess with text output (at most OUTPUT_LIMIT bytes of each stream); raises
    subprocess.TimeoutExpired past `timeout` seconds, or at once when `budget` = (name, seconds) is spent."""
    if MODE == "refuse":
        raise RuntimeError(f"refusing to run agent code unisolated (not root; {iso.LOCAL_ENV} unset)")
    setup_work()
    if budget is not None:
        name, seconds = budget
        if _budgets.setdefault(name, float(seconds)) <= 0:
            raise subprocess.TimeoutExpired(cmd, 0)
    who = iso.popen_kwargs(AGENT_UID) if ISOLATED else {}
    with tempfile.TemporaryFile(dir=_root[0]) as out, tempfile.TemporaryFile(dir=_root[0]) as err:
        proc = subprocess.Popen(cmd, cwd=cwd, env=_env(), start_new_session=True, stdout=out, stderr=err,
                                stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL, **who)
        try:
            proc.communicate(input=stdin.encode() if isinstance(stdin, str) else stdin, timeout=timeout)
        except subprocess.TimeoutExpired:
            reap()
            proc.wait()
            if budget is not None:
                _budgets[budget[0]] -= timeout
            raise
        finally:
            reap()
        return subprocess.CompletedProcess(cmd, proc.returncode, _read_back(out), _read_back(err))


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
        with open(p, "wb") as f:
            f.write(content if isinstance(content, bytes) else Path(content).read_bytes())
    os.chmod(d, 0o755)
    if ISOLATED:
        iso.give(d, AGENT_UID)
    return d


# --- reading what the agents left -----------------------------------------------------------------------------------

def read_regular(path, limit=64 << 20):
    """Bytes of a regular file the agents left, in the graded copy or a run directory: read as the agent UID when
    isolated (never more than the agents could read), walked from the work root refusing every link, never
    blocking, never more than `limit` (isolation.read_under). Any other path is refused."""
    rel = _rel(path)  # first: it sets up the work root
    return iso.read_under(_root[0], rel, limit, uid=AGENT_UID if ISOLATED else None)


def _rel(path):
    """`path` relative to the work root; refused unless it lies beneath it."""
    setup_work()
    path = os.fspath(path)
    rel = os.path.relpath(path, _root[0]) if os.path.isabs(path) and ".." not in path.split("/") else ".."
    if rel == ".." or rel.startswith("../"):
        raise ValueError(f"{path} is not in the graded workspace or a run directory")
    return rel


def read_text(path, limit=64 << 20):
    return read_regular(path, limit).decode("utf-8", errors="replace")


def read_json(path):
    return json.loads(read_regular(path))


def sha256(path):
    """Hex sha256 of a file the agents left (up to 1 GiB), read like read_regular but hashed where it is read: only
    the digest crosses back from the helper (isolation.hash_under)."""
    rel = _rel(path)
    return iso.hash_under(_root[0], rel, uid=AGENT_UID if ISOLATED else None)


def close(got, want, rel=0.005, abs_tol=1e-9):
    """Agreement within a relative tolerance (default 0.5%), for numbers the agent's program reports."""
    return abs(got - want) <= rel * abs(want) + abs_tol
