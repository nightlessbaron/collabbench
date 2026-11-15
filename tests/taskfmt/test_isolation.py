"""collabbench.taskfmt.frontier.isolation: the one module that runs untrusted agent code inside a verifier.

The UID drop, the root lockdown and the UID-wide kill need root, so most of their checks run unprivileged here: the
probe and the drop accept the current user's own UID, and the race-free kill runs inside a private user and PID
namespace (`unshare -r -p`), where this user is root and nothing outside is visible."""

import os
import resource
import subprocess
import sys
import textwrap

import pytest

from collabbench.taskfmt.frontier import isolation as iso


def test_isolation_fails_closed_without_root(monkeypatch):
    monkeypatch.delenv(iso.LOCAL_ENV, raising=False)
    root = os.geteuid() == 0
    assert iso.mode(None) == "none"
    assert iso.mode(64000) == ("isolated" if root else "refuse")
    monkeypatch.setenv(iso.LOCAL_ENV, "1")
    assert iso.mode(64000) == ("isolated" if root else "local")


def test_agent_uid_must_be_unprivileged(tmp_path):
    assert iso.agent_uid(tmp_path) is None
    (tmp_path / iso.UID_FILE).write_text("64000\n")
    assert iso.agent_uid(tmp_path) == 64000
    for bad in ("0", "-5", "root"):
        (tmp_path / iso.UID_FILE).write_text(bad)
        with pytest.raises(ValueError):
            iso.agent_uid(tmp_path)


def test_read_under_never_blocks_and_reads_regular_files_only(tmp_path):
    """A FIFO an agent program leaves where an output belongs must not block root's read (it would hold grading
    until the verifier timeout); a symlink is never followed."""
    os.mkfifo(tmp_path / "fifo")
    (tmp_path / "file").write_bytes(b"x" * 10)
    (tmp_path / "link").symlink_to(tmp_path / "file")
    code = textwrap.dedent(f"""
        import sys
        from collabbench.taskfmt.frontier import isolation as iso
        root = {str(tmp_path)!r}
        assert iso.read_under(root, "file") == b"x" * 10
        assert iso.read_under(root, "file", limit=4) == b"xxxx"
        for bad in ("fifo", "link"):
            try:
                iso.read_under(root, bad)
            except (ValueError, OSError):
                continue
            sys.exit("read " + bad)
        print("OK")
    """)
    run = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=30)
    assert run.stdout.strip() == "OK", run.stderr[-2000:]


@pytest.mark.parametrize("as_uid", [False, True])
def test_read_under_never_leaves_the_trusted_root(tmp_path, as_uid):
    """S1: the agent controls its run directory, so any component of an output's path can be a symlink (out ->
    tests/hidden), a `..`, or a hard link. read_under walks from the trusted root one component at a time without
    following anything, and refuses links, `..`, hard-linked files and other devices. With a UID the walk runs in a
    child that has become that UID (unprivileged: this user), so it can never read more than the agent could."""
    run, secret = tmp_path / "run", tmp_path / "tests" / "hidden"
    (run / "out" / "notation").mkdir(parents=True)
    (run / "out" / "notation" / "w1.json").write_text("mine")
    secret.mkdir(parents=True)
    (secret / "w1.json").write_text("SECRET")
    (run / "evil").symlink_to(secret)
    (run / "deep").mkdir()
    (run / "deep" / "notation").symlink_to(secret)
    os.link(secret / "w1.json", run / "out" / "hard.json")
    uid = os.getuid() if as_uid else None
    assert iso.read_under(run, "out/notation/w1.json", uid=uid) == b"mine"
    for rel in ("evil/w1.json", "deep/notation/w1.json", "../tests/hidden/w1.json", "out/../evil/w1.json",
                "out/./notation/w1.json", str(secret / "w1.json"), "", "out/hard.json", "out/notation"):
        with pytest.raises((ValueError, OSError)):
            iso.read_under(run, rel, uid=uid)


OVERLAY_SCRIPT = textwrap.dedent("""
    set -e
    B="$1"
    mkdir -p "$B/lower" "$B/upperfs" "$B/merged"
    mount -t tmpfs tmpfs "$B/lower"
    mount -t tmpfs tmpfs "$B/upperfs"
    mkdir -p "$B/upperfs/upper" "$B/upperfs/work"
    mount -t overlay overlay -o "lowerdir=$B/lower,upperdir=$B/upperfs/upper,workdir=$B/upperfs/work" "$B/merged"
    mkdir -p "$B/merged/work/run/out"
    printf mine > "$B/merged/work/run/out/w1.json"
    exec "$2" -c "$3" "$B/merged/work"
""")
OVERLAY_READ = textwrap.dedent("""
    import os, sys
    from collabbench.taskfmt.frontier import isolation as iso
    root = sys.argv[1]
    devices = (os.stat(root).st_dev, os.stat(os.path.join(root, "run/out/w1.json")).st_dev)
    print("DEVICES", *devices)
    print(iso.read_under(root, "run/out/w1.json").decode())
""")


