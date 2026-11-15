"""Rebuild the hand-built Inspire tasks: `python -m collabbench.tracks.inspire.real [--out DIR] [--seeds DIR]`."""

import argparse
from pathlib import Path

from collabbench import settings
from collabbench.tracks.inspire import real


def main() -> None:
    p = argparse.ArgumentParser(prog="python -m collabbench.tracks.inspire.real")
    p.add_argument("--out", default=str(settings.REPO / "tasks" / "inspire"))
    p.add_argument("--seeds", default=str(real.SEEDS_ROOT), help="the taskmaker frontier tasks directory (read-only)")
    a = p.parse_args()
    for d in real.build_all(Path(a.out), Path(a.seeds)):
        print(d)


if __name__ == "__main__":
    main()
