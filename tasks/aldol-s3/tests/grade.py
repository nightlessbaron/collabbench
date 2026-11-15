"""CollabBench grader (runs in the verifier container, stdlib only).

Scores the final workspace and every snapshot listed in the snapshots index. Each score runs in its own Python process
(`--score-one`), so snapshots never share imported modules. Writes reward.json (numbers Harbor keeps) and details.json
(per-requirement results and the snapshot trace).

Agent code that runs during grading must not change the grade, nor cost the trial:
- a task that names an agent UID (tests/agent_uid) is graded only isolated: as root, after isolation.lockdown and a
  passing isolation.probe, with agent code running as that UID. Without root it is graded only when local grading is
  asked for explicitly (isolation.LOCAL_ENV, as localcheck sets it); otherwise grading refuses (`verifier_error`) and
  no agent code runs. reward.json records `isolated` (1/0) for every such task. Isolated, the helpers' spare UID must
  be free (isolation.check_spare), or grading refuses;
- every such task runs isolation.nofollow_preflight first (as the agent UID when isolated) and records `nofollow_ok`
  (1/0): whether reading through a planted directory symlink is refused on this platform. A 0 is a platform fact for
  the gate to report, not a reason to void the trial (the UID drop still bounds every read); a preflight that cannot
  read a plain file at all is a verifier error;
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

An optional grade_config.json caps the work for slow suites: `max_snapshots_per_label` keeps, per label, the latest
snapshots evenly spaced in time (always the last one); unscored snapshots are left out of the trace. `workers` scores
that many snapshots at once; `score_timeout_s` bounds each score (and the deadline bounds them all). A task with an
agent UID scores one snapshot at a time, since its sweep kills every process of the UID; with several workers the
sweep of descendants runs once the snapshots are scored (each score also reaps its own descendants).
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
from concurrent.futures import ThreadPoolExecutor  # noqa: E402
from pathlib import Path  # noqa: E402

import isolation  # noqa: E402  tests/isolation.py, next to this file

HERE = Path(__file__).resolve().parent
SCORE_TIMEOUT_S = 900
NOT_A_SCORE = ("tests_total",)  # extras kept when a grade is voided
BUDGET = "verifier time budget"  # a snapshot left unscored by the deadline


def tests_digest() -> str:
    """Every file the grader reads (score modules, hidden tests, expected_tests.json, references), bytecode aside."""
    h = hashlib.sha256()
    for p in sorted(HERE.rglob("*")):
        if "__pycache__" in p.parts or p.suffix == ".pyc" or p.is_dir():
            continue
        body = os.readlink(p).encode() if p.is_symlink() else p.read_bytes()
        h.update(str(p.relative_to(HERE)).encode() + b"\0" + hashlib.sha256(body).digest())
    return h.hexdigest()


def _config() -> dict:
    path = HERE / "grade_config.json"
    cfg = json.loads(path.read_text()) if path.exists() else {}
    return {"max_snapshots_per_label": cfg.get("max_snapshots_per_label"), "workers": int(cfg.get("workers") or 1),
            "score_timeout_s": int(cfg.get("score_timeout_s") or SCORE_TIMEOUT_S)}


def select_snapshots(index: list[dict], per_label: int | None) -> list[dict]:
    """At most `per_label` entries per label, evenly spaced over that label's snapshots and always including its last."""
    if per_label is None:
        return index
    keep = []
    for label in dict.fromkeys(e.get("label") for e in index):
        rows = sorted((e for e in index if e.get("label") == label), key=lambda e: e.get("t") or 0)
        n = min(per_label, len(rows))
        picks = {len(rows) - 1} if n == 1 else {round(i * (len(rows) - 1) / (n - 1)) for i in range(n)}
        keep += [rows[i] for i in sorted(picks)]
    return [e for e in index if any(e is k for k in keep)]


def score_one(workspace: Path) -> dict:
    sys.path.insert(0, str(HERE))
    import score  # the track's tests/score.py

    out = score.score(Path(workspace))
    return {"reward": float(out.get("reward", 0.0)), "requirements": {k: bool(v) for k, v in
                                                                      out.get("requirements", {}).items()},
            "extras": {k: float(v) for k, v in out.get("extras", {}).items()}, "tests": out.get("tests", {}),
            **{k: out[k] for k in ("collected", "failures") if k in out}}


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


