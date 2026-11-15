"""Hand-built Pool tasks converted from rl-graph-taskmaker frontier tasks (Task R3, re-scope 2026-11-15).

Pool's question is whether a team surfaces privately held facts. Each builder here turns one seed task into "two
halves of one interface, one spec each": the seed's hidden specification becomes a list of atomic facts, each held by
exactly one of two agents, `a` and `b`, and every deliverable needs facts from both. The shared instruction states the
goal and the deliverables' command lines and paths, and says the details are split between the two teammates; it,
the workspace and the visible samples state none of the needed facts.

Per task (see the builder modules):
- `environment/private/a.md` and `b.md`: each agent's notes, rendered from the builder's FACTS (needed facts, two or
  three true but unneeded distractors per side, and, in b's notes only, one secret the task must never output);
- `tests/facts.json`: the facts in the synthetic Pool's schema (generator.notes_and_facts: id, role, token, needed,
  secret, match), which collabbench.metrics' disclosure_precision reads unchanged;
- `tests/score.py` (SCORE_PY): reward = task_score, the mean over deliverables of each deliverable's pass rate.
  Requirements: `D<n>` when all of a deliverable's tests pass, and `F<fact id>` for each needed fact when every test of
  its family passes (the hidden tests its violation fails), which feeds fact retention;
- the seed's hidden tests, adapted (tests/hidden/), run agent programs through the shared frontier harness
  (collabbench.taskfmt.frontier: harness.py and isolation.py) as the dedicated UID in tests/agent_uid. Each needed
  fact has tests of its own that read that fact alone (FAMILIES): violating one fact alone turns off its own F
  requirement and, apart from the overlaps a builder documents (ATTRIBUTION_OVERLAP), no other (`attribution`);
- `shortcuts/<name>/solve.sh`: red-team solutions built from the reference by one-fact ablations (ABLATIONS):
  `a-only` and `b-only` (the reference with every fact of the other side violated), `no-facts` (both sides
  violated) and `empty-deliverables`.

The agent sandbox and the verifier run without network: TaskSpec has no network field on this branch, so the builder
writes `[environment].network_mode = "no-network"` into task.toml itself (set_no_network), exactly the line the kit
writes once it has the field.

Rebuild with `python -m collabbench.tracks.pool.real [--out tasks/pool]`.
"""

import json
import os
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from collabbench import settings
from collabbench.taskfmt.frontier.build import (  # noqa: F401  re-exported for the builders
    AGENT_UID, HARNESS, SEEDS_ROOT, load_module, tree, write_shortcuts)
from collabbench.taskfmt.frontier.isolation import LOCAL_ENV

ASSETS = Path(__file__).resolve().parent / "assets"
TASKS = settings.REPO / "tasks" / "pool"
ROLES = ["a", "b"]
FACT_KEYS = ("id", "role", "token", "needed", "secret", "match")  # the synthetic Pool's facts.json schema
NETWORK_LINE = 'network_mode = "no-network"\n'

SCORE_PY = '''"""Score a workspace: the hidden pytest suite, then per-deliverable pass rates (written by the Pool builder).

reward = task_score, the mean over deliverables of each deliverable's pass rate. Requirements: D<n> when every test
of deliverable D<n> passes; F<id> for each needed fact when every test of its family passes (the hidden tests a
violation of that fact fails), which is what fact retention reads.
"""

from pathlib import Path

import pytest_score

DELIVERABLES = {deliverables}
FAMILIES = {families}


def _rate(oks):
    return sum(oks) / len(oks) if oks else 0.0


def score(workspace: Path) -> dict:
    out = pytest_score.run_pytest(Path(workspace), timeout_s=840)
    tests = out.get("tests") or {{}}
    by_deliverable = {{d: [ok for name, ok in tests.items() if name.startswith(f"test_{{d}}_")] for d in DELIVERABLES}}
    rates = {{d: _rate(oks) for d, oks in by_deliverable.items()}}
    requirements = {{d: bool(oks) and all(oks) for d, oks in by_deliverable.items()}}
    for fact, family in FAMILIES.items():
        requirements["F" + fact] = bool(tests) and all(tests.get(name, False) for name in family)
    task_score = sum(rates.values()) / len(rates)
    extras = {{**out.get("extras", {{}}), "task_score": task_score,
              "all_pass": float(bool(tests) and all(tests.values())), **{{f"rate_{{d}}": r for d, r in rates.items()}}}}
    return {{"reward": task_score, "requirements": requirements, "extras": extras, "tests": tests}}
'''


def render_score_py(deliverables: list[str], families: dict[str, list[str]]) -> str:
    body = "".join(f"    {json.dumps(k)}: {json.dumps(sorted(v))},\n" for k, v in sorted(families.items()))
    return SCORE_PY.format(deliverables=json.dumps(deliverables), families="{\n" + body + "}")


def facts_json(facts: list[dict]) -> str:
    return json.dumps([{k: f[k] for k in FACT_KEYS} for f in facts], indent=1) + "\n"


def render_notes(title: str, intro: str, facts: list[dict], role: str) -> str:
    """One agent's private notes: a title, an introduction (no facts in it), and one bullet per fact it holds."""
    bullets = "\n".join(f"- {f['text']}" for f in facts if f["role"] == role)
    return f"# {title}\n\n{intro.strip()}\n\n{bullets}\n"


def manifest(owners: dict[str, list[str]], reserved: str, seed_id: str) -> dict:
    return {"track": "pool", "roles": ROLES, "workspace": "shared", "owners": owners, "reserved_command": reserved,
            "source_task": seed_id}


