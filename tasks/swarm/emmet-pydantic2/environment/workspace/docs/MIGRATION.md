# Migrating emmet to pydantic 2

emmet (`emmet-core`, `emmet-builders`, `emmet-api`) moves from pydantic 1.10 to pydantic 2.4 and
pydantic-settings 2.0. Both are already installed, together with maggma 0.57, which supports pydantic 2, and
pymatgen 2023.9.10. Every document model, settings class, builder and API resource must work on pydantic 2.

The full upstream guide is <https://docs.pydantic.dev/2.4/migration/>. pydantic also publishes an automatic codemod,
`bump-pydantic`, but it is not installed here and the environment has no network. The sections below cover what emmet
uses.

## Settings: `BaseSettings` moved to `pydantic-settings`

```python
# before
from pydantic import BaseSettings

class EmmetSettings(BaseSettings):
    class Config:
        env_prefix = "emmet_"
        extra = "ignore"

# after
from pydantic_settings import BaseSettings, SettingsConfigDict

class EmmetSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="emmet_", extra="ignore")
```

- `pydantic.PyObject` is removed. Use `pydantic.ImportString`, which imports a dotted path on validation.
- Root validators on settings become `@model_validator(mode="before")` and receive the raw input mapping.

## Model configuration

| pydantic 1 (`class Config`) | pydantic 2 (`model_config = ConfigDict(...)`) |
|---|---|
| `allow_population_by_field_name` | `populate_by_name` |
| `anystr_strip_whitespace` | `str_strip_whitespace` |
| `orm_mode` | `from_attributes` |
| `schema_extra` | `json_schema_extra` |
| `underscore_attrs_are_private` | default behaviour (use `PrivateAttr`) |
| `use_enum_values`, `extra`, `validate_assignment`, `arbitrary_types_allowed` | same names |
| `json_encoders` | still accepted but deprecated; prefer `@field_serializer` |

## Fields

- `Optional[X]` without a default is now **required**. Write `Optional[X] = None` or
  `Field(None, description=...)` where a field may be missing.
- `Field(..., regex=...)` is now `Field(..., pattern=...)`. `min_items` and `max_items` are now `min_length` and
  `max_length`. `const=True` is gone: use `Literal[...]`.
- `Field(..., alias=...)` still works. Extra keyword arguments to `Field()` are deprecated: use
  `json_schema_extra={...}`.
- Field names that start with an underscore are private attributes, not fields. Rename the field, or declare it with
  `PrivateAttr`.
- A model with `__root__` becomes a `pydantic.RootModel[...]`, and the value is in `.root`.
- `pydantic.datetime_parse` is removed. Parse datetimes with a `mode="before"` validator, or let pydantic coerce
  ISO strings.
- Strict `int`/`str` unions: `Union[int, str]` keeps the input type when it already matches. Ordering in `Union` no
  longer decides the coercion.

## Validators

| pydantic 1 | pydantic 2 |
|---|---|
| `@validator("x")` | `@field_validator("x")` + `@classmethod`; the old `values` argument is `info.data` (`info: ValidationInfo`) |
| `@validator("x", pre=True)` | `@field_validator("x", mode="before")` |
| `@validator("x", always=True)` | give the field a default and use `validate_default=True` |
| `@validator("x", each_item=True)` | validate the items inside the field validator, or use an `Annotated` item type |
| `@root_validator(pre=True)` | `@model_validator(mode="before")` + `@classmethod` (receives the raw data) |
| `@root_validator` / `(skip_on_failure=True)` | `@model_validator(mode="after")` (receives the model instance, returns it) |

## Methods

| pydantic 1 | pydantic 2 |
|---|---|
| `Model.parse_obj(d)` | `Model.model_validate(d)` |
| `Model.parse_raw(s)` / `parse_file` | `Model.model_validate_json(s)` |
| `m.dict(...)` | `m.model_dump(...)` |
| `m.json(...)` | `m.model_dump_json(...)` |
| `m.copy(update=...)` | `m.model_copy(update=...)` |
| `Model.schema()` | `Model.model_json_schema()` |
| `Model.__fields__` | `Model.model_fields` (`FieldInfo` objects: `.annotation`, `.default`, `.is_required()`) |
| `Model.update_forward_refs()` | `Model.model_rebuild()` |
| `parse_obj_as(T, x)` | `TypeAdapter(T).validate_python(x)` |

The old names exist only as deprecated shims. Where a shim behaves differently, for example `dict()` on nested
non-pydantic objects or `copy()` validation, code must use the new name.

## Custom types

Classes that validate themselves with `__get_validators__` / `__modify_schema__` must implement
`__get_pydantic_core_schema__(cls, source, handler)` and, for JSON schema, `__get_pydantic_json_schema__`. emmet's
`MPID`, `MPculeID` and the pymatgen-object wrappers are such types. `pydantic_core.core_schema` has the building
blocks: `no_info_plain_validator_function`, `with_info_plain_validator_function`, `str_schema`, `union_schema` and
`plain_serializer_function_ser_schema`.

pymatgen and monty `MSONable` classes, such as `Structure`, `Composition` and `Molecule`, already provide pydantic 2
schemas, so they can be field types directly.

## API (`emmet-api`)

- FastAPI 0.103 builds request and response models with pydantic 2. Query-operator classes that build models with
  `create_model(...)` must pass field definitions as `(type, FieldInfo)` and configuration as `__config__=ConfigDict(...)`.
- `MAPISettings` is a pydantic-settings class (env prefix `MAPI_`).

## Builders (`emmet-builders`)

maggma 0.57 stores and builders accept pydantic 2 models. `doc.model_dump()` replaces `doc.dict()`, and
`jsanitize(doc.model_dump(), allow_bson=True)` remains the way to prepare documents for a store.