def _extract(snapshot: Path, dest: str) -> None:
    with tarfile.open(snapshot) as tar:
        for member in tar:  # refused members (absolute paths, links leaving the snapshot) are skipped alone
            try:
                tar.extract(member, dest, filter="data")
            except tarfile.FilterError:
                continue


def grade(workspace: Path, snapshots: Path, tripwire: Path, out: Path, deadline_s: float | None = None) -> dict:
    cfg = _config()
    start = time.monotonic()
    deadline = start + deadline_s if deadline_s else None
    reserve = min(30.0, 0.1 * deadline_s) if deadline_s else 0.0

    def budget() -> float:
        limit = cfg["score_timeout_s"]
        return limit if deadline is None else min(limit, deadline - time.monotonic() - reserve)

    uid = isolation.agent_uid(HERE)
    mode = isolation.mode(uid)
    record = {} if uid is None else {"isolated": int(mode == "isolated")}
    isolation.become_subreaper()
    out.mkdir(parents=True, exist_ok=True)

    def refuse(why: dict) -> dict:  # a verifier error; no agent code has run
        _write(out, "reward.json", json.dumps({"reward": 0.0, "verifier_error": 1, **record}))
        _write(out, "details.json", json.dumps(why))
        return {"reward": 0.0, "verifier_error": 1, **record}

    if mode == "refuse":
        return refuse({"error": "the task runs agent code as its agent UID, and the verifier is not root"})
    if mode == "isolated":  # before any agent code runs
        try:
            isolation.check_spare(uid)
        except ValueError as e:
            return refuse({"error": f"the helpers' spare UID is not free: {e}"})
        isolation.lockdown(HERE, [out, workspace, snapshots, tripwire])
        leaks = isolation.probe(uid, HERE, [out, workspace, snapshots])
        if leaks:
            return refuse({"error": "the agent UID is not shut out", "probe": leaks})
    preflight = {}
    if uid is not None:  # read_under's no-follow layer, on the platform that grades (before any agent code)
        try:
            preflight = isolation.nofollow_preflight(tempfile.gettempdir(), uid=uid if mode == "isolated" else None)
        except Exception as e:  # noqa: BLE001 - e.g. no writable temp directory: fail closed, as a verifier error
            preflight = {"read_ok": 0, "nofollow_ok": 0, "error": f"{type(e).__name__}: {e}"}
        record["nofollow_ok"] = int(preflight.get("nofollow_ok", 0))
        if not preflight.get("read_ok"):
            return refuse({"error": "the preflight could not read a plain file", "preflight": preflight})
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

    workers = 1 if uid is not None else max(1, cfg["workers"])

    def scored(ws: Path, timeout_s: float) -> dict:
        result = safe_score(ws, timeout_s)
        if workers == 1:  # with several in flight, a sweep here would kill the others (see the module docstring)
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
        _write(out, "details.json", json.dumps({"final": final, "trace": trace, **({"preflight": preflight}
                                                                                     if preflight else {})}, indent=1))
        return reward

    final = scored(workspace, budget())
    reward = finish(final, [], 0)  # a valid reward for the final workspace, before any snapshot is scored
    index_path = snapshots / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else []
    if not index:
        return reward

    def snapshot_row(entry: dict) -> dict:  # budget and digest are checked when the score starts, not when queued
        row = {k: entry.get(k) for k in ("file", "t", "label", "reason", "tokens_so_far")}
        if tests_digest() != digest:  # a changed grader scores nothing more
            return {**row, "reward": 0.0, "requirements": {}, "error": "tests changed during grading"}
        if budget() < 1.0:
            return {**row, "reward": 0.0, "requirements": {}, "error": BUDGET}
        with tempfile.TemporaryDirectory() as tmp:
            try:
                _extract(snapshots / entry["file"], tmp)
                scored_snap = scored(Path(tmp), budget())
            except Exception as e:
                scored_snap = {"reward": 0.0, "requirements": {}, "error": f"{type(e).__name__}: {e}"}
        row.update({"reward": scored_snap["reward"], "requirements": scored_snap.get("requirements", {})})
        if "error" in scored_snap:
            row["error"] = scored_snap["error"]
        return row

    with ThreadPoolExecutor(max_workers=workers) as pool:
        trace = list(pool.map(snapshot_row, select_snapshots(index, cfg["max_snapshots_per_label"])))
    return finish(final, trace, sum(row.get("error") == BUDGET for row in trace))


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
