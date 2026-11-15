"""Written by the CollabBench builder into tests/hidden/ (emmet). Pytest runs isolated (python -I), so the workspace's
three emmet packages are on sys.path only through this file, appended: workspace files can never replace stdlib or
pytest modules. `emmet` is a namespace package spread over the three directories."""

import os
import sys

_ws = os.environ.get("COLLAB_WORKSPACE")
if _ws:
    for _pkg in ("emmet-core", "emmet-builders", "emmet-api"):
        _path = os.path.join(_ws, _pkg)
        if _path not in sys.path:
            sys.path.append(_path)
