"""Written by the CollabBench builder into tests/hidden/ (emmet). Pytest runs isolated (python -I), so the workspace's
three emmet packages are on sys.path only through this file, appended: workspace files can never replace stdlib or
pytest modules. `emmet` is a namespace package spread over the three directories.

MAPISettings looks for test data in the workspace's test_files/, a link that the scored copy of the workspace does not
keep; MAPI_TEST_FILES points it at the image's copy next to this file."""

import os
import sys

os.environ.setdefault("MAPI_TEST_FILES", os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_files"))
_ws = os.environ.get("COLLAB_WORKSPACE")
if _ws:
    for _pkg in ("emmet-core", "emmet-builders", "emmet-api"):
        _path = os.path.join(_ws, _pkg)
        if _path not in sys.path:
            sys.path.append(_path)
