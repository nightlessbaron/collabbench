"""A line-local migrator for Swarm instances: the strategy one agent can script without reading the modules.

`line_local_migrate(workspace)` rewrites every acme module with the mapping docs/MIGRATION.md documents, one line at a
time and with simple regexes, knowing nothing about the module:

- every import line that mentions `legacy` becomes `from storex import Missing, store` plus three helpers that keep
  legacy semantics exactly as the guide describes them (`get` with a default, `delete` returning a bool, `scan`
  reading every page and honouring offset, limit and start_after);
- on every line with a `storage.<fn>(` (or `legacy.storage.<fn>(`) call: get, scan and delete go to the helpers,
  incr becomes `store.add`, put becomes `store.put` and a `ttl=<expr>` on the same line becomes
  `ttl=timedelta(seconds=<expr>)` (left alone when the expression is already a `timedelta(...)` call).

It also flips every module to "storex" in acme/registry.py and adds every CHANGELOG line, which needs no knowledge of
any module. It is generous on purpose: it is the strongest migrator that still looks at one line at a time.
"""

import re
from pathlib import Path

HELPERS = '''from datetime import timedelta
from storex import Missing, store


def _legacy_get(key, default=None):
    try:
        return store.fetch(key).value
    except Missing:
        return default


def _legacy_delete(key):
    try:
        store.remove(key)
    except Missing:
        return False
    return True


def _legacy_scan(prefix, offset=0, limit=None, start_after=None):
    records, cursor = [], start_after
    while True:
        page = store.scan(prefix, cursor=cursor)
        records += [(r.key, r.value) for r in page.items]
        if page.next_cursor is None:
            break
        cursor = page.next_cursor
    records = records[offset:]
    return records if limit is None else records[:limit]
'''
IMPORT = re.compile(r"^\s*(from\s+legacy(\.storage)?\s+import\b|import\s+legacy\b)")
CALL = re.compile(r"\b(?:legacy\.)?storage\.(get|put|scan|delete|incr)\(")
TARGET = {"get": "_legacy_get(", "put": "store.put(", "scan": "_legacy_scan(", "delete": "_legacy_delete(",
          "incr": "store.add("}


def _expr_end(line: str, start: int) -> int:
    """Index just past the expression starting at `start`: up to a top-level comma or closing bracket."""
    depth = 0
    for i in range(start, len(line)):
        ch = line[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif ch == "," and depth == 0:
            return i
    return len(line)


def _rewrite_ttl(line: str) -> str:
    m = re.search(r"\bttl=", line)
    if not m:
        return line
    end = _expr_end(line, m.end())
    expr = line[m.end():end].strip()
    if not expr or expr == "None" or expr.startswith("timedelta("):
        return line
    return line[:m.end()] + f"timedelta(seconds={expr})" + line[end:]


def migrate_source(text: str) -> str:
    out, helpers_done = [], False
    for line in text.splitlines():
        if IMPORT.match(line):
            if not helpers_done:
                out.append(HELPERS)
                helpers_done = True
            continue
        if CALL.search(line):
            is_put = bool(re.search(r"\bstorage\.put\(", line))
            line = CALL.sub(lambda m: TARGET[m.group(1)], line)
            if is_put:
                line = _rewrite_ttl(line)
        out.append(line)
    return "\n".join(out) + "\n"


def line_local_migrate(workspace: Path) -> None:
    acme = Path(workspace) / "acme"
    names = []
    for path in sorted(acme.glob("*.py")):
        if path.name in ("__init__.py", "registry.py"):
            continue
        names.append(path.stem)
        path.write_text(migrate_source(path.read_text()))
    registry = acme / "registry.py"
    registry.write_text(registry.read_text().replace('"legacy"', '"storex"'))
    changelog = Path(workspace) / "CHANGELOG.md"
    lines = "".join(f"- Migrated acme.{n} to storex.\n" for n in names)
    changelog.write_text(changelog.read_text().replace("## Unreleased\n\n", f"## Unreleased\n\n{lines}", 1))
