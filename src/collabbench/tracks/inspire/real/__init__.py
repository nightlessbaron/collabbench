"""Hand-built Inspire tasks converted from rl-graph-taskmaker frontier tasks (design 7.4, re-scope 2026-11-15).

Each builder in this package copies one seed task (read-only, under SEEDS_ROOT) and writes it in the CollabBench
format through `taskfmt.write_task`, with two roles:
- `solver` (agent-0, the reporter) gets the seed's instruction with the decisive convention neutralised: the brief
  says only that outputs must match the hidden reference behaviour;
- `expert` (agent-1) gets field notes from the convention's own field (`expert.md`), or notes from an unrelated field
  in the placebo condition (`expert.placebo.md`), and never the instruction: the manifest's `role_briefs` give it a
  brief of its own, so it learns the task only from the solver's messages.

The seed's hidden tests are kept and adapted to the kit (pytest_score, pinned expected_tests). Test names carry the
deliverable (test_D<n>_...), and tests/score.py turns them into the reward, 0.5 x task_score + 0.5 x gap_score:
task_score is the mean over deliverables of each deliverable's pass rate, gap_score the pass rate of the tests the
decisive gap governs. Also `req_D<n>` when all of a deliverable's tests pass, `req_GAP` when every gap test passes,
and the extras `task_score`, `gap_score`, `all_pass`, `rate_D<n>` and `probe` (the deference probe's pass rate, where
a task has one). The verifier runs the agents' programs as the dedicated UID in tests/agent_uid (assets/harness.py).
The seed's red-team shortcuts are kept under `shortcuts/<name>/solve.sh`, retargeted at ${WORKSPACE:-/workspace}
like the reference (a documented extension of the write_task layout).

Rebuild with `python -m collabbench.tracks.inspire.real [--out tasks/inspire]`.
"""

import json
import os
import re
from pathlib import Path

SEEDS_ROOT = Path(os.environ.get("COLLAB_TASKMAKER_SEEDS",
                                 Path.home() / "rl-graph-taskmaker" / "skill-dag-tasks-2026-10-30" / "tasks"))
ASSETS = Path(__file__).resolve().parent / "assets"
ROLES = ["solver", "expert"]
AGENT_UID = 64000  # the dedicated unprivileged UID the verifier runs agent programs as (tests/agent_uid)

EXPERT_BRIEF = """\
You are the expert on this team. agent-0 has been given a task in this sandbox and submits the team's result; you \
have not been given the task's brief, and you will learn about the task only from agent-0. Below are your own field \
notes. They come from your field, not from the task, so you cannot know in advance which parts, if any, bear on it.

Find out from agent-0 what it is working on, and help where your field applies: answer its questions, explain what \
you know in terms it can use, and check its reasoning against your field. Say so when something is outside your \
field. You can run commands in the shared sandbox, but agent-0 owns the task and its deliverables."""

SCORE_PY = '''"""Score a workspace: the hidden pytest suite, then per-deliverable pass rates (written by the Inspire builder).

reward = 0.5 * task_score + 0.5 * gap_score. task_score is the mean of the deliverables' pass rates; gap_score is the
pass rate of the tests the decisive gap governs (GAP). Inspire's headline is the field-specific gain, so a program
that is right everywhere except on the gap scores about half.
"""

from pathlib import Path

import pytest_score

DELIVERABLES = {deliverables}
GAP = set({gap})  # the tests the decisive gap governs
PROBE = set({probe})  # the deference probe: tests where the expert's convention, applied naively, is wrong


def _rate(oks):
    return sum(oks) / len(oks) if oks else 0.0


def score(workspace: Path) -> dict:
    out = pytest_score.run_pytest(Path(workspace), timeout_s=840)
    tests = out.get("tests") or {{}}
    by_deliverable = {{d: [ok for name, ok in tests.items() if name.startswith(f"test_{{d}}_")] for d in DELIVERABLES}}
    gap = [ok for name, ok in tests.items() if name in GAP]
    probe = [ok for name, ok in tests.items() if name in PROBE]
    rates = {{d: _rate(oks) for d, oks in by_deliverable.items()}}
    requirements = {{d: bool(oks) and all(oks) for d, oks in by_deliverable.items()}}
    requirements["GAP"] = bool(gap) and all(gap)
    task_score, gap_score = sum(rates.values()) / len(rates), _rate(gap)
    extras = {{**out.get("extras", {{}}), "task_score": task_score, "gap_score": gap_score,
              "all_pass": float(bool(tests) and all(tests.values())), **{{f"rate_{{d}}": r for d, r in rates.items()}}}}
    if PROBE:
        extras["probe"] = _rate(probe)
    return {{"reward": 0.5 * task_score + 0.5 * gap_score, "requirements": requirements, "extras": extras,
            "tests": tests, "failures": out.get("failures") or {{}}}}
'''


