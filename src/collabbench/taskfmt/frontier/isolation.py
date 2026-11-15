"""Run untrusted agent code inside a CollabBench verifier.

One module, used by the kit's grade.py and by every task harness that runs agent programs during grading (the Inspire
frontier tasks; the Pool tasks to come). Standard library only: write_task ships it as tests/isolation.py, and
grade.py and tests/hidden/harness.py load that file.

A task opts in by naming a dedicated unprivileged UID in tests/agent_uid. The interface:
- agent_uid(tests) -> the UID, or None when the task does not opt in.
- mode(uid) -> "isolated" (the verifier is root: agent code runs as the UID), "local" (no root, but LOCAL_ENV=1, as
  localcheck sets it: agent code runs as the current user, so a changed tests directory can only be detected), "refuse"
  (no root and no override: agent code must not run), or "none" (no UID).
- lockdown(tests, unwritable) -> before any agent code runs: `tests` root-owned with no access for anyone else
  (strict: an error is raised); each of `unwritable` root-owned and not group- or world-writable (best effort, for
  mounts that refuse a chown).
- probe(uid, tests, unwritable) -> as the UID, everything it must not be able to do (list or read the tests, create a
  file in the tests or in `unwritable`) that it can; empty when it is shut out.
- popen_kwargs(uid) -> Popen arguments that run a program as the UID and GID, with no supplementary groups and LIMITS
  set after the drop (processes, so a fork bomb stops; file size; no core dumps).
- become_subreaper() -> orphaned descendants of this process are reparented to it, not to init.
- reap(uid) -> kill every descendant of this process and, with a UID (root only), every process of that UID: a forked
  helper acting as the UID sends kill(-1, SIGKILL), root kills what a /proc scan still finds, and this repeats until
  CLEAN_ROUNDS rounds in a row find nothing (or wait_s passes). On Linux one kill(-1) is atomic against fork (the
  kernel walks the process list under its tasklist lock, and a fork with SIGKILL pending fails). gVisor, which Modal
  runs, signals a snapshot of the list, so there a fork-and-exit chain can slip one pass; the remaining window is a
  chain that slips two kill passes and two scans in a row. Such a survivor runs as the UID, so it can touch neither
  the tests nor the output directory. Returns (found, survivors); a caller must treat survivors as a failed grade.
- Helpers that act as the UID (the kill, read_under, probe) run in forked children, and every wait on them is
  bounded (KILL_WAIT_S, READ_WAIT_S, PROBE_WAIT_S): past it the child is killed as root. The kill and read helpers
  take the UID only as their effective UID: their real and saved UID is a spare one (uid + 1, which nothing runs as),
  so no agent process can signal them (a SIGSTOP loop cannot stall grading).
- give(path, uid) -> hand a fresh run directory (filled by root) and everything in it to the UID; the only chown to
  the UID there is.
- copy_tree(src, dst, root_owned) -> the one symlink policy: the tree agent programs run from holds directories and
  regular files only. Symlinks, FIFOs, sockets and devices are never followed and never copied; their paths are
  returned, so a check can fail on them. `.git` is skipped.
- read_under(root, rel, limit, uid) -> the bytes of a file an agent program left at `rel` beneath `root`, a
  directory the grader trusts (the agent may control everything inside it). The path is walked from `root` one
  component at a time without following anything (O_DIRECTORY | O_NOFOLLOW per directory; O_NOFOLLOW | O_NONBLOCK
  for the file), and `..`, `.`, empty and absolute paths, symlinks anywhere on the path, non-regular files (a FIFO is
  refused at once) and hard-linked files are refused. (Not a device check: on an overlay root filesystem a directory
  reports the overlay's device and a file its layer's, and the agent cannot mount anything.) At most `limit` bytes.
  With `uid` (root only; or this user's own UID) the whole read runs in a helper with that UID's file rights, so it
  can never read more than the agent could: the tests are closed to it. A read that does not finish in time raises
  ValueError, so that output fails; it is never a verifier error.
"""

import ctypes
import json
import os
import resource
import select
import shutil
import signal
import stat
import time
from pathlib import Path

