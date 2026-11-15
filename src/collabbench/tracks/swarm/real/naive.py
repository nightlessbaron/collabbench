"""A line-local regex migrator built from the tables in each task's docs/MIGRATION.md (admission probe).

It rewrites one line at a time: renamed methods, validator decorators, Field keywords, config keys and import lines.
It never looks at another line of the module, so it cannot restructure a class (`class Meta` / `class Config` into a
config object), move a value from `values` to `info.data`, or rewrite a custom type's schema hooks. If such a script
scores well, the migration is too regular for the Swarm track. A task must keep its probe score at 0.4 or below,
measured live with `python -m collabbench.tracks.swarm.real naive <task_dir>` and a gate run of the variant it writes.
"""

import re

RULES: list[tuple[str, str]] = [
    (r"\.dict\(", ".model_dump("),
    (r"\.json\(", ".model_dump_json("),
    (r"\.parse_obj\(", ".model_validate("),
    (r"\.parse_raw\(", ".model_validate_json("),
    (r"\.construct\(", ".model_construct("),
    (r"\.schema\(\)", ".model_json_schema()"),
    (r"\.update_forward_refs\(", ".model_rebuild("),
    (r"\b__fields_set__\b", "model_fields_set"),
    (r"\b__fields__\b", "model_fields"),
    (r"@root_validator\(pre=True\)", '@model_validator(mode="before")'),
    (r"@root_validator\(skip_on_failure=True\)", '@model_validator(mode="after")'),
    (r"@root_validator\b(?!\()", '@model_validator(mode="after")'),
    (r"@validator\((.*)\bpre=True\b", r'@field_validator(\1mode="before"'),
    (r"@validator\(", "@field_validator("),
    (r"\bregex=", "pattern="),
    (r"\bmin_items=", "min_length="),
    (r"\bmax_items=", "max_length="),
    (r"\ballow_population_by_field_name\b", "populate_by_name"),
    (r"\borm_mode\b", "from_attributes"),
    (r"\bschema_extra\b", "json_schema_extra"),
    (r"\bPyObject\b", "ImportString"),
    (r"@ormar\.property_field\(\)", "@pydantic.computed_field()"),
    (r",\s*pydantic_only=True", ""),
]
IMPORT_NAMES = {"validator": "field_validator", "root_validator": "model_validator", "PyObject": "ImportString"}
SOURCE_DIRS = ("ormar/", "emmet-core/emmet/", "emmet-builders/emmet/", "emmet-api/emmet/")


def migrate_line(line: str) -> str:
    m = re.match(r"^(\s*)from pydantic import (.+)$", line)
    if m and "(" not in m.group(2):
        names = [n.strip() for n in m.group(2).split(",")]
        moved = [n for n in names if n == "BaseSettings"]
        kept = [IMPORT_NAMES.get(n, n) for n in names if n != "BaseSettings"]
        out = [f"{m.group(1)}from pydantic import {', '.join(kept)}"] if kept else []
        out += [f"{m.group(1)}from pydantic_settings import BaseSettings"] if moved else []
        return "\n".join(out)
    for pattern, repl in RULES:
        line = re.sub(pattern, repl, line)
    return line


def migrate_files(files: dict[str, str | bytes]) -> dict[str, str]:
    """Migrated text of every source .py file the rules change (files outside the source packages are untouched)."""
    out = {}
    for path, text in files.items():
        if isinstance(text, str) and path.endswith(".py") and path.startswith(SOURCE_DIRS):
            new = "\n".join(migrate_line(line) for line in text.split("\n"))
            if new != text:
                out[path] = new
    return out
