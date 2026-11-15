"""Grid files: which instances run under which conditions, how many times, on which pool."""

from dataclasses import dataclass, field
from pathlib import Path

import yaml

from collabbench.runner.conditions import condition_kwargs


@dataclass
class Cell:
    track: str
    task_dir: Path
    condition: str
    kwargs: dict[str, str]
    runs: int


@dataclass
class Grid:
    pool: str
    model: str
    effort: str
    concurrency: int
    tracks: dict
    root: Path
    name: str = "grid"
    cells_cache: list = field(default_factory=list)

    def cells(self) -> list[Cell]:
        out = []
        for track, spec in self.tracks.items():
            dirs = sorted({d for pattern in spec["instances"] for d in self.root.glob(pattern) if d.is_dir()})
            for d in dirs:
                for cond, runs in spec["conditions"].items():
                    kw = condition_kwargs(track, cond, int(spec["budget"]))
                    if self.effort:
                        kw["effort"] = self.effort
                    out.append(Cell(track, d, cond, kw, int(runs)))
        return out


def load_grid(path: Path) -> Grid:
    path = Path(path)
    raw = yaml.safe_load(path.read_text())
    return Grid(pool=raw.get("pool", "personal"), model=raw["model"], effort=raw.get("effort", "high"),
                concurrency=int(raw.get("concurrency", 16)), tracks=raw["tracks"],
                root=(path.parent / raw["root"]).resolve() if "root" in raw else path.parent.resolve(),
                name=path.stem)
