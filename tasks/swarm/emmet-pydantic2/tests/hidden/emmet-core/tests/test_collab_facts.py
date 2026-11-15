"""Brief-only decisions F1 and F2 (CollabBench)."""
import warnings


def test_F1_pyobject_alias():
    from pydantic import ImportString

    from emmet.core.settings import PyObject

    assert PyObject is ImportString


def test_F2_dict_without_warning():
    from emmet.core.base import EmmetBaseModel

    class Doc(EmmetBaseModel):
        value: int = 3

    doc = Doc()
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        out = doc.dict()
    assert out == doc.model_dump() and out["value"] == 3