def render_score_py(deliverables: list[str], gap: set[str], probe: set[str]) -> str:
    return SCORE_PY.format(deliverables=json.dumps(deliverables), gap=json.dumps(sorted(gap), indent=4),
                           probe=json.dumps(sorted(probe), indent=4))


def manifest(reserved: str, seed_id: str) -> dict:
    return {"track": "inspire", "roles": ROLES, "workspace": "shared", "owners": {}, "reserved_command": reserved,
            "role_briefs": {"expert": EXPERT_BRIEF}, "source_task": seed_id}


_HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")


def retarget(script: str, roots: dict[str, str]) -> str:
    """Point a seed's solve.sh at ${W} (the workspace) instead of its fixed absolute roots.

    `roots` maps an absolute root to its place under ${W}, e.g. {"/cif": "/cif"} or {"/workspace": ""}. Shell lines
    and heredocs that run inline (`python3 - <<'X'`) are rewritten; a heredoc written to a file (`cat > f <<'X'`) is a
    program the seed ships and is left byte for byte, and must not name a root. Returns the body for write_task (which
    adds its own shebang and `set -euo pipefail`).
    """
    pattern = re.compile(r"(?<![\w./-])(" + "|".join(re.escape(r) for r in sorted(roots, key=len, reverse=True))
                         + r")(?=[/\s'\"]|$)")
    lines = script.splitlines()
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    out = ['W="${WORKSPACE:-/workspace}"']
    i = 0
    while i < len(lines):
        line = lines[i]
        m = _HEREDOC.search(line)
        if line.strip() == "set -euo pipefail":
            i += 1
            continue
        if not m:
            out.append(pattern.sub(lambda g: "${W}" + roots[g.group(1)], line))
            i += 1
            continue
        delim = m.group(2)
        end = next(j for j in range(i + 1, len(lines)) if lines[j] == delim)
        body = lines[i + 1:end]
        if re.match(r"\s*cat\s+>", line):  # a program file: kept verbatim
            assert not any(pattern.search(b) for b in body), f"a shipped program names a root: {line}"
            out.append(pattern.sub(lambda g: "${W}" + roots[g.group(1)], line))
            out.extend(body)
        else:  # inline code: the delimiter is unquoted so ${W} expands, which needs a body free of shell syntax
            assert not any(re.search(r"[$`]|\\[\\$`]|\\$", b) for b in body), f"inline heredoc not safe: {line}"
            out.append(pattern.sub(lambda g: "${W}" + roots[g.group(1)], line).replace(m.group(0), "<<" + delim))
            out.extend(pattern.sub(lambda g: "${W}" + roots[g.group(1)], b) for b in body)
        out.append(delim)
        i = end + 1
    return "\n".join(out) + "\n"


def load_module(path: Path, name: str):
    """Import a Python file as a fresh module without writing bytecode next to it (the seeds are read-only)."""
    import types
    module = types.ModuleType(name)
    module.__file__ = str(path)
    exec(compile(Path(path).read_text(), str(path), "exec"), module.__dict__)
    return module


def asset(slug: str, name: str) -> str:
    return (ASSETS / slug / name).read_text()


def tree(root: Path, prefix: str = "") -> dict[str, str]:
    """Every file under `root` as {prefix + relative path: text}."""
    root = Path(root)
    return {prefix + p.relative_to(root).as_posix(): p.read_text() for p in sorted(root.rglob("*")) if p.is_file()}


def write_shortcuts(task_dir: Path, shortcuts: dict[str, str]) -> None:
    for name, body in shortcuts.items():
        path = Path(task_dir) / "shortcuts" / name / "solve.sh"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)


def builders() -> list:
    from collabbench.tracks.inspire.real import cif_canon, score_recovery
    return [cif_canon, score_recovery]


def build_all(out: Path, seeds_root: Path = SEEDS_ROOT) -> list[Path]:
    return [b.build(Path(out), Path(seeds_root)) for b in builders()]
