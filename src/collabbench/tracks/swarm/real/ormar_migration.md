# Migrating ormar to pydantic 2

The next ormar release supports pydantic 2.x (pydantic-core does validation and serialization in Rust) and drops
pydantic 1.x. The environment already has pydantic 2.5, FastAPI 0.109 and the matching test tools installed. The
`ormar` interface changes with pydantic's. This guide has two parts: what changes for people who use ormar, and the
pydantic 1 to 2 changes that matter when porting the library itself.

## Part 1: changes in the ormar interface

### Model configuration: `ormar_config` replaces `class Meta`

Models no longer declare an inner `Meta` class. Each model has an `ormar_config` attribute that is an instance of
`ormar.OrmarConfig`. The attribute must be named `ormar_config`, and it must be an `OrmarConfig` instance.

```python
import databases
import ormar
import sqlalchemy

database = databases.Database("sqlite:///db.sqlite")
metadata = sqlalchemy.MetaData()

# before
class Album(ormar.Model):
    class Meta:
        database = database
        metadata = metadata
        tablename = "albums"

    id: int = ormar.Integer(primary_key=True)
    name: str = ormar.String(max_length=100)
    favorite: bool = ormar.Boolean(default=False)

# after
class Album(ormar.Model):
    ormar_config = ormar.OrmarConfig(
        database=database,
        metadata=metadata,
        tablename="albums",
    )

    id: int = ormar.Integer(primary_key=True)
    name: str = ormar.String(max_length=100)
    favorite: bool = ormar.Boolean(default=False)
```

### `OrmarConfig` parameters

`OrmarConfig` takes the settings `Meta` used to hold:

```python
metadata: Optional[sqlalchemy.MetaData]
database: Optional[databases.Database]
engine: Optional[sqlalchemy.engine.Engine]
tablename: Optional[str]
order_by: Optional[List[str]]
abstract: bool
exclude_parent_fields: Optional[List[str]]
queryset_class: Type[QuerySet]
extra: Extra
constraints: Optional[List[ColumnCollectionConstraint]]
```

### Shared settings: `OrmarConfig.copy()` replaces a `BaseMeta` class

Create one base config and give each model a copy. `copy()` accepts the same parameters as `OrmarConfig()`, so any of
them can be overridden. By default it keeps the existing attributes, except `tablename`, `order_by` and `constraints`,
which are cleared.

```python
base_ormar_config = ormar.OrmarConfig(
    database=databases.Database("sqlite:///db.sqlite"),
    metadata=sqlalchemy.MetaData(),
)

class Album(ormar.Model):
    ormar_config = base_ormar_config.copy(tablename="albums")

    id: int = ormar.Integer(primary_key=True)
    name: str = ormar.String(max_length=100)


class Track(ormar.Model):
    ormar_config = base_ormar_config.copy(tablename="tracks")

    id: int = ormar.Integer(primary_key=True)
    name: str = ormar.String(max_length=100)
```

### The `choices` field parameter is removed

Fields no longer accept `choices`. Use an `ormar.Enum` field instead. To keep the database column type, for example
an Integer column, write a validator.

```python
from enum import Enum

class Country(str, Enum):
    UK = "UK"
    US = "US"

class Artist(ormar.Model):
    ormar_config = ormar.OrmarConfig(database=database, metadata=metadata, tablename="artists")

    id: int = ormar.Integer(primary_key=True)
    name: str = ormar.String(max_length=100)
    country: Country = ormar.Enum(enum_class=Country)
```

### The `pydantic_only` field parameter is removed

`pydantic_only` fields are gone. A model can declare plain pydantic fields, as in any pydantic model:

```python
class Dish(ormar.Model):
    ormar_config = ormar.OrmarConfig(database=database, metadata=metadata, tablename="dishes")

    id: int = ormar.Integer(primary_key=True)
    name: str = ormar.String(max_length=100)
    cook: str = "sam"  # a normal pydantic field, not stored in the database
```

### `@ormar.property_field` is removed: use `@pydantic.computed_field`

```python
class Employee(ormar.Model):
    ormar_config = ormar.OrmarConfig(database=database, metadata=metadata)

    id: int = ormar.Integer(primary_key=True)
    first_name: str = ormar.String(max_length=100)
    last_name: str = ormar.String(max_length=100)

    @pydantic.computed_field()
    def full_name(self) -> str:
        return f"{self.first_name} {self.last_name}"
```

