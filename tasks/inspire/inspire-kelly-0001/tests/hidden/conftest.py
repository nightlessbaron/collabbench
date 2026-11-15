"""Written by the CollabBench kit into tests/hidden/. Pytest runs isolated (python -I), so the agents' workspace is
on sys.path only through this file, and it is appended: workspace files can never replace stdlib or pytest modules."""

import os
import sys

_ws = os.environ.get("COLLAB_WORKSPACE")
if _ws and _ws not in sys.path:
    sys.path.append(_ws)
