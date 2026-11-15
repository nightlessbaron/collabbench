"""ormar to pydantic 2: ormar-orm/ormar PR #1238 (squash-merged as 500625f, parent 3a206dd, March 2024).

ormar is an async ORM built on pydantic and SQLAlchemy. The PR ports its internals to pydantic 2 and changes its own
interface: `ormar_config = OrmarConfig(...)` replaces `class Meta`, `choices` / `pydantic_only` / `property_field` are
removed. It changes 66 files under ormar/, and the upstream suite (about 450 tests) runs on SQLite.
"""

from pathlib import Path

from collabbench.tracks.swarm.real.common import Area, Migration, dist_stub

HERE = Path(__file__).resolve().parent
IMAGE = "public.ecr.aws/docker/library/python:3.11-slim"  # pydantic 2.5.3 breaks on CPython >= 3.12.4 (ForwardRef)
# Versions from the post-migration poetry.lock (runtime, the `all` extras the suite needs, and the dev test tools).
PIP = ["pydantic==2.5.3", "pydantic-core==2.14.6", "annotated-types==0.6.0", "typing-extensions==4.10.0",
       "databases==0.7.0", "SQLAlchemy==1.4.52", "greenlet==3.0.3", "aiosqlite==0.19.0", "asyncpg==0.28.0",
       "PyMySQL==1.1.0", "cryptography==41.0.7", "orjson==3.9.15", "fastapi==0.109.2", "starlette==0.36.3",
       "httpx==0.24.1", "httpcore==0.17.3", "anyio==4.3.0", "sniffio==1.3.1", "h11==0.14.0", "idna==3.6",
       "certifi==2024.2.2", "asgi-lifespan==2.1.0", "pydantic-extra-types==2.6.0", "nest-asyncio==1.6.0",
       "pytest==7.4.4", "pytest-asyncio==0.21.1", "pluggy==1.4.0", "iniconfig==2.0.0", "packaging==24.0"]
STUB = "RUN " + dist_stub("ormar", "0.12.2")  # ormar/__init__.py reads importlib.metadata.version("ormar")

FACT_TESTS = '''"""Brief-only decisions F1-F3 (CollabBench)."""
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
'''

FACT_EDITS = {
    "ormar/__init__.py": [
        ('    "OrmarConfig",\n]', '    "OrmarConfig",\n    "ModelMeta",\n]\n\n'
                                '# Kept so that downstream type hints that import the old name keep working.\n'
                                'ModelMeta = OrmarConfig'),
    ],
    "ormar/fields/model_fields.py": [
        ("    def __new__(cls, *args: Any, **kwargs: Any) -> BaseField:  # type: ignore\n        cls.validate(**kwargs)\n",
         "    def __new__(cls, *args: Any, **kwargs: Any) -> BaseField:  # type: ignore\n"
         "        if \"choices\" in kwargs:\n"
         "            raise ModelDefinitionError(\n"
         "                \"The choices parameter was removed: use an ormar.Enum field instead.\"\n"
         "            )\n"
         "        if \"pydantic_only\" in kwargs:\n"
         "            raise ModelDefinitionError(\n"
         "                \"The pydantic_only parameter was removed: declare a plain pydantic field instead.\"\n"
         "            )\n"
         "        cls.validate(**kwargs)\n"),
    ],
}

