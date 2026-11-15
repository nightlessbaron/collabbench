import json

import pytest

from collabbench import settings


def test_gateway_url_appends_v1(tmp_path):
    state = tmp_path / "comet-gateway.json"
    state.write_text(json.dumps({"gateway_url": "http://h:8400", "job_id": "1"}))
    assert settings.gateway_url(state) == "http://h:8400/v1"


def test_gateway_url_tolerates_trailing_slash(tmp_path):
    state = tmp_path / "comet-gateway.json"
    state.write_text(json.dumps({"gateway_url": "http://h:8400/"}))
    assert settings.gateway_url(state) == "http://h:8400/v1"


def test_gateway_key_reads_api_key_field(tmp_path):
    key = tmp_path / "api-key.yaml"
    key.write_text("api-key: abc\n")
    assert settings.gateway_key(key) == "abc"


def test_gateway_key_missing_raises(tmp_path):
    key = tmp_path / "api-key.yaml"
    key.write_text("other: s3cr3t-value\n")
    with pytest.raises(ValueError) as err:
        settings.gateway_key(key)
    assert "s3cr3t-value" not in str(err.value)


def test_model_and_repo():
    assert settings.MODEL == "deepseek-v4-1-flash-1017"
    assert (settings.REPO / "pyproject.toml").is_file()
