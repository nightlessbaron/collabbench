"""Builder-side helpers for frontier tasks converted from rl-graph-taskmaker seeds (Inspire and Pool real tasks).

- SEEDS_ROOT: the read-only directory of seed tasks (COLLAB_TASKMAKER_SEEDS overrides it).
- AGENT_UID: the dedicated unprivileged UID a task names in tests/agent_uid; its verifier runs agent programs as it.
- HARNESS: harness.py, shipped to a task as tests/hidden/harness.py: how hidden tests run agent programs and read what
  they leave, on top of tests/isolation.py (isolation.py, which write_task ships).
- retarget, load_module, tree, write_shortcuts: the seed-to-task conversions every builder needs.
"""

import os
import re
from pathlib import Path

SEEDS_ROOT = Path(os.environ.get("COLLAB_TASKMAKER_SEEDS",
                                 Path.home() / "rl-graph-taskmaker" / "skill-dag-tasks-2026-10-30" / "tasks"))
AGENT_UID = 64000  # the dedicated unprivileged UID the verifier runs agent programs as (tests/agent_uid)
HARNESS = Path(__file__).resolve().parent / "harness.py"

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


def tree(root: Path, prefix: str = "") -> dict[str, str]:
    """Every file under `root` as {prefix + relative path: text}."""
    root = Path(root)
    return {prefix + p.relative_to(root).as_posix(): p.read_text() for p in sorted(root.rglob("*")) if p.is_file()}


def write_shortcuts(task_dir: Path, shortcuts: dict[str, str]) -> None:
    """Red-team solutions under shortcuts/<name>/solve.sh, each a solve.sh body (as write_task takes the reference)."""
    for name, body in shortcuts.items():
        path = Path(task_dir) / "shortcuts" / name / "solve.sh"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)