AREAS = [
    Area("R1", "model definition", ["tests.test_model_definition.", "tests.test_types::"],
         "models defined with `ormar_config` build their pydantic 2 schema, fields, keys, defaults and table "
         "definitions (`ormar/models`, `ormar/fields`); covered by tests/test_model_definition and tests/test_types.py"),
    Area("R2", "inheritance and pydantic models", ["tests.test_inheritance_and_pydantic_generation."],
         "model inheritance, mixins, abstract models and `get_pydantic()` work under pydantic 2 (`ormar/models/helpers`, "
         "`ormar/models/metaclass.py`)"),
    Area("R3", "relations", ["tests.test_relations."],
         "foreign keys, many-to-many, through models, reverse relations and forward references "
         "(`ormar/relations`, `ormar/fields/foreign_key.py`, `ormar/fields/many_to_many.py`)"),
    Area("R4", "queries", ["tests.test_queries."],
         "the QuerySet API: filters, select_related, prefetch, aggregations, pagination (`ormar/queryset`)"),
    Area("R5", "dump, exclusion and deferred fields", ["tests.test_exclude_include_dict.", "tests.test_deferred."],
         "`model_dump()` / `model_dump_json()` with include/exclude, `fields()` / `exclude_fields()`, deferred and "
         "forward-ref fields (`ormar/models/excludable.py`, `ormar/models/newbasemodel.py`)"),
    Area("R6", "FastAPI", ["tests.test_fastapi."],
         "ormar models as FastAPI 0.109 request and response models, including generated pydantic models"),
    Area("R7", "model methods and ordering", ["tests.test_model_methods.", "tests.test_ordering."],
         "save, update, upsert, load, load_all, save_related, and default and relation ordering (`ormar/models/model.py`)"),
    Area("R8", "signals, encryption, constraints, utilities",
         ["tests.test_signals.", "tests.test_encryption.", "tests.test_meta_constraints.", "tests.test_utils."],
         "signals, encrypted fields, unique/index/check constraints and helper utilities (`ormar/signals`, "
         "`ormar/fields/sqlalchemy_encrypted.py`)"),
]

BRIEF = """# Port ormar to pydantic 2

ormar, an async ORM built on pydantic and SQLAlchemy, still targets pydantic 1. The environment now has pydantic 2.5
and FastAPI 0.109, so `import ormar` fails. Port the library in `ormar/` to pydantic 2, and adopt the new model
configuration and API described in `docs/MIGRATION.md`: `ormar_config = ormar.OrmarConfig(...)` instead of
`class Meta`, the removal of `choices`, `pydantic_only` and `property_field`, and the `model_dump()` family. The test
suite in `tests/` still uses the old interface and must be updated with the library. Tests run on SQLite and need no
network: `python -m pytest tests`. The existing behaviour of every feature must stay the same apart from the documented
changes."""

MIGRATION = Migration(
    slug="ormar-pydantic2",
    url="https://github.com/ormar-orm/ormar.git",
    parent="3a206dd8dc0fdb74bf2aacad23323a3e622ea328",
    after="500625f0ec5af8671939e776bc53abbc03d8ad41",
    prs=["https://github.com/ormar-orm/ormar/pull/1238"],
    source_globs=["ormar/*"],
    hidden_tests={"tests": "tests"},
    areas=AREAS,
    facts={
        "F1": "keep the old name importable for one release: `ormar.ModelMeta` must be the same object as "
              "`ormar.OrmarConfig`, and `\"ModelMeta\"` must be in `ormar.__all__`.",
        "F2": "passing the removed `choices` argument to any column field (`ormar.String`, `ormar.Integer`, ...) must "
              "raise `ormar.exceptions.ModelDefinitionError` whose message contains `ormar.Enum`.",
        "F3": "passing the removed `pydantic_only` argument to any column field must raise "
              "`ormar.exceptions.ModelDefinitionError` whose message contains `pydantic_only`.",
    },
    fact_tests={"hidden/tests/test_collab_facts.py": FACT_TESTS},
    fact_edits=FACT_EDITS,
    migration_md=(HERE / "ormar_migration.md").read_text(),
    brief_intro=BRIEF,
    post_versions=["0.20.0", "0.20.1"],
    drop=[".github/*"],
    targets=None,
    test_timeout_s=1200,
    # Six snapshots per label give the trace speedup, time_to_score and overrun need; the kit's deadline-bounded
    # grading keeps the verifier within its timeout.
    spec_kwargs=dict(base_image=IMAGE, pip_packages=PIP, env_dockerfile=STUB, tests_dockerfile=STUB, cpus=2,
                     memory_mb=4096, verifier_timeout_s=5400, max_snapshots_per_label=6, score_workers=2,
                     score_timeout_s=1500),
    naive_probe_reward=0.0,  # runs/gates/ormar-pydantic2-naive--gate-oracle--20261115-051805: 0 of 450 pinned tests
)
