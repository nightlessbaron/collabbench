from pathlib import Path

import grade_graph


def score(workspace: Path) -> dict:
    return grade_graph.score(workspace, Path(__file__).resolve().parent)
