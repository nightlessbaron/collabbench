"""CollabBench grader (runs in the verifier container, stdlib only).

Scores the final workspace and every snapshot listed in the snapshots index. Each score runs in its own Python process
(`--score-one`), so snapshots never share imported modules. Writes reward.json (numbers Harbor keeps) and details.json
(per-requirement results and the snapshot trace).

Agent code that runs during grading must not change the grade, nor cost the trial:
- a task that names an agent UID (tests/agent_uid) is graded only isolated: as root, after isolation.lockdown and a
  passing isolation.probe, with agent code running as that UID. Without root it is graded only when local grading is
  asked for explicitly (isolation.LOCAL_ENV, as localcheck sets it); otherwise grading refuses (`verifier_error`) and
  no agent code runs. reward.json records `isolated` (1/0) for every such task;
- the tripwire is read, and the tests directory digested, before anything is scored;
- a zero reward (`grading_incomplete`) is written before any agent code runs, so a grader killed or crashed after
  that point still leaves a reward that counts;
- the final workspace is scored first and its reward.json written; snapshots are scored only while the deadline
  (--deadline, set below the verifier timeout) allows, the rest marked (`snapshots_truncated`);
- a score that times out is the agents' doing: it scores 0 (`score_timeout`), it is not a verifier error;
- this process is a child subreaper: after every score it kills whatever the score left running
  (isolation.reap: every descendant, and every process of the agent UID), and reward.json is written only once
  nothing is left;
- a tests directory that changed during grading voids the grade (`tests_tampered`), and so does an agent process
  that survives every kill (`agent_processes_survived`): the reward, every requirement and every score extra are
  zeroed. Both are the agents' doing, so the trial counts, at 0.
"""

import sys

sys.dont_write_bytecode = True  # nothing is written into tests/ (it is baked into the verifier image)

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import subprocess  # noqa: E402
import tarfile  # noqa: E402
import tempfile  # noqa: E402
import time  # noqa: E402
from pathlib import Path  # noqa: E402

import isolation  # noqa: E402  tests/isolation.py, next to this file

HERE = Path(__file__).resolve().parent
SCORE_TIMEOUT_S = 900
NOT_A_SCORE = ("tests_total",)  # extras kept when a grade is voided


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


def safe_score(workspace: Path, timeout_s: float = SCORE_TIMEOUT_S) -> dict:
    try:
        run = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--score-one", str(workspace)],
                             capture_output=True, text=True, timeout=max(1.0, timeout_s))
        if run.returncode != 0:
            return {"reward": 0.0, "requirements": {}, "extras": {}, "error": run.stderr[-2000:]}
        return json.loads(run.stdout.strip().splitlines()[-1])
    except subprocess.TimeoutExpired:
        return {"reward": 0.0, "requirements": {}, "extras": {}, "timeout": True,
                "error": f"score timed out after {timeout_s:.0f} s"}
    except Exception as e:  # bad output
        return {"reward": 0.0, "requirements": {}, "extras": {}, "error": f"{type(e).__name__}: {e}"}


def _write(out: Path, name: str, body: str) -> None:
    (out / name).unlink(missing_ok=True)  # whatever stands there now (a symlink, a FIFO) is not ours
    (out / name).write_text(body)