def requirements(deliverables: list[str], facts: list[dict]) -> list[str]:
    return [*deliverables, *("F" + f["id"] for f in facts if f["needed"])]


def apply(text: str, replacements: list[tuple[str, str]], what: str = "") -> str:
    """`text` with each (old, new) applied in turn; every `old` must occur exactly once when its turn comes."""
    for old, new in replacements:
        count = text.count(old)
        if count != 1:
            raise ValueError(f"{what}: {old[:60]!r} occurs {count} times")
        text = text.replace(old, new)
    return text


def ablate(programs: dict[str, str], ablations: dict[str, list[tuple[str, str, str]]], fact_ids) -> dict[str, str]:
    """The reference programs with every listed fact violated (each fact's (program, old, new) replacements)."""
    out = dict(programs)
    for fid in fact_ids:
        for path, old, new in ablations[fid]:
            out[path] = apply(out[path], [(old, new)], f"ablation {fid}")
    return out


def side_shortcuts(programs: dict[str, str], ablations: dict, facts: list[dict], solution) -> dict[str, str]:
    """The red-team set: a-only (b's facts violated), b-only (a's violated), no-facts, and empty deliverables."""
    needed = {r: [f["id"] for f in facts if f["needed"] and f["role"] == r] for r in ROLES}
    return {"a-only": solution(ablate(programs, ablations, needed["b"])),
            "b-only": solution(ablate(programs, ablations, needed["a"])),
            "no-facts": solution(ablate(programs, ablations, needed["a"] + needed["b"])),
            "empty-deliverables": solution({path: "" for path in programs})}


def set_no_network(task_dir: Path) -> None:
    """No network for the agent sandbox and the verifier: [environment].network_mode, the kit's own line once
    TaskSpec has a `network` field (then this is a no-op)."""
    toml = Path(task_dir) / "task.toml"
    text = toml.read_text()
    if "network_mode" not in text:
        assert text.rstrip().splitlines()[-1].startswith("memory_mb"), "[environment] is no longer last"
        toml.write_text(text + NETWORK_LINE)


def files_sh(files: dict[str, str]) -> str:
    """Shell lines that write `files` ({workspace-relative path: text}) under ${W}; an empty text makes an empty
    file. The delimiter is quoted, so the programs are written byte for byte."""
    lines = []
    for rel, text in files.items():
        lines.append(f'mkdir -p "${{W}}/{Path(rel).parent.as_posix()}"')
        if not text:
            lines.append(f': > "${{W}}/{rel}"')
            continue
        assert "\nCOLLAB_EOF\n" not in "\n" + text and text.endswith("\n"), rel
        lines.append(f"cat > \"${{W}}/{rel}\" <<'COLLAB_EOF'\n{text}COLLAB_EOF")
    return "\n".join(lines) + "\n"


def score_with(task_dir: Path, body: str, python: str, tmp: Path) -> dict:
    """Run a solve.sh body (bash, writing under $WORKSPACE) on a copy of the start workspace in `tmp`, then grade it
    with `python` through the task's own grade.py (local grading: agent code runs as this user)."""
    ws = Path(tmp) / "workspace"
    shutil.copytree(Path(task_dir) / "environment" / "workspace", ws, symlinks=True)
    env = {**os.environ, "WORKSPACE": str(ws), "PATH": f"{Path(python).parent}:{os.environ.get('PATH', '')}"}
    subprocess.run(["bash", "-c", "set -euo pipefail\n" + body], env=env, check=True, capture_output=True)
    run = subprocess.run([python, str(Path(task_dir) / "tests" / "grade.py"), "--score-one", str(ws)],
                         capture_output=True, text=True, timeout=1800, env={**env, LOCAL_ENV: "1"})
    if run.returncode != 0:
        raise RuntimeError(run.stderr[-3000:])
    return json.loads(run.stdout.strip().splitlines()[-1])


def attribution(builder, task_dir: Path, python: str, tmp: Path | None = None, jobs: int = 17) -> dict:
    """Score the reference and each one-fact ablation of it (builder.ABLATIONS) in `task_dir` with `python`. Returns
    the reference's reward and failing tests, and for each ablated fact the F requirements it turns off and the
    reward."""
    import tempfile
    progs = builder.programs()
    variants = {"reference": progs, **{fid: ablate(progs, builder.ABLATIONS, [fid]) for fid in builder.ABLATIONS}}
    with tempfile.TemporaryDirectory(dir=tmp) as work:
        def one(item):
            name, ps = item
            (Path(work) / name).mkdir()
            return name, score_with(task_dir, builder.solution(ps), python, Path(work) / name)

        with ThreadPoolExecutor(jobs) as pool:
            results = dict(pool.map(one, variants.items()))
    ref = results.pop("reference")
    return {"reference": {"reward": ref["reward"], "failed": sorted(n for n, ok in ref["tests"].items() if not ok)},
            "off": {fid: sorted(k for k, v in r["requirements"].items() if k.startswith("F") and not v)
                    for fid, r in results.items()},
            "reward": {fid: r["reward"] for fid, r in results.items()}}


def asset(slug: str, name: str) -> str:
    return (ASSETS / slug / name).read_text()


def builders() -> list:
    from collabbench.tracks.pool.real import aquilon, pressproof
    return [aquilon, pressproof]


def build_all(out: Path, seeds_root: Path = SEEDS_ROOT) -> list[Path]:
    return [b.build(Path(out), Path(seeds_root)) for b in builders()]
