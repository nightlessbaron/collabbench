# Port ormar to pydantic 2

ormar, an async ORM built on pydantic and SQLAlchemy, still targets pydantic 1. The environment now has pydantic 2.5
and FastAPI 0.109, so `import ormar` fails. Port the library in `ormar/` to pydantic 2, and adopt the new model
configuration and API described in `docs/MIGRATION.md`: `ormar_config = ormar.OrmarConfig(...)` instead of
`class Meta`, the removal of `choices`, `pydantic_only` and `property_field`, and the `model_dump()` family. The test
suite in `tests/` still uses the old interface and must be updated with the library. Tests run on SQLite and need no
network: `python -m pytest tests`. The existing behaviour of every feature must stay the same apart from the documented
changes.

Three decisions that apply during the migration (they are not in the migration guide):

- F1: keep the old name importable for one release: `ormar.ModelMeta` must be the same object as `ormar.OrmarConfig`, and `"ModelMeta"` must be in `ormar.__all__`.
- F2: passing the removed `choices` argument to any column field (`ormar.String`, `ormar.Integer`, ...) must raise `ormar.exceptions.ModelDefinitionError` whose message contains `ormar.Enum`.
- F3: passing the removed `pydantic_only` argument to any column field must raise `ormar.exceptions.ModelDefinitionError` whose message contains `pydantic_only`.

Requirements:

- R1 (model definition): models defined with `ormar_config` build their pydantic 2 schema, fields, keys, defaults and table definitions (`ormar/models`, `ormar/fields`); covered by tests/test_model_definition and tests/test_types.py
- R2 (inheritance and pydantic models): model inheritance, mixins, abstract models and `get_pydantic()` work under pydantic 2 (`ormar/models/helpers`, `ormar/models/metaclass.py`)
- R3 (relations): foreign keys, many-to-many, through models, reverse relations and forward references (`ormar/relations`, `ormar/fields/foreign_key.py`, `ormar/fields/many_to_many.py`)
- R4 (queries): the QuerySet API: filters, select_related, prefetch, aggregations, pagination (`ormar/queryset`)
- R5 (dump, exclusion and deferred fields): `model_dump()` / `model_dump_json()` with include/exclude, `fields()` / `exclude_fields()`, deferred and forward-ref fields (`ormar/models/excludable.py`, `ormar/models/newbasemodel.py`)
- R6 (FastAPI): ormar models as FastAPI 0.109 request and response models, including generated pydantic models
- R7 (model methods and ordering): save, update, upsert, load, load_all, save_related, and default and relation ordering (`ormar/models/model.py`)
- R8 (signals, encryption, constraints, utilities): signals, encrypted fields, unique/index/check constraints and helper utilities (`ormar/signals`, `ormar/fields/sqlalchemy_encrypted.py`)
- F1, F2, F3: as stated above.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
