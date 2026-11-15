"""Written by the CollabBench kit into tests/hidden/. Pytest runs isolated (python -I), so the agents' workspace is
on sys.path only through this file, and it is appended: workspace files can never replace stdlib or pytest modules.
A task that names an agent UID (tests/agent_uid) runs agent code only as that UID, never inside this root process, so
its workspace is never put on the path at all."""

import os
import sys

_ws = os.environ.get("COLLAB_WORKSPACE")
_isolating = os.path.exists(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "agent_uid"))
if _ws and _ws not in sys.path and not _isolating:
    sys.path.append(_ws)
