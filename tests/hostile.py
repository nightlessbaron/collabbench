"""A hostile agent program, for the verifier-isolation tests.

`program(...)` is Python source an agent could leave in its workspace for the verifier to run. When it runs it
rewrites files under the tests directory (expected_tests.json and score.py) and leaves a double-forked, setsid daemon
with its stdio closed. The daemon waits for reward.json in the verifier's output directory and overwrites it with a
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


def program(tests: str, out: str, expected: list[str], daemon: bool = True) -> str:
    """Source that rewrites `tests` (expected_tests.json := `expected`; score.py always scores 1.0) and, with
    `daemon`, leaves the daemon watching `out`. Append the module's ordinary code after it."""
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
    return src


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