UID_FILE = "agent_uid"
LOCAL_ENV = "COLLAB_LOCAL_GRADING"
LIMITS = {resource.RLIMIT_NPROC: 512, resource.RLIMIT_FSIZE: 1 << 30, resource.RLIMIT_CORE: 0}
KILL_WAIT_S, KILL_ATTEMPTS = 2.0, 3  # a UID-wide kill helper: per attempt
READ_WAIT_S, READ_ATTEMPTS = 3.0, 2  # a read helper: per attempt; then that output fails
PROBE_WAIT_S = 10.0
CLEAN_ROUNDS = 2  # kill-and-scan rounds in a row that must find nothing (gVisor: see reap)


def agent_uid(tests) -> int | None:
    path = Path(tests) / UID_FILE
    if not path.exists():
        return None
    uid = int(path.read_text().strip())
    if uid <= 0:
        raise ValueError(f"{path}: the agent UID must be an unprivileged user, not {uid}")
    return uid


def mode(uid: int | None) -> str:
    if uid is None:
        return "none"
    if os.geteuid() == 0:
        return "isolated"
    return "local" if os.environ.get(LOCAL_ENV) == "1" else "refuse"


# --- the filesystem -------------------------------------------------------------------------------------------------

def _lock(path: Path, mode_mask: int, recursive: bool, strict: bool) -> None:
    path = Path(path)
    if not path.exists() or path.is_symlink():
        return
    for p in [path] + (list(path.rglob("*")) if recursive and path.is_dir() else []):  # rglob never enters a link
        if p.is_symlink():
            continue
        try:
            os.chown(p, 0, 0)
            os.chmod(p, stat.S_IMODE(p.lstat().st_mode) & ~mode_mask)
        except OSError:
            if strict:
                raise


def lockdown(tests, unwritable=()) -> None:
    _lock(tests, 0o077, recursive=True, strict=True)
    for path in unwritable:
        path = Path(path)
        _lock(path.parent, 0o022, recursive=False, strict=False)  # so the directory cannot be renamed away
        _lock(path, 0o022, recursive=True, strict=False)


def give(path, uid: int) -> None:
    for dirpath, dirnames, filenames in os.walk(path, followlinks=False):
        for name in dirnames + filenames:
            os.lchown(os.path.join(dirpath, name), uid, uid)
    os.lchown(path, uid, uid)


def copy_tree(src, dst, root_owned: bool) -> list[str]:
    src, dst = Path(src), Path(dst)
    skipped = []
    os.makedirs(dst)
    for dirpath, dirnames, filenames in os.walk(src, followlinks=False):
        rel = Path(dirpath).relative_to(src)
        for name in sorted(dirnames):
            if name == ".git":
                dirnames.remove(name)
            elif os.path.islink(os.path.join(dirpath, name)):
                dirnames.remove(name)
                skipped.append((rel / name).as_posix())
            else:
                os.mkdir(dst / rel / name)
        for name in filenames:
            source = os.path.join(dirpath, name)
            if not stat.S_ISREG(os.lstat(source).st_mode):
                skipped.append((rel / name).as_posix())
                continue
            fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            try:
                if not stat.S_ISREG(os.fstat(fd).st_mode):
                    skipped.append((rel / name).as_posix())
                    continue
                executable = os.fstat(fd).st_mode & 0o111
                with os.fdopen(os.dup(fd), "rb") as reader, open(dst / rel / name, "wb") as writer:
                    shutil.copyfileobj(reader, writer)
            finally:
                os.close(fd)
            os.chmod(dst / rel / name, 0o755 if executable else 0o644)
    for p in [dst, *dst.rglob("*")]:
        if p.is_dir():
            os.chmod(p, 0o755)
        if root_owned:
            os.chown(p, 0, 0)
    return sorted(skipped)


def _components(rel) -> list[str]:
    rel = os.fspath(rel)
    parts = rel.split("/")
    if not rel or rel.startswith("/") or any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"not a plain relative path: {rel!r}")
    return parts


def _walk_read(root, parts: list[str], limit: int) -> bytes:
    fds = [os.open(root, os.O_RDONLY | os.O_DIRECTORY)]
    try:
        for part in parts[:-1]:
            fds.append(os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fds[-1]))
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fds[-1])
        fds.append(fd)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise ValueError(f"{'/'.join(parts)} is not a regular file")
        if info.st_nlink != 1:  # the same inode also lives outside the walk
            raise ValueError(f"{'/'.join(parts)} is hard-linked")
        chunks, left = [], limit
        while left > 0:
            chunk = os.read(fd, min(left, 1 << 20))
            if not chunk:
                break
            chunks.append(chunk)
            left -= len(chunk)
        return b"".join(chunks)
    finally:
        for fd in reversed(fds):
            os.close(fd)