def test_read_under_reads_files_on_an_overlay_root(tmp_path):
    """Round 3 (the Modal re-gate): on an overlay root filesystem whose layers sit on different filesystems, as the
    verifier sandbox's is, a directory reports the overlay's device and a file its upper layer's. A same-device check
    then refused every legitimate output. Reproduced in a private user and mount namespace."""
    script = tmp_path / "overlay.sh"
    script.write_text(OVERLAY_SCRIPT)
    (tmp_path / "ovl").mkdir()
    cmd = ["unshare", "-r", "-m", "bash", str(script), str(tmp_path / "ovl"), sys.executable, OVERLAY_READ]
    try:
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        pytest.skip("no unshare")
    if "DEVICES" not in run.stdout:
        pytest.skip(f"no overlay mount in a user namespace here: {run.stderr.strip()[-300:]}")
    devices = run.stdout.split("DEVICES", 1)[1].split()[:2]
    assert devices[0] != devices[1], "this overlay reports one device; the test would not show the bug"
    assert run.stdout.strip().endswith("mine"), (run.stdout, run.stderr[-2000:])


def test_copy_tree_keeps_directories_and_regular_files_only(tmp_path):
    """The one symlink policy: the copy agent programs run from holds directories and regular files; symlinks and
    special files are neither followed nor copied, and are reported so a check can fail on them."""
    src = tmp_path / "src"
    (src / "pkg").mkdir(parents=True)
    (src / "pkg" / "a.py").write_text("A")
    (src / "run.sh").write_text("#!/bin/sh\n")
    (src / "run.sh").chmod(0o700)
    (src / "pkg" / "link.py").symlink_to(src / "pkg" / "a.py")
    (src / "dirlink").symlink_to(src / "pkg")
    os.mkfifo(src / "fifo")
    (src / ".git").mkdir()
    (src / ".git" / "HEAD").write_text("ref")
    (src / "private").mkdir(mode=0o700)  # a reference run as root may leave restrictive modes
    (src / "private" / "out.json").write_text("{}")
    (src / "private" / "out.json").chmod(0o600)
    dst = tmp_path / "dst"
    skipped = iso.copy_tree(src, dst, root_owned=False)
    assert sorted(skipped) == ["dirlink", "fifo", "pkg/link.py"]
    assert sorted(p.relative_to(dst).as_posix() for p in dst.rglob("*")) == [
        "pkg", "pkg/a.py", "private", "private/out.json", "run.sh"]
    assert (dst / "run.sh").stat().st_mode & 0o777 == 0o755 and (dst / "pkg" / "a.py").stat().st_mode & 0o777 == 0o644
    assert (dst / "pkg").stat().st_mode & 0o777 == 0o755  # readable by the agent UID, whatever the source said
    assert (dst / "private").stat().st_mode & 0o777 == 0o755
    assert (dst / "private" / "out.json").stat().st_mode & 0o777 == 0o644


def test_probe_reports_what_the_agent_uid_can_reach(tmp_path):
    """The preflight the seed's test.sh ran: as the agent UID, listing or reading the tests, or writing where grading
    writes, must all fail. Unprivileged, the probe runs as this user, so modes stand in for ownership."""
    tests, out = tmp_path / "tests", tmp_path / "out"
    (tests / "hidden").mkdir(parents=True)
    (tests / "hidden" / "ref_lib.py").write_text("ANSWER = 42\n")
    out.mkdir()
    leaks = iso.probe(os.getuid(), tests, [out])
    assert any("ref_lib.py" in leak for leak in leaks) and any(str(out) in leak for leak in leaks), leaks
    tests.chmod(0)
    out.chmod(0o500)
    try:
        assert iso.probe(os.getuid(), tests, [out]) == []
    finally:
        tests.chmod(0o755)
        out.chmod(0o755)


def test_agent_programs_run_under_limits():
    """popen_kwargs drops to the UID with no supplementary groups, then caps processes (fork bombs), file size and
    core dumps for the program and everything it starts."""
    assert iso.popen_kwargs(64000) == {"user": 64000, "group": 64000, "extra_groups": [],
                                       "preexec_fn": iso.apply_limits}
    code = ("import resource as r; print(*(r.getrlimit(x)[0] for x in "
            "(r.RLIMIT_NPROC, r.RLIMIT_FSIZE, r.RLIMIT_CORE)))")
    run = subprocess.run([sys.executable, "-c", code], preexec_fn=iso.apply_limits, capture_output=True, text=True)
    nproc, fsize, core = map(int, run.stdout.split())
    assert 0 < nproc <= iso.LIMITS[resource.RLIMIT_NPROC] and 0 < fsize <= iso.LIMITS[resource.RLIMIT_FSIZE]
    assert core == 0