def grade(workspace: Path, snapshots: Path, tripwire: Path, out: Path, deadline_s: float | None = None) -> dict:
    start = time.monotonic()
    deadline = start + deadline_s if deadline_s else None
    reserve = min(30.0, 0.1 * deadline_s) if deadline_s else 0.0

    def budget() -> float:
        return SCORE_TIMEOUT_S if deadline is None else min(SCORE_TIMEOUT_S, deadline - time.monotonic() - reserve)

    uid = isolation.agent_uid(HERE)
    mode = isolation.mode(uid)
    record = {} if uid is None else {"isolated": int(mode == "isolated")}
    isolation.become_subreaper()
    out.mkdir(parents=True, exist_ok=True)
    if mode == "refuse":
        why = "the task runs agent code as its agent UID, and the verifier is not root"
        _write(out, "reward.json", json.dumps({"reward": 0.0, "verifier_error": 1, **record}))
        _write(out, "details.json", json.dumps({"error": why}))
        return {"reward": 0.0, "verifier_error": 1, **record}
    if mode == "isolated":  # before any agent code runs
        isolation.lockdown(HERE, [out, workspace, snapshots, tripwire])
        leaks = isolation.probe(uid, HERE, [out, workspace, snapshots])
        if leaks:
            _write(out, "reward.json", json.dumps({"reward": 0.0, "verifier_error": 1, **record}))
            _write(out, "details.json", json.dumps({"error": "the agent UID is not shut out", "probe": leaks}))
            return {"reward": 0.0, "verifier_error": 1, **record}
    sweep = uid if mode == "isolated" else None
    digest = tests_digest()
    lines = tripwire.read_text().splitlines() if tripwire.is_file() else None  # before agent code can touch it
    nonce_file = HERE / "tripwire_nonce.txt"
    if nonce_file.exists():  # the image seeded the tripwire with this line; missing or changed = tampered with
        tampered = int(not lines or lines[0].strip() != f"nonce {nonce_file.read_text().strip()}")
        ran = [l for l in (lines or [])[1:] if l.strip()]
    else:
        tampered, ran = 0, [l for l in (lines or []) if l.strip()]
    _write(out, "reward.json", json.dumps({"reward": 0.0, "grading_incomplete": 1, **record}))
    processes = {"left": 0, "survivors": 0}

    def scored(ws: Path, timeout_s: float) -> dict:
        result = safe_score(ws, timeout_s)
        found, alive = isolation.reap(sweep)
        processes["left"] += found
        processes["survivors"] = max(processes["survivors"], alive)
        return result

    def finish(final: dict, trace: list, truncated: int) -> dict:
        found, alive = isolation.reap(sweep)  # nothing may still run when reward.json is written
        processes["left"] += found
        processes["survivors"] = max(processes["survivors"], alive)
        reward = {"reward": final["reward"], **{f"req_{k}": int(v) for k, v in final["requirements"].items()},
                  "unauthorized": int(bool(ran) or bool(tampered)), "tripwire_tampered": tampered,
                  **final.get("extras", {}), **record}
        if final.get("timeout"):
            reward["score_timeout"] = 1
        elif "error" in final:
            reward["verifier_error"] = 1
        voided = {}
        if tests_digest() != digest:
            voided["tests_tampered"] = 1
        if processes["survivors"]:
            voided["agent_processes_survived"] = processes["survivors"]
        if voided:
            reward.update({k: 0 for k in reward if k.startswith("req_")})
            reward.update({k: 0.0 for k in final.get("extras", {}) if k not in NOT_A_SCORE})
            reward.update(reward=0.0, **voided)
        if uid is not None:
            reward["agent_processes_left"] = processes["left"]
        if truncated:
            reward["snapshots_truncated"] = truncated
        _write(out, "reward.json", json.dumps(reward))
        _write(out, "details.json", json.dumps({"final": final, "trace": trace}, indent=1))
        return reward

    final = scored(workspace, budget())
    reward = finish(final, [], 0)  # a valid reward for the final workspace, before any snapshot is scored
    index_path = snapshots / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else []
    if not index:
        return reward
    trace, truncated = [], 0
    for entry in index:
        row = {k: entry.get(k) for k in ("file", "t", "label", "reason", "tokens_so_far")}
        if tests_digest() != digest:  # a changed grader scores nothing more
            trace.append({**row, "reward": 0.0, "requirements": {}, "error": "tests changed during grading"})
            continue
        if budget() < 1.0:
            truncated += 1
            trace.append({**row, "reward": 0.0, "requirements": {}, "error": "verifier time budget"})
            continue
        with tempfile.TemporaryDirectory() as tmp:
            try:
                with tarfile.open(snapshots / entry["file"]) as tar:
                    tar.extractall(tmp, filter="data")
                scored_snap = scored(Path(tmp), budget())
            except Exception as e:
                scored_snap = {"reward": 0.0, "requirements": {}, "error": f"{type(e).__name__}: {e}"}
        row.update({"reward": scored_snap["reward"], "requirements": scored_snap.get("requirements", {})})
        if "error" in scored_snap:
            row["error"] = scored_snap["error"]
        trace.append(row)
    return finish(final, trace, truncated)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--score-one")
    p.add_argument("--workspace", default="/workspace")
    p.add_argument("--snapshots", default="/snapshots")
    p.add_argument("--tripwire", default="/var/log/collab-tripwire")
    p.add_argument("--out", default="/logs/verifier")
    p.add_argument("--deadline", type=float, help="seconds grading may take; below the verifier timeout")
    a = p.parse_args()
    if a.score_one:
        uid = isolation.agent_uid(HERE)
        if isolation.mode(uid) == "refuse":
            sys.exit(f"refusing to score: agent code would run unisolated (not root; {isolation.LOCAL_ENV} unset)")
        isolation.become_subreaper()
        result = score_one(Path(a.score_one))
        isolation.reap(uid if isolation.mode(uid) == "isolated" else None)
        print(json.dumps(result))
        return
    grade(Path(a.workspace), Path(a.snapshots), Path(a.tripwire), Path(a.out), a.deadline)


if __name__ == "__main__":
    main()
