"""Brief-only decisions F1-F3 (CollabBench)."""
import pytest

import ormar
from ormar.exceptions import ModelDefinitionError


def test_F1_model_meta_alias():
    assert ormar.ModelMeta is ormar.OrmarConfig
    assert "ModelMeta" in ormar.__all__


def test_F2_choices_rejected():
    with pytest.raises(ModelDefinitionError, match="ormar.Enum"):
        ormar.String(max_length=10, choices=["a", "b"])
    with pytest.raises(ModelDefinitionError, match="ormar.Enum"):
        ormar.Integer(choices=[1, 2])


def test_F3_pydantic_only_rejected():
    with pytest.raises(ModelDefinitionError, match="pydantic_only"):
        ormar.String(max_length=10, pydantic_only=True, default="x")
    with pytest.raises(ModelDefinitionError, match="pydantic_only"):
        ormar.Integer(pydantic_only=True, default=1)
