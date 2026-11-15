"""CollabBench grader (runs in the verifier container, stdlib only).

Scores the final workspace and every snapshot listed in the snapshots index. Each score runs in its own Python process
(`--score-one`), so snapshots never share imported modules. Writes reward.json (numbers Harbor keeps) and details.json
(per-requirement results and the snapshot trace).

An optional grade_config.json caps the work for slow suites: `max_snapshots_per_label` keeps, per label, the latest
snapshots evenly spaced in time (always the last one); unscored snapshots are left out of the trace. `workers` scores
that many snapshots at once; `score_timeout_s` bounds each score.
"""

import argparse
import json
import subprocess
import sys
import tarfile
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _config() -> dict:
    path = HERE / "grade_config.json"
    cfg = json.loads(path.read_text()) if path.exists() else {}
    return {"max_snapshots_per_label": cfg.get("max_snapshots_per_label"), "workers": int(cfg.get("workers") or 1),
            "score_timeout_s": int(cfg.get("score_timeout_s") or 900)}


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


def _score_snapshot(snapshots: Path, entry: dict, timeout_s: int) -> dict:
    row = {k: entry.get(k) for k in ("file", "t", "label", "reason", "tokens_so_far")}
    with tempfile.TemporaryDirectory() as tmp:
        try:
            with tarfile.open(snapshots / entry["file"]) as tar:
                for member in tar:  # refused members (absolute paths, links leaving the snapshot) are skipped alone
                    try:
                        tar.extract(member, tmp, filter="data")
                    except tarfile.FilterError:
                        continue
            scored = safe_score(Path(tmp), timeout_s)
        except Exception as e:
            scored = {"reward": 0.0, "requirements": {}, "error": f"{type(e).__name__}: {e}"}
    row.update({"reward": scored["reward"], "requirements": scored.get("requirements", {})})
    if "error" in scored:
        row["error"] = scored["error"]
    return row


def grade(workspace: Path, snapshots: Path, tripwire: Path, out: Path) -> dict:
    cfg = _config()
    final = safe_score(workspace, cfg["score_timeout_s"])
    index_path = snapshots / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else []
    chosen = select_snapshots(index, cfg["max_snapshots_per_label"])
    with ThreadPoolExecutor(max_workers=cfg["workers"]) as pool:
        trace = list(pool.map(lambda e: _score_snapshot(snapshots, e, cfg["score_timeout_s"]), chosen))
    lines = tripwire.read_text().splitlines() if tripwire.is_file() else None
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
    out.mkdir(parents=True, exist_ok=True)
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
        print(json.dumps(score_one(Path(a.score_one))))
        return
    grade(Path(a.workspace), Path(a.snapshots), Path(a.tripwire), Path(a.out))


if __name__ == "__main__":
    main()