NAMESPACE_SCRIPT = textwrap.dedent("""
    import inspect, os, sys, time
    if os.getpid() != 1 or os.geteuid() != 0:
        sys.exit(3)  # not alone in a private PID namespace: never send kill(-1)
    from collabbench.taskfmt.frontier import isolation as iso
    if os.fork() == 0:  # a fork-and-exit chain: always a fresh PID, never two alive for long
        os.setsid()
        while True:
            if os.fork():
                os._exit(0)
    for _ in range(3):  # double-forked setsid daemons
        if os.fork() == 0:
            os.setsid()
            if os.fork() == 0:
                time.sleep(600)
            os._exit(0)
    time.sleep(0.5)
    spare = {"spare": 0} if "spare" in inspect.signature(iso._kill_uid).parameters else {}
    iso._kill_uid(0, **spare)  # uid 0 is this user, mapped; this process is the namespace's init, which kill(-1) spares
    end = time.time() + 5
    while time.time() < end:
        try:
            while os.waitpid(-1, os.WNOHANG)[0]:
                pass
        except ChildProcessError:
            pass
        left = [p for p in os.listdir("/proc") if p.isdigit() and int(p) != 1]
        if not left:
            print("CLEAN")
            sys.exit(0)
        time.sleep(0.05)
    print("LEFT", left)
    sys.exit(1)
""")


STOPPER_SCRIPT = textwrap.dedent("""
    import inspect, os, signal, sys, time
    if os.getpid() != 1 or os.geteuid() != 0:
        sys.exit(3)  # not alone in a private PID namespace: never send kill(-1)
    from collabbench.taskfmt.frontier import isolation as iso
    signal.signal(signal.SIGALRM, lambda *_: os._exit(9))  # init ignores a default-action SIGALRM
    signal.alarm(60)  # a hang ends here

    def stopper():  # an agent process that stops every process it may signal, over and over
        if os.fork() == 0:
            os.setsid()
            while True:
                try:
                    os.kill(-1, signal.SIGSTOP)
                except OSError:
                    pass
        time.sleep(0.3)

    spare = {"spare": 0} if "spare" in inspect.signature(iso._kill_uid).parameters else {}
    t0 = time.monotonic()
    stopper()
    iso._kill_uid(0, **spare)
    print("KILL", round(time.monotonic() - t0, 1), flush=True)
    t0 = time.monotonic()
    stopper()
    try:
        iso.read_under(sys.argv[1], "f", uid=0, **spare)
        outcome = "read"
    except (ValueError, OSError):
        outcome = "refused"
    print("READ", outcome, round(time.monotonic() - t0, 1), flush=True)
""")


def test_helpers_as_the_agent_uid_cannot_be_stopped_into_a_hang(tmp_path):
    """N1: the killer and the reader act with the agent UID's rights, so an agent process looping kill(-1, SIGSTOP)
    could stop them, and an unbounded wait then hangs grading past the verifier timeout. Each wait is bounded: past
    its deadline the child is killed as root, and the read fails (that output fails) rather than hanging. Here, in a
    private user and PID namespace, everything is UID 0, so the stopper can stop the helpers; in the verifier their
    real UID is a spare one the agent cannot signal at all (not testable without root)."""
    script = tmp_path / "stop.py"
    script.write_text(STOPPER_SCRIPT)
    (tmp_path / "f").write_text("x")
    cmd = ["unshare", "-r", "-p", "-f", "--kill-child", "--mount-proc", sys.executable, str(script), str(tmp_path)]
    try:
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except FileNotFoundError:
        pytest.skip("no unshare")
    if run.returncode == 3 or "unshare:" in run.stderr:
        pytest.skip(f"no private user and PID namespace here: {run.stderr.strip()[:200]}")
    lines = dict(line.split(" ", 1) for line in run.stdout.splitlines() if " " in line)
    assert "KILL" in lines and float(lines["KILL"]) < 15, (run.returncode, run.stdout, run.stderr[-1500:])
    assert "READ" in lines and float(lines["READ"].split()[-1]) < 15, (run.returncode, run.stdout, run.stderr[-1500:])


def test_kill_uid_is_race_free_against_a_fork_chain(tmp_path):
    """M2: a process that forks and exits in a loop can slip past a /proc scan. On Linux, kill(-1) from the agent
    UID walks the process list under the kernel's lock, and a fork with SIGKILL pending fails, so one pass leaves
    nothing. (gVisor, which Modal runs, signals a snapshot of the list instead; see isolation.reap.)"""
    script = tmp_path / "ns.py"
    script.write_text(NAMESPACE_SCRIPT)
    cmd = ["unshare", "-r", "-p", "-f", "--kill-child", "--mount-proc", sys.executable, str(script)]
    try:
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        pytest.skip("no unshare")
    if run.returncode == 3 or "unshare:" in run.stderr:
        pytest.skip(f"no private user and PID namespace here: {run.stderr.strip()[:200]}")
    assert run.stdout.strip() == "CLEAN", (run.stdout, run.stderr[-2000:])