### Renamed methods (the old names are deprecated)

The old names keep working for now, but they are deprecated.

| before | after | notes |
|---|---|---|
| `model.dict(...)` | `model.model_dump(...)` | same parameters (`include`, `exclude`, ...) |
| `model.json(...)` | `model.model_dump_json(...)` | same parameters |
| `Model.construct(**values)` | `Model.model_construct(**values)` | see pydantic's documentation |

## Part 2: pydantic 1 to 2, for porting the library

The full guide is <https://docs.pydantic.dev/2.5/migration/>. These are the parts that ormar's internals touch.

### `BaseModel` methods and attributes

| pydantic 1 | pydantic 2 |
|---|---|
| `__fields__` | `model_fields` (a dict of `FieldInfo`, not `ModelField`) |
| `__fields_set__` | `model_fields_set` |
| `Config` inner class / `__config__` | `model_config` (a `ConfigDict`) |
| `dict()` / `json()` | `model_dump()` / `model_dump_json()` |
| `copy()` | `model_copy()` |
| `construct()` | `model_construct()` |
| `parse_obj()` / `parse_raw()` | `model_validate()` / `model_validate_json()` |
| `schema()` / `schema_json()` | `model_json_schema()` |
| `update_forward_refs()` | `model_rebuild()` |
| `__get_validators__` on custom types | `__get_pydantic_core_schema__` |
| `validate_assignment` via `__setattr__` hooks | `model_config["validate_assignment"]`, `__pydantic_validator__.validate_assignment` |

### Fields

- `pydantic.fields.ModelField` no longer exists. Field definitions are `pydantic.fields.FieldInfo` objects in
  `Model.model_fields`. `FieldInfo.annotation` holds the type, and `FieldInfo.is_required()` replaces `required`.
- `Optional[X]` no longer means "not required". A field is required unless it has a default, so write
  `Optional[X] = None` for an optional field.
- `Field(regex=...)` is now `Field(pattern=...)`. `const` is gone (use `Literal`). `min_items` and `max_items` are now
  `min_length` and `max_length`. Extra keyword arguments to `Field()` are deprecated: use `json_schema_extra`.
- A model can no longer read private attributes from `__fields__`. Use `PrivateAttr` and `__pydantic_private__`.

### Validators

| pydantic 1 | pydantic 2 |
|---|---|
| `@validator("x")` | `@field_validator("x")` (a classmethod; `values` becomes `info.data`) |
| `@validator(..., pre=True)` | `@field_validator(..., mode="before")` |
| `@root_validator(pre=True)` | `@model_validator(mode="before")` |
| `@root_validator` | `@model_validator(mode="after")` (receives the model instance) |

### Model construction and the metaclass

- The metaclass is `pydantic._internal._model_construction.ModelMetaclass`. It builds a core schema for each model.
  Fields added or changed after class creation need `model_rebuild(force=True)`.
- `__init__` runs `self.__pydantic_validator__.validate_python(data, self_instance=self)`. Custom `__init__`
  overrides must call it, or `super().__init__`.
- Model instances keep their values in `__dict__`. The set fields are in `__pydantic_fields_set__`, and extra values
  in `__pydantic_extra__`.
- `create_model()` takes `__base__`, `__module__` and field definitions as `(type, FieldInfo)` tuples. Configuration
  goes in `__config__`, a `ConfigDict`.
- `Extra.ignore` / `Extra.forbid` are now the strings `"ignore"` / `"forbid"` in `model_config["extra"]`.

### Serialization

- `model_dump()` replaces `dict()`. `include` and `exclude` take sets or dicts as before, but there is no `encoder`
  argument. Use `@field_serializer`, `@model_serializer`, or `model_dump(mode="json")`.
- `json_encoders` in the config still works, but it is deprecated. `@field_serializer` replaces it.
- `@computed_field` replaces properties that should appear in dumps.

### Generics and forward references

- `ForwardRef`s resolve in `model_rebuild()`, which takes `_types_namespace` for the names. `update_forward_refs()` is
  deprecated.
- `typing.get_args` / `typing.get_origin` replace `pydantic.typing` helpers, which are removed.

### FastAPI

FastAPI 0.100 and later builds request and response models with pydantic 2. Models passed as `response_model` must be
pydantic 2 models that can build a JSON schema.