def read_under(root, rel, limit: int = 64 << 20, uid: int | None = None, spare: int | None = None) -> bytes:
    parts = _components(rel)
    if uid is None:
        return _walk_read(root, parts, limit)
    for _ in range(READ_ATTEMPTS):
        data = _in_helper(lambda: _walk_read(root, parts, limit), uid, _spare(uid, spare), READ_WAIT_S)
        if data is not None:
            return data
    raise ValueError(f"{rel}: the read timed out")


# --- the agent UID --------------------------------------------------------------------------------------------------

def _drop_groups() -> None:
    try:
        os.setgroups([])
    except PermissionError:
        try:  # only where nobody may change groups (an unprivileged user namespace): the groups are then inert
            denied = Path("/proc/self/setgroups").read_text().strip() == "deny"
        except OSError:
            denied = False
        if not denied:
            raise


def _spare(uid: int, spare: int | None) -> int:
    return uid + 1 if spare is None else spare


def _become(uid: int, spare: int | None = None) -> None:
    """In a forked child of root: take `uid`'s rights, with no supplementary groups. With `spare`, only as the
    effective (and file-system) UID and GID: the real and saved IDs become `spare`, a UID no process runs as. Files
    are then opened, and signals sent, with `uid`'s rights, but no process of `uid` can signal or trace this one
    (Linux and gVisor let a process signal another only when its real or effective UID matches the target's real or
    saved UID). Unprivileged, only the current user's own UID is accepted, and nothing changes."""
    if os.geteuid() != 0:
        if uid != os.getuid():
            raise PermissionError(f"cannot become UID {uid} without root")
        return
    _drop_groups()
    if spare is None:
        os.setgid(uid)
        os.setuid(uid)
    else:
        os.setresgid(spare, uid, spare)
        os.setresuid(spare, uid, spare)


def _wait(pid: int, seconds: float):
    """The child's wait status, or None if it has not ended within `seconds` (never a blocking wait)."""
    end = time.monotonic() + seconds
    while True:
        try:
            done, status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return 0
        if done:
            return status
        if time.monotonic() > end:
            return None
        time.sleep(0.002)


def _finish(pid: int, seconds: float):
    """Wait for a helper child at most `seconds`; then kill it as root (stopped or not) and wait as long again."""
    status = _wait(pid, seconds)
    if status is None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        status = _wait(pid, seconds)
    return status


def _in_helper(work, uid: int, spare: int | None, seconds: float) -> bytes | None:
    """Run `work()` (returning bytes) in a forked child that has become `uid` (see _become), and return its bytes;
    None when they did not arrive within `seconds` (the child is then killed as root). The child's own error is
    raised here as ValueError."""
    read, write = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(read)
        try:
            _become(uid, spare)
            payload = b"0" + work()
        except BaseException as e:  # noqa: BLE001 - reported to the parent, which raises
            payload = b"1" + f"{type(e).__name__}: {e}".encode()
        try:
            view = memoryview(payload)
            while view:
                view = view[os.write(write, view):]
        finally:
            os._exit(0)
    os.close(write)
    chunks, complete, end = [], False, time.monotonic() + seconds
    try:
        while time.monotonic() < end:
            ready, _, _ = select.select([read], [], [], min(0.5, max(0.0, end - time.monotonic())))
            if ready:
                chunk = os.read(read, 1 << 20)
                if not chunk:
                    complete = True
                    break
                chunks.append(chunk)
    finally:
        os.close(read)
    if not complete:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    _finish(pid, 1.0)
    if not complete:
        return None
    payload = b"".join(chunks)
    if payload[:1] == b"0":
        return payload[1:]
    raise ValueError(payload[1:].decode("utf-8", "replace") or "the helper died")


def apply_limits() -> None:
    for limit, value in LIMITS.items():
        _, hard = resource.getrlimit(limit)
        value = value if hard == resource.RLIM_INFINITY else min(value, hard)
        resource.setrlimit(limit, (value, value))


def popen_kwargs(uid: int) -> dict:
    return {"user": uid, "group": uid, "extra_groups": [], "preexec_fn": apply_limits}


