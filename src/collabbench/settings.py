"""Where things are: the repository, the evaluated model, and the user's Comet gateway.

The gateway's URL moves when Comet's service job is preempted, so it is read from Comet's state file on every call.
The key is read from Comet's key file; it is returned to the caller and never logged or written anywhere.
"""

import json
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
MODEL = "deepseek-v4-1-flash-1017"
COMET = Path.home() / "comet"
GATEWAY_STATE = COMET / "state" / "comet-gateway.json"
GATEWAY_KEY_FILE = COMET / "api-key.yaml"


def gateway_url(state_path: Path = GATEWAY_STATE) -> str:
    """The OpenAI-compatible base URL of the gateway: Comet's `gateway_url` plus `/v1`."""
    url = json.loads(Path(state_path).read_text())["gateway_url"]
    return url.rstrip("/") + "/v1"


def gateway_key(key_path: Path = GATEWAY_KEY_FILE) -> str:
    """The gateway's Bearer key (the `api-key` field). The error never quotes the file."""
    data = yaml.safe_load(Path(key_path).read_text())
    value = data.get("api-key", data.get("api_key")) if isinstance(data, dict) else None
    if not isinstance(value, str) or not value:
        raise ValueError(f"no api-key field in {Path(key_path).name}")
    return value
