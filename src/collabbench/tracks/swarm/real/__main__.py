"""Builder CLI for the real-migration Swarm tasks.

    python -m collabbench.tracks.swarm.real build [ormar-pydantic2 emmet-pydantic2] [--out tasks/swarm]
    python -m collabbench.tracks.swarm.real naive <task_dir> [--out runs/naive]

`build` reads the pinned upstream commits with git (no upstream code runs here) and writes the task in harvest mode;
`collabbench pin-tests` then pins its hidden tests from the gate's runs on Modal. `naive` writes a copy of a pinned
task whose reference is the line-local regex migrator's output (naive.py): the oracle reward of that copy's gate is the
admission probe score.
"""

import argparse
import shutil
from pathlib import Path

from collabbench import settings
from collabbench.tracks.swarm.real.common import patch_between, solve_script
from collabbench.tracks.swarm.real.naive import migrate_files


def migrations() -> dict:
    from collabbench.tracks.swarm.real import emmet, ormar
    return {ormar.MIGRATION.slug: (ormar.MIGRATION, None), emmet.MIGRATION.slug: (emmet.MIGRATION,
                                                                                emmet.build_spec_kwargs)}


def build(slugs: list[str], out: Path) -> list[Path]:
    known = migrations()
    written = []
    for slug in slugs or list(known):
        migration, prepare = known[slug]
        if prepare:
            prepare()
        written.append(migration.write(out))
    return written


def workspace_files(task_dir: Path) -> dict[str, str | bytes]:
    root = Path(task_dir) / "environment" / "workspace"
    out = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file() and not p.is_symlink()):
        data = path.read_bytes()
        try:
            out[str(path.relative_to(root))] = data.decode("utf-8")
        except UnicodeDecodeError:
            out[str(path.relative_to(root))] = data
    return out


def write_naive(task_dir: Path, out: Path) -> Path:
    task_dir = Path(task_dir)
    files = workspace_files(task_dir)
    migrated = migrate_files(files)
    dest = Path(out) / f"{task_dir.name}-naive"
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(task_dir, dest, symlinks=True)
    patch = patch_between({p: files[p].encode() for p in migrated}, {p: t.encode() for p, t in migrated.items()})
    (dest / "solution" / "solve.sh").write_text("#!/bin/bash\nset -euo pipefail\n" + solve_script(patch))
    return dest


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="python -m collabbench.tracks.swarm.real")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("slugs", nargs="*")
    b.add_argument("--out", default=str(settings.REPO / "tasks" / "swarm"))
    n = sub.add_parser("naive")
    n.add_argument("task")
    n.add_argument("--out", default=str(settings.REPO / "runs" / "naive"))
    a = p.parse_args(argv)
    if a.cmd == "build":
        for d in build(a.slugs, Path(a.out)):
            print(d)
    else:
        print(write_naive(Path(a.task), Path(a.out)))


if __name__ == "__main__":
    main()