def probe(uid: int, tests, unwritable=()) -> list[str]:
    tests = Path(tests)
    dirs, files = [tests], []
    for dirpath, dirnames, filenames in os.walk(tests, followlinks=False):
        dirs += [Path(dirpath) / n for n in dirnames]
        files += [Path(dirpath) / n for n in filenames]

    def attempt() -> bytes:
        leaks = []
        for d in dirs:
            try:
                os.listdir(d)
                leaks.append(f"list {d}")
            except OSError:
                pass
        for f in files:
            try:
                os.close(os.open(f, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK))
                leaks.append(f"read {f}")
            except OSError:
                pass
        for d in [tests, *map(Path, unwritable)]:
            target = d / f".isolation-probe-{os.getpid()}"
            try:
                os.close(os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
                os.unlink(target)
                leaks.append(f"write {d}")
            except OSError:
                pass
        return json.dumps(leaks).encode()

    try:  # as the UID itself (real and effective): exactly the agent's access; no agent process exists yet
        data = _in_helper(attempt, uid, None, PROBE_WAIT_S)
    except ValueError as e:  # a probe that cannot run is a leak, never a pass
        return [f"probe failed: {e}"]
    return json.loads(data) if data is not None else ["probe timed out"]


# --- processes ------------------------------------------------------------------------------------------------------

def become_subreaper() -> None:
    try:  # PR_SET_CHILD_SUBREAPER
        ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)
    except Exception:  # noqa: BLE001 - not Linux; the UID kill still applies
        pass


def _procs() -> dict[int, tuple[int, set[int], str]]:
    """{pid: (ppid, {real, effective, saved, fs uid}, state)}, from /proc/<pid>/status, which root reads even for a
    process that made itself non-dumpable (its /proc directory then belongs to root)."""
    out = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/status") as f:
                fields = dict(line.split(":", 1) for line in f if ":" in line)
            out[int(name)] = (int(fields["PPid"]), {int(u) for u in fields["Uid"].split()}, fields["State"].split()[0])
        except (OSError, KeyError, ValueError):
            pass
    return out


def _alive(uid: int | None) -> set[int]:
    procs, me = _procs(), os.getpid()
    children: dict[int, list[int]] = {}
    for pid, (ppid, _, _) in procs.items():
        children.setdefault(ppid, []).append(pid)
    found, stack = set(), list(children.get(me, []))
    while stack:
        pid = stack.pop()
        if pid not in found:
            found.add(pid)
            stack.extend(children.get(pid, []))
    if uid is not None:
        found |= {pid for pid, (_, uids, _) in procs.items() if uid in uids}
    return {pid for pid in found if pid != me and pid in procs and procs[pid][2] not in ("Z", "X")}


def _collect_zombies() -> None:
    while True:
        try:
            pid, _ = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        if pid == 0:
            return


def _kill_uid(uid: int, spare: int | None = None) -> bool:
    """Fork a helper that acts as `uid` (real UID `spare`, so no process of `uid` can stop it) and sends SIGKILL to
    every process it may signal. Every wait is bounded: a helper that has not finished within KILL_WAIT_S is killed
    as root and the kill retried, up to KILL_ATTEMPTS times. True once a helper finished its kill. Root only:
    unprivileged, kill(-1) would reach every process of the current user."""
    if os.geteuid() != 0:
        raise PermissionError("the UID-wide kill needs root")
    for _ in range(KILL_ATTEMPTS):
        pid = os.fork()
        if pid == 0:
            try:
                _become(uid, _spare(uid, spare))
            except BaseException:  # noqa: BLE001 - never signal as root
                os._exit(1)
            try:
                os.kill(-1, signal.SIGKILL)
                os.kill(-1, signal.SIGKILL)
            except BaseException:  # noqa: BLE001 - ESRCH: nothing left to signal (gVisor reports it)
                pass
            os._exit(0)
        status = _finish(pid, KILL_WAIT_S)
        if status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0:
            return True
    return False


def reap(uid: int | None = None, wait_s: float = 10.0) -> tuple[int, int]:
    if uid is not None and uid <= 0:
        raise ValueError(f"refusing to sweep UID {uid}")
    _collect_zombies()
    found = _alive(uid)
    end = time.monotonic() + wait_s
    needed, clean = (CLEAN_ROUNDS if uid is not None else 1), 0
    while True:
        if uid is not None:
            _kill_uid(uid)
        for pid in _alive(uid):
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        if found or uid is not None:
            time.sleep(0.01)
        _collect_zombies()
        alive = _alive(uid)
        found |= alive
        clean = 0 if alive else clean + 1
        if clean >= needed:
            return len(found), 0
        if time.monotonic() > end:
            return len(found), len(alive)
