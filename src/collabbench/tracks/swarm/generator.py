"""Swarm track (design 7.2): migrate N modules from `legacy.storage` to `storex`.

Answer-first: each module is an instance of one archetype (session cache, rate limiter, stock, flags, audit log, purge,
metrics, leaderboard, profiles), wrapped in seeded business logic (id normalization, validation, formatting, small
domain rules) and written in one of many legacy call-site styles: how the module reaches the client (plain, aliased or
dotted imports, imported functions, a module-level client, a repository class, private wrappers), how calls are
written (keywords, reordered keywords, split over lines, a positional ttl), how keys are built (concatenation, an
f-string, a namespace helper), how the ttl is given (seconds, minutes, hours, a timedelta, computed) and how pages are
read (all at once, an offset loop, a start_after cursor, a rows helper). A correct migration of a call site needs code
that is not on its line, so one script written from docs/MIGRATION.md alone does poorly, and the codebase (60 to 90
modules of 80 to 200 lines) is too big for one agent to read within its budget.

The generator renders each module twice from the same parameters: the legacy module (the starting workspace) and the
migrated module (the reference). The hidden tests drive the module's public functions; their expected values are
recorded by running the legacy module in-process against legacy.storage, so they hold for both semantics except where
the brief's facts F1-F3 change behaviour:

- F1: audit records stop expiring (no ttl).
- F2: counters move from the `count/` namespace to `counter/`.
- F3: no ttl above one hour.

The facts are in the brief only, never in docs/MIGRATION.md, so a lead must pass them on to whoever migrates a module.
Each module also flips its entry in acme/registry.py and adds a CHANGELOG line; those shared edits conflict on merge.
The hidden tests shadow `legacy` with a package that raises on import, so an unmigrated module fails all its tests.
"""

import builtins
import random
import re
import sys
import types
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from collabbench.taskfmt.spec import TaskSpec, write_task

ENTITIES = ["billing", "orders", "carts", "invoices", "tickets", "users", "payments", "shipments", "returns", "reviews",
            "coupons", "catalog", "search", "alerts", "devices", "sensors", "reports", "exports", "webhooks", "emails",
            "tokens", "teams", "projects", "tasks", "comments", "files", "media", "playlists", "bookings", "rooms",
            "menus", "recipes", "fleet", "routes", "drivers", "vendors", "partners", "loyalty", "surveys", "quotas",
            "refunds", "wallets", "badges", "courses", "lessons", "tenants", "leases", "parcels", "pickups", "lockers",
            "warranties", "repairs", "claims", "policies", "quotes", "leads", "campaigns", "banners", "stores",
            "kiosks"]
ARCHETYPES = ["sessions", "ratelimit", "stock", "flags", "audit", "purge", "metrics", "leaderboard", "profiles"]
RESERVED = "scripts/release.sh"
ALL_FACTS = {"F1": True, "F2": True, "F3": True}
TTLS = [600, 900, 1800, 2700, 3600, 7200, 14400, 43200, 86400]
INDENT = "    "
PREFIXES = {"sessions": "session/{e}/", "ratelimit": "count/rate/{e}/", "stock": "stock/{e}/", "flags": "flag/{e}/",
            "audit": "audit/{e}/", "purge": "tmp/{e}/", "metrics": "count/{e}/", "leaderboard": "score/{e}/",
            "profiles": "profile/{e}/"}
COUNTERS = ("ratelimit", "metrics")  # F2
# how a module reaches the legacy client; weights tuned so no single style dominates
ACCESS = {"canonical": 2, "wrappers": 1, "dotted": 1, "alias": 2, "modalias": 2, "fromimport": 2, "injected": 2,
          "repo": 2}
SHAPE_CLASS = {"canonical": "name", "alias": "name", "modalias": "name", "injected": "name", "dotted": "dotted",
               "fromimport": "fromimport", "repo": "repo", "wrappers": "wrappers"}
FORMATS = {"get": ["plain", "kw"], "put": ["plain", "kw", "kwrev", "split", "positional"],
           "incr": ["plain", "kw", "split"], "delete": ["plain", "kw"]}
ARCH_OPS = {"sessions": ("get", "put", "delete"), "ratelimit": ("incr", "delete", "get"),
            "stock": ("get", "put", "incr"), "flags": ("get", "put", "delete"), "audit": ("put",),
            "purge": ("put", "delete", "get"), "metrics": ("incr", "get", "delete"),
            "leaderboard": ("get", "put"), "profiles": ("get", "put", "delete")}
TTL_CHANCE = {"sessions": 1.0, "profiles": 1.0, "audit": 1.0, "purge": 0.7, "leaderboard": 0.5, "flags": 0.4}
CLEANERS = {"sessions": ["lower", "code", "numeric"], "ratelimit": ["lower", "email", "numeric"],
            "stock": ["lower", "slug", "code"], "flags": ["lower", "slug", "dotted"],
            "audit": ["lower", "numeric", "code"], "purge": ["lower", "slug"], "metrics": ["dotted", "lower"],
            "leaderboard": ["lower", "email", "slug"], "profiles": ["lower", "numeric", "email"]}
NOUNS = {"sessions": "session", "ratelimit": "user", "stock": "item", "flags": "flag", "audit": "event",
         "purge": "entry", "metrics": "metric", "leaderboard": "player", "profiles": "user"}
TEAMS = ["platform", "growth", "payments", "fulfilment", "identity", "insights", "support", "catalog", "logistics",
         "billing-ops"]


@dataclass
class Module:
    name: str
    entity: str
    arch: str
    p: dict = field(default_factory=dict)  # archetype constants and optional functions
    v: dict = field(default_factory=dict)  # legacy call-site style
    logic: dict = field(default_factory=dict)  # business logic: id cleaner, helpers, docstring


def render(template: str, **kw) -> str:
    for k, v in kw.items():
        template = template.replace(f"@@{k}@@", str(v))
    assert "@@" not in template, template[template.index("@@") - 40:template.index("@@") + 40]
    return template


def _block(lines: list[str], ind: str) -> str:
    return "\n".join(ind + line if line else "" for line in lines)


# --- workspace library files ------------------------------------------------------------------------------------------
LEGACY_STORAGE = '''"""Legacy key-value storage client. Deprecated: it is being removed in favour of storex (docs/MIGRATION.md)."""

from datetime import timedelta

_DATA = {}  # key -> (value, ttl in seconds or None)


def get(key, default=None):
    """The value stored under key, or default."""
    return _DATA[key][0] if key in _DATA else default


def put(key, value, ttl=None):
    """Store a value. ttl is a number of seconds or a datetime.timedelta (None: never expires)."""
    if isinstance(ttl, timedelta):
        ttl = ttl.total_seconds()
    _DATA[key] = (value, None if ttl is None else int(ttl))


def scan(prefix, offset=0, limit=None, start_after=None):
    """(key, value) pairs under prefix, sorted by key: keys after start_after, skipping offset, at most limit."""
    rows = [(k, v[0]) for k, v in sorted(_DATA.items())
            if k.startswith(prefix) and (start_after is None or k > start_after)]
    rows = rows[offset:]
    return rows if limit is None else rows[:limit]


def delete(key):
    """Delete a key. True if it existed."""
    return _DATA.pop(key, None) is not None


def incr(key, amount=1):
    """Add amount to an integer (missing counts as 0) and return the new value."""
    value, ttl = _DATA.get(key, (0, None))
    _DATA[key] = (value + amount, ttl)
    return value + amount
'''

STOREX = '''"""storex: the new key-value store client. See docs/MIGRATION.md."""

from dataclasses import dataclass
from datetime import timedelta


class Missing(KeyError):
    """The key does not exist."""


@dataclass(frozen=True)
class Record:
    key: str
    value: object
    ttl: timedelta | None


@dataclass(frozen=True)
class Page:
    items: list
    next_cursor: str | None  # None on the last page


class Store:
    PAGE_LIMIT = 50

    def __init__(self):
        self._data = {}

    def fetch(self, key):
        """The Record for key; raises Missing if there is none."""
        if key not in self._data:
            raise Missing(key)
        value, ttl = self._data[key]
        return Record(key, value, ttl)

    def put(self, key, value, *, ttl=None):
        """Store a value. ttl is a datetime.timedelta, keyword-only (None: never expires)."""
        if ttl is not None and not isinstance(ttl, timedelta):
            raise TypeError("ttl must be a datetime.timedelta or None")
        self._data[key] = (value, ttl)

    def scan(self, prefix, *, cursor=None, limit=PAGE_LIMIT):
        """One page (at most `limit` Records) under prefix, in key order, after `cursor`."""
        keys = sorted(k for k in self._data if k.startswith(prefix) and (cursor is None or k > cursor))
        chunk = keys[:limit]
        return Page([Record(k, *self._data[k]) for k in chunk], chunk[-1] if len(keys) > limit else None)

    def remove(self, key):
        """Delete key; raises Missing if there is none."""
        if key not in self._data:
            raise Missing(key)
        del self._data[key]

    def add(self, key, by=1):
        """Add `by` to a counter (missing counts as 0) and return the new value."""
        value, ttl = self._data.get(key, (0, None))
        self._data[key] = (value + by, ttl)
        return value + by

    def ttl_of(self, key):
        return self.fetch(key).ttl

    def clear(self):
        self._data.clear()


store = Store()
'''

MIGRATION = '''# Migrating from legacy.storage to storex

`legacy.storage` is being removed. Every module must use the `storex` client instead:

```python
from storex import Missing, store
```

| legacy.storage | storex | What changed |
|---|---|---|
| `get(key, default=None)` | `store.fetch(key).value` | `fetch` returns a `Record`; a missing key raises `storex.Missing` (a `KeyError`) instead of returning a default |
| `put(key, value, ttl=None)` | `store.put(key, value, ttl=None)` | `ttl` is keyword-only and must be a `datetime.timedelta`; legacy also took a number of seconds, which now raises `TypeError` |
| `scan(prefix, offset=0, limit=None, start_after=None)` | `store.scan(prefix, cursor=None)` | returns one `Page` of at most 50 `Record`s (`.key`, `.value`) instead of a list of `(key, value)` pairs; pass `page.next_cursor` back as `cursor` to get the next page (`next_cursor` is `None` on the last page). There is no `offset`; `cursor` works like `start_after` |
| `delete(key)` | `store.remove(key)` | returns nothing; a missing key raises `storex.Missing` instead of returning `False` |
| `incr(key, amount=1)` | `store.add(key, by=1)` | same behaviour (a missing counter starts at 0; the new value is returned); the step is called `by` |

Reading every record under a prefix:

```python
records, cursor = [], None
while True:
    page = store.scan(prefix, cursor=cursor)
    records += page.items
    if page.next_cursor is None:
        break
    cursor = page.next_cursor
```

Migrated code must keep each module's public functions and their behaviour.
'''


# --- call sites: legacy calls and their storex reference -------------------------------------------------------------
LEGACY_TTL_ARG = {"seconds": "TTL_SECONDS", "computed": "TTL_SECONDS", "minutes": "TTL_MINUTES * 60",
                  "hours": "TTL_HOURS * 3600", "timedelta": "TTL"}
NEW_TTL_BASE = {"seconds": "timedelta(seconds=TTL_SECONDS)", "computed": "timedelta(seconds=TTL_SECONDS)",
                "minutes": "timedelta(minutes=TTL_MINUTES)", "hours": "timedelta(hours=TTL_HOURS)",
                "timedelta": "TTL"}


class Ops:
    """Renders one module's storage operations, as legacy calls (legacy=True) or as the storex reference."""

    def __init__(self, m: Module, legacy: bool, facts: dict):
        self.m, self.legacy, self.facts, self.v = m, legacy, facts, m.v
        self.access = m.v["access"]
        self.used: set[str] = set()

    # -- what the module stores and how
    @property
    def has_ttl(self) -> bool:
        if self.m.p.get("ttl") is None:
            return False
        return self.legacy or not (self.m.arch == "audit" and self.facts["F1"])

    @property
    def capped(self) -> bool:
        return self.has_ttl and not self.legacy and self.facts["F3"] and self.m.p["ttl"] > 3600

    def prefix(self) -> str:
        p = PREFIXES[self.m.arch].format(e=self.m.entity)
        if not self.legacy and self.m.arch in COUNTERS and self.facts["F2"]:
            p = "counter/" + p[len("count/"):]
        return p

    @property
    def layered(self) -> bool:
        return self.access in ("repo", "wrappers")

    def _recv(self) -> str:
        return {"canonical": "storage", "wrappers": "storage", "dotted": "legacy.storage", "repo": "self._client"
                }.get(self.access, self.v.get("alias", ""))

    def _callee(self, fn: str) -> str:
        if self.access == "fromimport":
            return self.v["fnames"][fn]
        return f"{self._recv()}.{fn}"

    def key(self, name: str) -> str:
        ks = self.v["key"]
        if ks == "helper":
            return f"_key({name})"
        if ks == "fstr":
            return f'f"{{PREFIX}}{{{name}}}"'
        return f"PREFIX + {name}"

    def ttl_arg(self) -> str:
        return LEGACY_TTL_ARG[self.v["ttl"]]

    # -- legacy call text
    def _l_get(self, key: str, default: str | None) -> str:
        kw = self.v["fmt"]["get"] == "kw"
        if default is None:
            args = [f"key={key}" if kw else key]
        else:
            args = [key, f"default={default}" if kw else default]
        return f"{self._callee('get')}({', '.join(args)})"

    def _l_put(self, key: str, value: str, ttl: str | None, ind: str) -> str:
        f = self.v["fmt"]["put"]
        if f == "positional" and ttl:
            args = [key, value, ttl]
        elif f in ("kw", "kwrev"):
            args = [f"key={key}", f"value={value}"]
            if f == "kwrev":
                args.reverse()
            args += [f"ttl={ttl}"] if ttl else []
        else:
            args = [key, value] + ([f"ttl={ttl}"] if ttl else [])
        if f == "split":
            return f"{ind}{self._callee('put')}(\n" + "".join(f"{ind}{INDENT}{a},\n" for a in args) + f"{ind})"
        return f"{ind}{self._callee('put')}({', '.join(args)})"

    def _l_incr(self, key: str, by: str | None, ind: str) -> str:
        f = self.v["fmt"]["incr"]
        args = [key] if by is None else [key, by if f == "plain" else f"amount={by}"]
        if f == "split" and by is not None:
            return f"{self._callee('incr')}(\n" + "".join(f"{ind}{INDENT}{a},\n" for a in args) + f"{ind})"
        return f"{self._callee('incr')}({', '.join(args)})"

    def _l_delete(self, key: str) -> str:
        return f"{self._callee('delete')}({'key=' if self.v['fmt']['delete'] == 'kw' else ''}{key})"

    def _l_loop(self, prefix: str, kvar: str, vvar: str, body: list[str], ind: str, style: str) -> str:
        scan = self._callee("scan")
        if style == "all":
            return f"{ind}for {kvar}, {vvar} in {scan}({prefix}):\n" + _block(body, ind + INDENT)
        if style == "offset":
            return (f"{ind}offset = 0\n{ind}while True:\n"
                    f"{ind}    batch = {scan}({prefix}, offset=offset, limit=_BATCH)\n"
                    f"{ind}    if not batch:\n{ind}        break\n{ind}    for {kvar}, {vvar} in batch:\n"
                    + _block(body, ind + 2 * INDENT) + f"\n{ind}    offset += len(batch)")
        return (f"{ind}last = None\n{ind}while True:\n"
                f"{ind}    batch = {scan}({prefix}, start_after=last, limit=_BATCH)\n"
                f"{ind}    for {kvar}, {vvar} in batch:\n" + _block(body, ind + 2 * INDENT)
                + f"\n{ind}    if len(batch) < _BATCH:\n{ind}        break\n{ind}    last = batch[-1][0]")

    # -- operations used by archetype code; `name` is the record's name (the key minus PREFIX)
    def _layer(self, op: str) -> str:
        if self.access == "wrappers":
            return {"read": "_read", "write": "_write", "drop": "_drop", "bump": "_bump", "rows": "_rows"}[op]
        return f"{self.v['inst']}.{op}"

    def get(self, name: str, default: str | None = None) -> str:
        self.used.add("get")
        tail = "" if default is None else f", {default}"
        if self.layered:
            return f"{self._layer('read')}({name}{tail})"
        if self.legacy:
            return self._l_get(self.key(name), default)
        return f"_fetch({self.key(name)}{tail})"

    def put(self, name: str, value: str, ind: str = INDENT) -> str:
        self.used.add("put")
        if self.access == "wrappers":
            return f"{ind}_write({name}, {value})"
        if self.access == "repo":
            ttl = (self.ttl_arg() if self.legacy else "_TTL") if self.has_ttl else None
            return f"{ind}{self._layer('write')}({name}, {value}{f', ttl={ttl}' if ttl else ''})"
        if self.legacy:
            return self._l_put(self.key(name), value, self.ttl_arg() if self.has_ttl else None, ind)
        return f"{ind}store.put({self.key(name)}, {value}{', ttl=_TTL' if self.has_ttl else ''})"

    def delete(self, name: str) -> str:
        self.used.add("delete")
        if self.layered:
            return f"{self._layer('drop')}({name})"
        return self._l_delete(self.key(name)) if self.legacy else f"_remove({self.key(name)})"

    def incr(self, name: str, by: str | None, ind: str = INDENT) -> str:
        self.used.add("incr")
        tail = "" if by is None else f", {by}"
        if self.layered:
            return f"{self._layer('bump')}({name}{tail})"
        return self._l_incr(self.key(name), by, ind) if self.legacy else f"store.add({self.key(name)}{tail})"

    def loop(self, nvar: str, vvar: str, body: list[str], ind: str = INDENT) -> str:
        """`for nvar, vvar in <every record under PREFIX, in key order>:` + body."""
        self.used.add("scan")
        if self.layered or self.v["scan"] == "rows":
            rows = self._layer("rows") if self.layered else "_rows"
            return f"{ind}for {nvar}, {vvar} in {rows}():\n" + _block(body, ind + INDENT)
        kvar = "_" if nvar == "_" else "key"
        body = ([] if nvar == "_" else [f"{nvar} = key[len(PREFIX):]"]) + body
        if self.legacy:
            return self._l_loop("PREFIX", kvar, vvar, body, ind, self.v["scan"])
        return f"{ind}for {kvar}, {vvar} in _records(PREFIX):\n" + _block(body, ind + INDENT)

    # -- module-level pieces that depend on what the archetype used
    def needs_batch(self) -> bool:
        if not self.legacy or "scan" not in self.used:
            return False
        style = self.v["rows_inner"] if (self.layered or self.v["scan"] == "rows") else self.v["scan"]
        return style in ("offset", "cursor")

    def storex_names(self) -> list[str]:
        return (["Missing"] if self.used & {"get", "delete"} else []) + ["store"]

    def consts(self) -> list[str]:
        """PREFIX (and its parts), the client variable and the ttl constants."""
        out = []
        pre = self.prefix()
        if self.v["key"] == "helper":
            ns, scope = pre.rstrip("/").split("/", 1)
            out += [f'NAMESPACE = "{ns}"', f'SCOPE = "{scope}"', 'PREFIX = f"{NAMESPACE}/{SCOPE}/"']
        else:
            out.append(f'PREFIX = "{pre}"')
        if self.m.p.get("ttl") is not None:
            out += self._ttl_consts()
        if self.needs_batch():
            out.append(f"_BATCH = {self.v['batch']}  # records per scan call")
        if self.legacy and self.access == "injected":
            out.append(f"{self.v['alias']} = storage  # {self.v['inject_note']}")
        return out

    def _ttl_consts(self) -> list[str]:
        s, style, note = self.m.p["ttl"], self.v["ttl"], self.m.logic["ttl_note"]
        if style == "seconds":
            out = [f"TTL_SECONDS = {s}  # {note}"]
        elif style == "computed":
            out = [f"TTL_SECONDS = {s // 3600} * 60 * 60  # {note}" if s % 3600 == 0 else
                   f"TTL_SECONDS = {s // 60} * 60  # {note}"]
        elif style == "minutes":
            out = [f"TTL_MINUTES = {s // 60}  # {note}"]
        elif style == "hours":
            out = [f"TTL_HOURS = {s // 3600}  # {note}"]
        else:
            arg = "days=1" if s == 86400 else f"hours={s // 3600}" if s % 3600 == 0 else f"minutes={s // 60}"
            out = [f"TTL = timedelta({arg})  # {note}"]
        if not self.legacy:
            if self.has_ttl:
                base = NEW_TTL_BASE[style]
                if self.capped:
                    out += ["MAX_TTL = timedelta(hours=1)  # no ttl above one hour", f"_TTL = min({base}, MAX_TTL)"]
                else:
                    out.append(f"_TTL = {base}")
            else:
                out[-1] = out[-1].split("  #")[0] + "  # legacy retention; audit records no longer expire"
        return out

    def needs_timedelta(self) -> bool:
        if self.m.p.get("ttl") is None:
            return False
        return self.v["ttl"] == "timedelta" or (not self.legacy and self.has_ttl)

    def layer_chunks(self) -> list[str]:
        """Private helpers that hold the storage calls: key helper, wrappers, repository class, rows helper and,
        in the reference, the storex helpers that keep legacy semantics."""
        out = []
        if self.v["key"] == "helper" and self.access != "repo":
            out.append('''
def _key(name):
    """The storage key for one record."""
    return "/".join((NAMESPACE, SCOPE, name))
''')
        if not self.legacy and self.access != "repo":
            out += self._storex_helpers()
        if self.access == "wrappers":
            out += self._wrappers()
        elif self.access == "repo":
            out.append(self._repo())
        elif self.v["scan"] == "rows" and "scan" in self.used:
            out.append(self._rows_fn())
        return out

    def _storex_helpers(self) -> list[str]:
        out = []
        if "get" in self.used:
            out.append('''
def _fetch(key, default=None):
    """The stored value, or default when there is none."""
    try:
        return store.fetch(key).value
    except Missing:
        return default
''')
        if "delete" in self.used:
            out.append('''
def _remove(key):
    """Delete key. True if it existed."""
    try:
        store.remove(key)
    except Missing:
        return False
    return True
''')
        if "scan" in self.used:
            out.append('''
def _records(prefix):
    """Every (key, value) under prefix, across all pages, in key order."""
    rows, cursor = [], None
    while True:
        page = store.scan(prefix, cursor=cursor)
        rows += [(r.key, r.value) for r in page.items]
        if page.next_cursor is None:
            return rows
        cursor = page.next_cursor
''')
        return out

    def _rows_fn(self) -> str:
        doc = '"""(name, value) for every record under PREFIX, in name order."""'
        if not self.legacy:
            return f"\ndef _rows():\n    {doc}\n    return [(key[len(PREFIX):], value) for key, value in _records(PREFIX)]\n"
        loop = self._l_loop("PREFIX", "key", "value", ["rows.append((key[len(PREFIX):], value))"], INDENT,
                            self.v["rows_inner"])
        return f"\ndef _rows():\n    {doc}\n    rows = []\n{loop}\n    return rows\n"

    def _wrappers(self) -> list[str]:
        out, u = [], self.used
        if "get" in u:
            call = self._l_get(self.key("name"), "default") if self.legacy else f"_fetch({self.key('name')}, default)"
            out.append(f'\ndef _read(name, default=None):\n    """The value stored for name, or default."""\n'
                       f"    return {call}\n")
        if "put" in u:
            if self.legacy:
                sig = f"name, value, ttl={self.ttl_arg()}" if self.has_ttl else "name, value"
                ttl = "ttl" if self.has_ttl else None
                body = (f"{INDENT}{self._callee('put')}({self.key('name')}, value, ttl)" if ttl and
                        self.v["fmt"]["put"] != "split" else self._l_put(self.key("name"), "value", ttl, INDENT))
            else:
                sig = "name, value"
                body = f"{INDENT}store.put({self.key('name')}, value{', ttl=_TTL' if self.has_ttl else ''})"
            out.append(f'\ndef _write({sig}):\n    """Store value for name."""\n{body}\n')
        if "delete" in u:
            call = self._l_delete(self.key("name")) if self.legacy else f"_remove({self.key('name')})"
            out.append(f'\ndef _drop(name):\n    """Delete the record for name. True if it existed."""\n'
                       f"    return {call}\n")
        if "incr" in u:
            call = self._l_incr(self.key("name"), "amount", INDENT) if self.legacy else \
                f"store.add({self.key('name')}, amount)"
            out.append(f'\ndef _bump(name, amount=1):\n    """Add amount to the counter for name; returns the new '
                       f'value."""\n    return {call}\n')
        if "scan" in u:
            out.append(self._rows_fn())
        return out

    def _repo(self) -> str:
        cls, inst, u = self.v["cls"], self.v["inst"], self.used
        head = (f'\nclass {cls}:\n    """Records under one key prefix of the shared key-value store."""\n\n'
                f"    def __init__(self, client, prefix):\n        self._client = client\n"
                f"        self._prefix = prefix\n")
        meths = []
        key = "self._prefix + name"
        if self.legacy:
            if "get" in u:
                meths.append(f"    def read(self, name, default=None):\n        return {self._l_get(key, 'default')}\n")
            if "put" in u:
                if self.has_ttl:
                    meths.append("    def write(self, name, value, ttl=None):\n"
                                 + self._l_put(key, "value", "ttl", 2 * INDENT) + "\n")
                else:
                    meths.append("    def write(self, name, value):\n"
                                 + self._l_put(key, "value", None, 2 * INDENT) + "\n")
            if "delete" in u:
                meths.append(f"    def drop(self, name):\n        return {self._l_delete(key)}\n")
            if "incr" in u:
                meths.append(f"    def bump(self, name, amount=1):\n"
                             f"        return {self._l_incr(key, 'amount', 2 * INDENT)}\n")
            if "scan" in u:
                loop = self._l_loop("self._prefix", "key", "value", ["rows.append((key[len(self._prefix):], value))"],
                                    2 * INDENT, self.v["rows_inner"])
                meths.append('    def rows(self):\n        """(name, value) for every record, in name order."""\n'
                             f"        rows = []\n{loop}\n        return rows\n")
            client = self.v.get("alias") or "storage"
        else:
            if "get" in u:
                meths.append("    def read(self, name, default=None):\n        try:\n"
                             f"            return self._client.fetch({key}).value\n"
                             "        except Missing:\n            return default\n")
            if "put" in u:
                ttl = ", ttl=ttl" if self.has_ttl else ""
                sig = "name, value, ttl=None" if self.has_ttl else "name, value"
                meths.append(f"    def write(self, {sig}):\n        self._client.put({key}, value{ttl})\n")
            if "delete" in u:
                meths.append(f"    def drop(self, name):\n        try:\n            self._client.remove({key})\n"
                             "        except Missing:\n            return False\n        return True\n")
            if "incr" in u:
                meths.append(f"    def bump(self, name, amount=1):\n        return self._client.add({key}, amount)\n")
            if "scan" in u:
                meths.append('    def rows(self):\n        """(name, value) for every record, in name order."""\n'
                             "        rows, cursor = [], None\n        while True:\n"
                             "            page = self._client.scan(self._prefix, cursor=cursor)\n"
                             "            rows += [(r.key[len(self._prefix):], r.value) for r in page.items]\n"
                             "            if page.next_cursor is None:\n                return rows\n"
                             "            cursor = page.next_cursor\n")
            client = "store"
        return head + "".join("\n" + mt for mt in meths) + f"\n\n{inst} = {cls}({client}, PREFIX)\n"

    def import_lines(self) -> list[str]:
        if not self.legacy:
            return [f"from storex import {', '.join(self.storex_names())}"]
        a = self.access
        if a in ("canonical", "wrappers", "injected") or (a == "repo" and not self.v.get("alias")):
            return ["from legacy import storage"]
        if a in ("alias", "repo"):
            return [f"from legacy import storage as {self.v['alias']}"]
        if a == "modalias":
            return [f"import legacy.storage as {self.v['alias']}"]
        if a == "dotted":
            return ["import legacy.storage"]
        names = sorted(fn if alias == fn else f"{fn} as {alias}" for fn, alias in self.v["fnames"].items()
                       if fn in self.used or (fn == "scan" and "scan" in self.used))
        return [f"from legacy.storage import {', '.join(names)}"]


# --- business logic: id cleaners --------------------------------------------------------------------------------------
CLEANER_SRC = {
    "lower": '''
_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{0,@@max@@}$")


def @@fn@@(raw):
    """A @@noun@@ id: trimmed, lower case, letters, digits, '-' and '_' only."""
    if not isinstance(raw, str):
        raise TypeError(f"@@noun@@ id must be a string, not {type(raw).__name__}")
    value = raw.strip().lower()
    if not _ID_PATTERN.match(value):
        raise ValueError(f"bad @@noun@@ id: {raw!r}")
    return value
''',
    "numeric": '''
ID_WIDTH = @@width@@  # digits in a stored id


def @@fn@@(raw):
    """@@Noun@@ ids are positive whole numbers; keys hold them zero-padded so they sort numerically."""
    try:
        number = int(str(raw).strip())
    except ValueError:
        raise ValueError(f"bad @@noun@@ id: {raw!r}") from None
    if not 0 < number < 10 ** ID_WIDTH:
        raise ValueError(f"@@noun@@ id out of range: {number}")
    return f"{number:0{ID_WIDTH}d}"
''',
    "code": '''
CODE_PREFIX = "@@cp@@"


def @@fn@@(raw):
    """@@Noun@@ codes look like @@cp@@-1234; lower case, spaces and a missing prefix are accepted."""
    value = str(raw).strip().upper()
    if not value.startswith(CODE_PREFIX + "-"):
        value = f"{CODE_PREFIX}-{value}"
    digits = value[len(CODE_PREFIX) + 1:]
    if not digits.isdigit() or len(digits) > @@maxd@@:
        raise ValueError(f"bad @@noun@@ code: {raw!r}")
    return value
''',
    "slug": '''
MAX_SLUG = @@max@@


def @@fn@@(raw):
    """A @@noun@@ name as a slug: lower-case words joined by '-', at most MAX_SLUG characters."""
    words = re.findall(r"[a-z0-9]+", str(raw).lower())
    if not words:
        raise ValueError(f"no letters or digits in @@noun@@ name {raw!r}")
    return "-".join(words)[:MAX_SLUG]
''',
    "email": '''
def @@fn@@(raw):
    """@@Noun@@s are identified by e-mail address, compared case-insensitively."""
    value = str(raw).strip().lower()
    local, at, domain = value.partition("@")
    if not at or not local or "." not in domain.strip("."):
        raise ValueError(f"not an e-mail address: {raw!r}")
    return value
''',
    "dotted": '''
_NAME_PATTERN = re.compile(r"^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")


def @@fn@@(raw):
    """A dotted @@noun@@ name such as 'api.calls'; '/' and spaces are accepted as '.' and '_'."""
    value = str(raw).strip().lower().replace("/", ".").replace(" ", "_")
    if not _NAME_PATTERN.match(value):
        raise ValueError(f"bad @@noun@@ name: {raw!r}")
    return value
''',
}
CLEANER_RE = {"lower", "slug", "dotted"}


def _cleaner_samples(kind: str, params: dict) -> dict:
    """Valid raw ids (i0, i1, i2), another spelling of i0 (a0), an invalid id (bad), and an id for loop index i."""
    if kind == "lower":
        return dict(i=["S1", "ab-7", "zed_3"], a0=" s1 ", bad="no spaces!", loop='f"k{i:03d}"')
    if kind == "numeric":
        return dict(i=["17", "42", "7"], a0=" 017", bad="abc", loop="str(i + 1)")
    if kind == "code":
        cp = params["cp"]
        return dict(i=[f"{cp}-12", "300", f"{cp.lower()}-7"], a0="12", bad=f"{cp}-x1", loop='f"{i:04d}"')
    if kind == "slug":
        return dict(i=["Blue Widget", "red box 2", "gamma"], a0="  blue--WIDGET ", bad="!!!", loop='f"Item {i:03d}"')
    if kind == "email":
        return dict(i=["ann@example.com", "bob@shop.io", "cy@mail.net"], a0="  Ann@Example.COM", bad="ann",
                    loop='f"u{i:03d}@example.com"')
    return dict(i=["api.calls", "queue.depth", "hits"], a0="API/Calls", bad="9lives", loop='f"m.k{i:03d}"')


# --- business logic: pure public helpers (seeded constants; some get their own hidden test) --------------------------
PURE = {
    "money": (["format_amount", "display_amount", "money_label"], set(), '''
CURRENCY = "@@cur@@"


def @@fn@@(cents, currency=CURRENCY):
    """Whole cents as a display amount, e.g. 123456 -> '1,234.56 @@cur@@'."""
    if isinstance(cents, bool) or not isinstance(cents, int):
        raise TypeError("amount must be whole cents")
    sign = "-" if cents < 0 else ""
    units, rest = divmod(abs(cents), 100)
    return f"{sign}{units:,}.{rest:02d} {currency}"
''', lambda r: dict(cur=r.choice(["EUR", "USD", "GBP", "CHF", "SEK"])),
        ["@@fn@@(123456)", "@@fn@@(-5)", "@@fn@@(100000000, 'JPY')"]),
    "percent": (["share", "percent_of", "as_percent"], set(), '''
def @@fn@@(part, whole, digits=@@d@@):
    """part as a percentage of whole with `digits` decimals; '-' when whole is zero."""
    if whole == 0:
        return "-"
    return f"{100 * part / whole:.{digits}f}%"
''', lambda r: dict(d=r.choice([0, 1, 2])), ["@@fn@@(1, 3)", "@@fn@@(5, 0)", "@@fn@@(7, 8, 2)"]),
    "mask": (["mask_email", "redact_address", "hide_email"], set(), '''
def @@fn@@(address):
    """Hide most of the local part of an e-mail address: 'jane.doe@x.io' -> 'j@@c@@@@c@@@@c@@@@c@@@@c@@@@c@@e@x.io'."""
    local, at, domain = address.partition("@")
    if not at:
        raise ValueError(f"not an e-mail address: {address!r}")
    if len(local) <= 2:
        return "@@c@@" * len(local) + "@" + domain
    return local[0] + "@@c@@" * (len(local) - 2) + local[-1] + "@" + domain
''', lambda r: dict(c=r.choice(["*", "#", "x"])), ["@@fn@@('jane.doe@x.io')", "@@fn@@('al@b.co')"]),
    "duration": (["parse_duration", "duration_seconds", "to_seconds"], {"re"}, '''
_DURATION_PART = re.compile(r"(\\d+)\\s*([dhms])")
_UNIT_SECONDS = {"d": 86400, "h": 3600, "m": 60, "s": 1}


def @@fn@@(text):
    """'1h30m' or '2d 4h' as seconds. Raises ValueError on anything else."""
    text = text.strip().lower()
    parts = _DURATION_PART.findall(text)
    if not parts or _DURATION_PART.sub("", text).strip():
        raise ValueError(f"bad duration: {text!r}")
    return sum(int(n) * _UNIT_SECONDS[unit] for n, unit in parts)
''', lambda r: {}, ["@@fn@@('1h30m')", "@@fn@@(' 2d 4h ')", "@@fn@@('45s')"]),
    "tier": (["tier_for", "level_name", "badge_for"], set(), '''
TIERS = [(@@a@@, "bronze"), (@@b@@, "silver"), (@@c@@, "gold")]  # (threshold, name), ascending


def @@fn@@(points):
    """The highest tier whose threshold the points reach, or 'none'."""
    reached = "none"
    for threshold, name in TIERS:
        if points >= threshold:
            reached = name
    return reached
''', lambda r: dict(a=r.choice([10, 50, 100]), b=r.choice([200, 500]), c=r.choice([1000, 2500])),
        ["[@@fn@@(p) for p in (0, 60, 600, 5000)]"]),
    "backoff": (["retry_delay", "backoff_seconds", "wait_before_retry"], set(), '''
def @@fn@@(attempt, base=@@b@@, cap=@@c@@):
    """Seconds to wait before retry number `attempt` (1-based): doubling from base, never above cap."""
    if attempt < 1:
        raise ValueError("attempts start at 1")
    return min(cap, base * 2 ** (attempt - 1))
''', lambda r: dict(b=r.choice([1, 2, 5]), c=r.choice([60, 300, 900])), ["[@@fn@@(n) for n in (1, 2, 5, 20)]"]),
    "weekdays": (["business_days", "weekdays_between", "working_days"], {"datetime.date", "datetime.timedelta"}, '''
def @@fn@@(start, end):
    """Weekdays (Monday to Friday) from start up to, not including, end; both ISO dates."""
    day, stop = date.fromisoformat(start), date.fromisoformat(end)
    count = 0
    while day < stop:
        if day.weekday() < 5:
            count += 1
        day += timedelta(days=1)
    return count
''', lambda r: {}, ["@@fn@@('2026-11-02', '2026-11-16')", "@@fn@@('2026-11-07', '2026-11-09')"]),
    "shipping": (["shipping_cost", "postage", "delivery_fee"], set(), '''
ZONE_RATES = {"domestic": @@d@@, "eu": @@e@@, "world": @@w@@}  # cents per started kilogram


def @@fn@@(weight_grams, zone="domestic"):
    """Shipping in cents: the zone's rate per started kilogram, at least one kilogram."""
    if zone not in ZONE_RATES:
        raise ValueError(f"unknown zone: {zone}")
    kilos = max(1, -(-int(weight_grams) // 1000))
    return kilos * ZONE_RATES[zone]
''', lambda r: dict(d=r.choice([290, 350, 499]), e=r.choice([890, 990]), w=r.choice([1590, 2200])),
        ["@@fn@@(250)", "@@fn@@(2001, 'eu')", "@@fn@@(999, 'world')"]),
    "luhn": (["luhn_ok", "card_checksum_ok", "valid_card_number"], set(), '''
def @@fn@@(number):
    """True if the digits of number pass the Luhn checksum; spaces and dashes are ignored."""
    digits = [int(ch) for ch in str(number) if ch.isdigit()]
    if len(digits) < 2:
        return False
    total = 0
    for i, d in enumerate(reversed(digits)):
        if i % 2:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0
''', lambda r: {}, ["@@fn@@('4539 1488 0343 6467')", "@@fn@@('1234-5678')", "@@fn@@('7')"]),
    "humanize": (["humanize", "compact_count", "short_number"], set(), '''
def @@fn@@(n):
    """A compact count: 999 -> '999', 1234 -> '1.2k', 5600000 -> '5.6M'."""
    for limit, suffix in ((10 ** 9, "B"), (10 ** 6, "M"), (10 ** 3, "k")):
        if abs(n) >= limit:
            return f"{n / limit:.1f}{suffix}"
    return str(n)
''', lambda r: {}, ["[@@fn@@(n) for n in (999, 1234, 5600000, -2500)]"]),
    "names": (["split_name", "name_parts", "first_and_rest"], set(), '''
def @@fn@@(full_name):
    """(first, rest) of a display name, each word capitalized; extra spaces are dropped."""
    words = full_name.split()
    if not words:
        raise ValueError("empty name")
    return words[0].capitalize(), " ".join(w.capitalize() for w in words[1:])
''', lambda r: {}, ["@@fn@@('  ada   LOVELACE ')", "@@fn@@('cher')"]),
    "discount": (["apply_discount", "discounted", "price_after_code"], set(), '''
DISCOUNTS = {"WELCOME": @@a@@, "LOYAL": @@b@@, "STAFF": @@c@@}  # percent off


def @@fn@@(cents, code=None):
    """The price after a discount code, rounded down to whole cents; unknown codes raise ValueError."""
    if code is None:
        return cents
    pct = DISCOUNTS.get(code.strip().upper())
    if pct is None:
        raise ValueError(f"unknown discount code: {code}")
    return cents * (100 - pct) // 100
''', lambda r: dict(a=r.choice([5, 10, 15]), b=r.choice([7, 12, 20]), c=r.choice([25, 30, 40])),
        ["@@fn@@(1999)", "@@fn@@(1999, ' welcome')", "@@fn@@(1000, 'STAFF')"]),
    "label": (["duration_label", "elapsed_label", "short_duration"], set(), '''
def @@fn@@(seconds):
    """A short label for a duration: 3725 -> '1h 2m', 59 -> '59s'."""
    if seconds < 60:
        return f"{seconds}s"
    minutes = seconds // 60
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    return " ".join(f"{v}{u}" for v, u in ((days, "d"), (hours, "h"), (minutes, "m")) if v)
''', lambda r: {}, ["[@@fn@@(s) for s in (59, 3725, 90061)]"]),
    "phone": (["normalize_phone", "phone_e164", "clean_phone"], {"re"}, '''
COUNTRY_CODE = "@@cc@@"


def @@fn@@(raw, country=COUNTRY_CODE):
    """A phone number as '+<country><digits>'; a leading 0 is the trunk prefix and is dropped."""
    digits = re.sub(r"\\D", "", raw)
    if raw.strip().startswith("+"):
        return "+" + digits
    if digits.startswith("0"):
        digits = digits[1:]
    if len(digits) < 6:
        raise ValueError(f"phone number too short: {raw!r}")
    return f"+{country}{digits}"
''', lambda r: dict(cc=r.choice(["31", "44", "49", "33", "1"])), ["@@fn@@('020 123 4567')", "@@fn@@('+1 (555) 010')"]),
    "quantize": (["round_to_step", "quantize", "snap"], set(), '''
def @@fn@@(value, step=@@s@@):
    """value rounded to the nearest multiple of step; halves round up."""
    if step <= 0:
        raise ValueError("step must be positive")
    return (value + step // 2) // step * step
''', lambda r: dict(s=r.choice([5, 10, 25, 50])), ["[@@fn@@(v) for v in (0, 7, 12, 99, 250)]"]),
    "chunks": (["chunked", "in_batches", "batches_of"], set(), '''
def @@fn@@(items, size=@@s@@):
    """items in consecutive lists of at most `size` elements."""
    if size < 1:
        raise ValueError("size must be at least 1")
    items = list(items)
    return [items[i:i + size] for i in range(0, len(items), size)]
''', lambda r: dict(s=r.choice([2, 3, 4])), ["@@fn@@(range(7))", "@@fn@@('abcde', 2)"]),
    "vat": (["with_vat", "gross_price", "vat_split"], set(), '''
VAT_PERCENT = @@r@@


def @@fn@@(net_cents):
    """(net, vat, gross) in cents; the VAT rounds half up to the cent."""
    vat = (net_cents * VAT_PERCENT + 50) // 100
    return net_cents, vat, net_cents + vat
''', lambda r: dict(r=r.choice([7, 9, 19, 20, 21, 25])), ["@@fn@@(1000)", "@@fn@@(1999)"]),
    "initials": (["initials", "monogram", "short_name"], set(), '''
def @@fn@@(full_name, limit=@@n@@):
    """Up to `limit` upper-case initials of a name: 'ada king lovelace' -> 'AKL'."""
    letters = [word[0].upper() for word in full_name.replace("-", " ").split() if word[0].isalpha()]
    return "".join(letters[:limit])
''', lambda r: dict(n=r.choice([2, 3])), ["@@fn@@('ada king lovelace')", "@@fn@@('jean-luc picard')"]),
    "truncate": (["truncate_words", "shorten", "excerpt"], set(), '''
def @@fn@@(text, limit=@@n@@, ellipsis="..."):
    \"\"\"text cut to at most `limit` characters at a word boundary, with an ellipsis when it was cut.\"\"\"
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    cut = text[:limit - len(ellipsis)].rsplit(" ", 1)[0]
    return cut + ellipsis
''', lambda r: dict(n=r.choice([20, 30, 40])),
        ["@@fn@@('the quick brown fox jumps over the lazy dog again and again')", "@@fn@@('short')",
         "@@fn@@('  spaced   out   words here ', 12)"]),
    "slugify": (["slugify", "url_slug", "make_slug"], {"re"}, '''
def @@fn@@(title, sep="@@sep@@"):
    \"\"\"A URL slug: the lower-case ASCII words of title joined by sep.\"\"\"
    words = re.findall(r"[a-z0-9]+", title.lower())
    return sep.join(words)
''', lambda r: dict(sep=r.choice(["-", "_"])), ["@@fn@@('Hello, World! 2026')", "@@fn@@('  ')"]),
    "wmean": (["weighted_mean", "weighted_average", "mean_by_weight"], set(), '''
def @@fn@@(pairs, digits=@@d@@):
    \"\"\"The weighted mean of (value, weight) pairs, rounded; None when the weights sum to zero.\"\"\"
    total = sum(w for _, w in pairs)
    if total == 0:
        return None
    return round(sum(v * w for v, w in pairs) / total, digits)
''', lambda r: dict(d=r.choice([1, 2, 3])), ["@@fn@@([(3, 1), (5, 3)])", "@@fn@@([])", "@@fn@@([(1, 0), (2, 0)])"]),
    "nextday": (["next_weekday", "following_weekday", "next_day_named"], {"datetime.date", "datetime.timedelta"}, '''
_DAY_NAMES = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


def @@fn@@(iso_date, day="@@day@@"):
    \"\"\"The first date strictly after iso_date that falls on `day` (mon..sun), as an ISO date.\"\"\"
    start = date.fromisoformat(iso_date)
    target = _DAY_NAMES.index(day[:3].lower())
    ahead = (target - start.weekday() - 1) % 7 + 1
    return (start + timedelta(days=ahead)).isoformat()
''', lambda r: dict(day=r.choice(["mon", "fri", "sun"])), ["@@fn@@('2026-11-15')", "@@fn@@('2026-11-16', 'Monday')"]),
    "csv": (["csv_line", "to_csv_row", "csv_row"], set(), '''
def @@fn@@(fields, sep="@@sep@@"):
    \"\"\"One CSV line: a field is quoted when it holds the separator, a quote or a newline.\"\"\"
    out = []
    for value in fields:
        text = "" if value is None else str(value)
        if sep in text or '"' in text or "\\n" in text:
            text = '"' + text.replace('"', '""') + '"'
        out.append(text)
    return sep.join(out)
''', lambda r: dict(sep=r.choice([",", ";"])), ["@@fn@@(['a', 'b,c', None, 'say \"hi\"'])", "@@fn@@([1, 2.5, 'x;y'])"]),
    "convert": (["convert_cents", "to_currency", "exchange"], set(), '''
RATES = {"EUR": 100, "USD": @@usd@@, "GBP": @@gbp@@}  # units per 100 EUR


def @@fn@@(cents, src="EUR", dst="USD"):
    \"\"\"Whole cents converted between currencies through EUR, rounded half up to the cent.\"\"\"
    if src not in RATES or dst not in RATES:
        raise ValueError(f"unknown currency: {src if src not in RATES else dst}")
    eur = cents * 100 / RATES[src]
    return int(eur * RATES[dst] / 100 + 0.5)
''', lambda r: dict(usd=r.choice([105, 108, 112]), gbp=r.choice([84, 86, 88])),
        ["@@fn@@(1000)", "@@fn@@(1999, 'GBP', 'EUR')", "@@fn@@(0, 'USD', 'GBP')"]),
    "plural": (["plural", "pluralize", "count_label"], set(), '''
IRREGULAR = {"person": "people", "child": "children", "box": "boxes"}


def @@fn@@(n, word):
    \"\"\"'1 item', '3 items', '2 people': n followed by the right form of word.\"\"\"
    if n == 1:
        return f"{n} {word}"
    form = IRREGULAR.get(word)
    if form is None:
        form = word[:-1] + "ies" if word.endswith("y") and word[-2:-1] not in "aeiou" else word + "s"
    return f"{n} {form}"
''', lambda r: {}, ["[@@fn@@(n, w) for n, w in ((1, 'item'), (3, 'city'), (2, 'person'), (0, 'day'))]"]),
    "bucket": (["age_bucket", "bucket_for", "range_label"], set(), '''
BUCKETS = (@@a@@, @@b@@, @@c@@)  # upper bounds in days, exclusive


def @@fn@@(days):
    \"\"\"'<a', 'a-b', 'b-c' or 'c+' for a number of days, using BUCKETS.\"\"\"
    if days < 0:
        raise ValueError("days cannot be negative")
    low = 0
    for high in BUCKETS:
        if days < high:
            return f"<{high}" if low == 0 else f"{low}-{high - 1}"
        low = high
    return f"{low}+"
''', lambda r: dict(a=r.choice([7, 14]), b=r.choice([30, 60]), c=r.choice([90, 180, 365])),
        ["[@@fn@@(d) for d in (0, 10, 45, 100, 400)]"]),
    "isoweek": (["week_label", "iso_week", "week_of"], {"datetime.date"}, '''
def @@fn@@(iso_date):
    \"\"\"The ISO week of a date as 'YYYY-Www', e.g. '2026-W46'.\"\"\"
    year, week, _ = date.fromisoformat(iso_date).isocalendar()
    return f"{year}-W{week:02d}"
''', lambda r: {}, ["@@fn@@('2026-11-15')", "@@fn@@('2027-01-01')"]),
    "amount": (["parse_amount", "cents_from_text", "read_amount"], set(), '''
def @@fn@@(text):
    \"\"\"'12.5', '1,234.50' or '-3' as whole cents; more than two decimals raise ValueError.\"\"\"
    clean = text.strip().replace(",", "")
    sign = -1 if clean.startswith("-") else 1
    whole, _, frac = clean.lstrip("+-").partition(".")
    if not whole.isdigit() or (frac and not frac.isdigit()) or len(frac) > 2:
        raise ValueError(f"bad amount: {text!r}")
    return sign * (int(whole) * 100 + int(frac.ljust(2, "0")))
''', lambda r: {}, ["@@fn@@('12.5')", "@@fn@@(' 1,234.50 ')", "@@fn@@('-3')"]),
    "titlecase": (["title_case", "headline", "nice_title"], set(), '''
SMALL_WORDS = {"a", "an", "and", "of", "the", "to", "in", "on", "for"}


def @@fn@@(text):
    \"\"\"Title case that keeps small words lower case, except the first word.\"\"\"
    words = text.lower().split()
    return " ".join(w if i and w in SMALL_WORDS else w.capitalize() for i, w in enumerate(words))
''', lambda r: {}, ["@@fn@@('the lord OF the rings')", "@@fn@@('a tale of two cities')"]),
}

DOCS = {
    "sessions": ["@@Ent@@ sessions: the signed-in state of @@ent@@ users.",
                 "Session cache for @@ent@@: who is signed in and what they were doing."],
    "ratelimit": ["@@Ent@@ rate limiting: actions per user, within a plan's limit.",
                  "Per-user action counters for @@ent@@, checked against plan limits."],
    "stock": ["@@Ent@@ stock levels, one record per item.", "Inventory for @@ent@@: units on hand per item."],
    "flags": ["@@Ent@@ feature flags.", "Runtime switches for the @@ent@@ service."],
    "audit": ["@@Ent@@ audit log: one record per event.", "An audit trail of @@ent@@ events, kept for review."],
    "purge": ["@@Ent@@ scratch space, purged in bulk.", "Temporary @@ent@@ entries that a nightly job clears."],
    "metrics": ["@@Ent@@ metrics: named counters.", "Counters for @@ent@@ dashboards."],
    "leaderboard": ["@@Ent@@ leaderboard: each player's best score.", "Best scores per player for @@ent@@ events."],
    "profiles": ["@@Ent@@ profiles, merged over defaults.", "Per-user settings for @@ent@@, stored as overrides."],
}
NOTES = [
    "Owned by the @@team@@ team. Other services import the public functions, so keep their names and behaviour.",
    "Records live in the shared key-value store under PREFIX; nothing else writes there.",
    "Every id is normalized before it becomes part of a key, so callers may pass ids as users typed them.",
    "Validation happens before anything is written: a rejected call leaves the store as it was.",
    "The helpers at the bottom are pure and safe to call from templates and reports.",
    "Reports read the store at call time; nothing is cached in the process.",
]
TTL_NOTES = ["how long a record lives", "retention agreed with the @@team@@ team", "records expire after this",
             "keep in sync with the cleanup job", "expiry for stored records"]


# --- archetypes: storage functions (rendered through Ops) and hidden-test scenarios --------------------------------
@dataclass
class Built:
    consts: list[str] = field(default_factory=list)
    helpers: list[str] = field(default_factory=list)  # private business logic
    funcs: list[str] = field(default_factory=list)  # public functions that touch storage
    scen: list[tuple[str, list]] = field(default_factory=list)  # (label, [(kind, code)])
    write: str | None = None  # one call that writes one record with the module's ttl
    counter: str | None = None  # one call that bumps one counter (F2)


def _sessions(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    if p["check"] == 0:
        b.consts.append(f"SCHEMA_VERSION = {p['schema']}")
        chk, badp = "_session_record", '"not a dict"'
        b.helpers.append('''
def _session_record(data):
    """A clean copy of session data: string keys only, private ('_') keys dropped, schema version stamped."""
    if not isinstance(data, dict):
        raise TypeError("session data must be a dict")
    clean = {key: value for key, value in data.items() if isinstance(key, str) and not key.startswith("_")}
    clean["v"] = SCHEMA_VERSION
    return clean
''')
    elif p["check"] == 1:
        b.consts.append(f"MAX_FIELDS = {p['max_fields']}")
        chk, badp = "_checked_session", '{"user": 0}'
        b.helpers.append('''
def _checked_session(data):
    """Session data must be a dict with a positive integer 'user' and at most MAX_FIELDS fields."""
    if not isinstance(data, dict):
        raise TypeError("session data must be a dict")
    user = data.get("user")
    if isinstance(user, bool) or not isinstance(user, int) or user <= 0:
        raise ValueError("session data needs a positive integer 'user'")
    if len(data) > MAX_FIELDS:
        raise ValueError(f"too many session fields ({len(data)} > {MAX_FIELDS})")
    return dict(data)
''')
    else:
        b.consts += [f"ROLES = {tuple(p['roles'])!r}", f'DEFAULT_ROLE = "{p["roles"][0]}"']
        chk, badp = "_with_role", '{"user": 3, "role": "root"}'
        b.helpers.append('''
def _with_role(data):
    """Session data with a known role (DEFAULT_ROLE when none is given); other roles are rejected."""
    if not isinstance(data, dict):
        raise TypeError("session data must be a dict")
    role = data.get("role", DEFAULT_ROLE)
    if role not in ROLES:
        raise ValueError(f"unknown role: {role!r}")
    return {**data, "role": role}
''')
    b.funcs.append(f'''
def load(session_id):
    """The session's data, or None if it expired or never existed."""
    sid = {cl}(session_id)
    return {c.get("sid")}
''')
    b.funcs.append(f'''
def save(session_id, data):
    """Validate and store the session data; it expires after the session ttl. Returns the normalized id."""
    sid = {cl}(session_id)
    record = {chk}(data)
{c.put("sid", "record")}
    return sid
''')
    b.funcs.append(f'''
def drop(session_id):
    """Delete the session. True if it existed."""
    sid = {cl}(session_id)
    return {c.delete("sid")}
''')
    p1, p2 = '{"user": 7, "cart": [1, 2]}', '{"user": 8}'
    b.scen += [("load_missing_is_none", [("eq", "m.load(@i0@)")]),
               ("save_then_load", [("do", f"m.save(@i0@, {p1})"), ("eq", "m.load(@i0@)"), ("eq", "m.load(@i1@)")]),
               ("ids_are_normalized", [("eq", f"m.save(@a0@, {p2})"), ("eq", "m.load(@i0@)")]),
               ("drop", [("do", f"m.save(@i0@, {p2})"), ("eq", "m.drop(@i0@)"), ("eq", "m.drop(@a0@)"),
                         ("eq", "m.load(@i0@)")]),
               ("rejects_bad_input", [("do", f"m.save(@i1@, {p2})"), ("raises", f"m.save(@bad@, {p2})"),
                                      ("raises", f"m.save(@i0@, {badp})"), ("eq", "m.load(@i0@)"),
                                      ("eq", "m.load(@i1@)")])]
    b.scen += [("overwrite", [("do", f"m.save(@i0@, {p1})"), ("do", f"m.save(@a0@, {p2})"), ("eq", "m.load(@i0@)")]),
               ("sessions_independent", [("do", f"m.save(@i0@, {p1})"), ("do", f"m.save(@i1@, {p2})"),
                                         ("eq", "m.drop(@i0@)"), ("eq", "m.load(@i1@)"), ("eq", "m.load(@i0@)")])]
    if p["touch"]:
        b.funcs.append(f'''
def touch(session_id):
    """Store the session again to restart its ttl. False if there is no session."""
    sid = {cl}(session_id)
    data = {c.get("sid")}
    if data is None:
        return False
{c.put("sid", "data")}
    return True
''')
        b.scen.append(("touch", [("eq", "m.touch(@i0@)"), ("do", f"m.save(@i0@, {p1})"), ("eq", "m.touch(@a0@)"),
                                 ("eq", "m.load(@i0@)")]))
    if p["user_of"]:
        b.funcs.append('''
def user_of(session_id, default=None):
    """The user id kept in the session, or default when there is no session or no user."""
    data = load(session_id)
    if not data:
        return default
    return data.get("user", default)
''')
        b.scen.append(("user_of", [("do", f"m.save(@i0@, {p1})"), ("eq", "m.user_of(@a0@)"),
                                   ("eq", "m.user_of(@i1@, -1)")]))
    if p["active"]:
        b.funcs.append(f'''
def active():
    """Ids of every stored session, sorted."""
    ids = []
{c.loop("sid", "_", ["ids.append(sid)"])}
    return ids
''')
        b.scen.append(("active_across_pages", [("do", "for i in range(70):\n    m.save(@loop@, {'user': i + 1})"),
                                               ("eq", "len(m.active())"), ("eq", "m.active()[:3]")]))
    b.write = f"m.save(@i0@, {p2})"
    return b


def _ratelimit(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    b.consts += [f"LIMITS = {p['limits']!r}  # actions per window", f'DEFAULT_PLAN = "{next(iter(p["limits"]))}"']
    b.helpers.append('''
def _limit_for(plan):
    """How many actions the plan allows; unknown plans raise ValueError."""
    try:
        return LIMITS[plan]
    except KeyError:
        raise ValueError(f"unknown plan: {plan!r}") from None
''')
    b.funcs.append(f'''
def hit(user, plan=DEFAULT_PLAN, cost=1):
    """Count `cost` actions for the user. True while the user is within the plan's limit."""
    limit = _limit_for(plan)
    if isinstance(cost, bool) or not isinstance(cost, int) or cost < 1:
        raise ValueError(f"bad cost: {{cost!r}}")
    uid = {cl}(user)
    used = {c.incr("uid", "cost")}
    return used <= limit
''')
    b.funcs.append(f'''
def reset(user):
    """Forget the user's count. True if there was one."""
    uid = {cl}(user)
    return {c.delete("uid")}
''')
    plans = list(p["limits"].items())
    (p0, l0), (p1, l1) = plans[0], plans[1]
    b.scen += [("limit", [("eq", f"[m.hit(@i0@) for _ in range({l0 + 1})]")]),
               ("plans", [("eq", f"[m.hit(@i1@, {p1!r}) for _ in range({l1 + 1})][-2:]"),
                          ("raises", "m.hit(@i1@, 'gold')"), ("eq", "m.hit(@a0@)")]),
               ("reset", [("eq", "m.reset(@i0@)"), ("do", "m.hit(@i0@)"), ("eq", "m.reset(@a0@)"),
                          ("eq", f"[m.hit(@i0@) for _ in range({l0})][-1]")]),
               ("cost", [("eq", f"m.hit(@i0@, cost={l0})"), ("eq", "m.hit(@a0@)"),
                         ("raises", "m.hit(@i0@, cost=0)"), ("raises", "m.hit(@bad@)"), ("eq", "m.reset(@i0@)")])]
    b.scen += [("users_independent", [("do", f"for _ in range({l0}):\n    m.hit(@i0@)"), ("eq", "m.hit(@i0@)"),
                                      ("eq", "m.hit(@i1@)"), ("eq", "m.hit(@i2@)")]),
               ("cost_counts_toward_limit", [("eq", f"m.hit(@i0@, cost={l0 - 1})"), ("eq", "m.hit(@i0@)"),
                                             ("eq", "m.hit(@a0@)")])]
    if p["remaining"]:
        b.funcs.append(f'''
def remaining(user, plan=DEFAULT_PLAN):
    """Actions the user has left under the plan."""
    uid = {cl}(user)
    used = {c.get("uid", "0")}
    return max(0, _limit_for(plan) - used)
''')
        b.scen.append(("remaining", [("eq", "m.remaining(@i0@)"), ("do", "m.hit(@i0@, cost=2)"),
                                     ("eq", "m.remaining(@a0@)"), ("eq", f"m.remaining(@i0@, {p1!r})")]))
    if p["status"]:
        b.funcs.append(f'''
def status(user, plan=DEFAULT_PLAN):
    """A one-line summary such as 'ann: 3/5 used'."""
    uid = {cl}(user)
    used = {c.get("uid", "0")}
    return f"{{uid}}: {{used}}/{{_limit_for(plan)}} used"
''')
        b.scen.append(("status", [("eq", "m.status(@i0@)"), ("do", "m.hit(@i0@)"), ("eq", f"m.status(@a0@, {p1!r})")]))
    if p["usage"]:
        b.funcs.append(f'''
def usage():
    """{{user: count}} for every counted user, in user order."""
    counts = {{}}
{c.loop("uid", "used", ["counts[uid] = used"])}
    return counts
''')
        b.scen.append(("usage_across_pages", [("do", "for i in range(60):\n    m.hit(@loop@, cost=i % 4 + 1)"),
                                              ("eq", "len(m.usage())"), ("eq", "sum(m.usage().values())")]))
    b.counter = "m.hit(@i0@, cost=2)"
    return b


def _stock(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    b.consts.append(f"MAX_BATCH = {p['max_batch']}  # largest single movement")
    b.helpers.append('''
def _quantity(qty):
    """Quantities are whole numbers from 1 to MAX_BATCH."""
    if isinstance(qty, bool) or not isinstance(qty, int):
        raise TypeError(f"quantity must be an int, not {type(qty).__name__}")
    if not 1 <= qty <= MAX_BATCH:
        raise ValueError(f"quantity out of range: {qty}")
    return qty
''')
    if p["incr_restock"]:
        b.funcs.append(f'''
def restock(item, qty):
    """Add qty units of item. Returns the new level."""
    name = {cl}(item)
    return {c.incr("name", "_quantity(qty)")}
''')
    else:
        b.funcs.append(f'''
def restock(item, qty):
    """Add qty units of item. Returns the new level."""
    name = {cl}(item)
    level = {c.get("name", "0")} + _quantity(qty)
{c.put("name", "level")}
    return level
''')
    b.funcs.append(f'''
def take(item, qty):
    """Remove qty units of item. Raises ValueError, changing nothing, when fewer are left."""
    name = {cl}(item)
    qty = _quantity(qty)
    level = {c.get("name", "0")}
    if level < qty:
        raise ValueError(f"only {{level}} of {{name}} left")
{c.put("name", "level - qty")}
    return level - qty
''')
    b.funcs.append(f'''
def total():
    """Units across all items."""
    count = 0
{c.loop("_", "qty", ["count += qty"])}
    return count
''')
    b.funcs.append(f'''
def items():
    """Names of the stocked items, sorted."""
    names = []
{c.loop("name", "_", ["names.append(name)"])}
    return names
''')
    b.scen += [("restock_and_take", [("eq", "m.restock(@i0@, 3)"), ("eq", "m.restock(@a0@, 4)"),
                                     ("eq", "m.take(@i0@, 5)"), ("raises", "m.take(@i0@, 10)"), ("eq", "m.total()"),
                                     ("eq", "m.items()")]),
               ("total_across_pages", [("do", "for i in range(130):\n    m.restock(@loop@, i % 9 + 1)"),
                                       ("eq", "m.total()"), ("eq", "len(m.items())"), ("eq", "m.items()[:3]"),
                                       ("eq", "m.items() == sorted(m.items())")]),
               ("bad_quantities", [("eq", "m.restock(@i1@, 2)"), ("raises", "m.restock(@i1@, 0)"),
                                   ("raises", f"m.restock(@i1@, {p['max_batch'] + 1})"),
                                   ("raises", "m.restock(@i1@, '3')"), ("raises", "m.restock(@bad@, 1)"),
                                   ("eq", "m.total()")])]
    b.scen += [("take_to_zero", [("eq", "m.restock(@i0@, 5)"), ("eq", "m.take(@a0@, 5)"), ("eq", "m.items()"),
                                 ("eq", "m.total()"), ("raises", "m.take(@i1@, 1)")]),
               ("items_independent", [("do", "m.restock(@i0@, 2)"), ("do", "m.restock(@i1@, 9)"),
                                      ("do", "m.take(@i1@, 4)"), ("eq", "m.total()"), ("eq", "m.items()")])]
    if p["low"]:
        b.consts.append(f"LOW_THRESHOLD = {p['threshold']}")
        b.funcs.append(f'''
def low_stock(threshold=LOW_THRESHOLD):
    """Items with fewer than threshold units, sorted."""
    names = []
{c.loop("name", "qty", ["if qty < threshold:", "    names.append(name)"])}
    return names
''')
        b.scen.append(("low_stock", [("do", "for i in range(120):\n    m.restock(@loop@, i % 50 + 1)"),
                                     ("eq", "len(m.low_stock())"), ("eq", "m.low_stock(3)[:4]")]))
    if p["level"]:
        b.funcs.append(f'''
def level(item):
    """Units of item in stock (0 if it was never stocked)."""
    name = {cl}(item)
    return {c.get("name", "0")}
''')
        b.scen.append(("level", [("eq", "m.level(@i0@)"), ("do", "m.restock(@i0@, 6)"), ("eq", "m.level(@a0@)")]))
    if p["report"]:
        b.funcs.append(f'''
def report(limit=10):
    """The `limit` largest stock levels as aligned 'name  qty' lines, largest first."""
    rows = []
{c.loop("name", "qty", ["rows.append((qty, name))"])}
    rows.sort(key=lambda row: (-row[0], row[1]))
    width = max((len(name) for _, name in rows[:limit]), default=0)
    return [f"{{name.ljust(width)}}  {{qty:>6}}" for qty, name in rows[:limit]]
''')
        b.scen.append(("report", [("do", "for i in range(65):\n    m.restock(@loop@, i % 13 + 1)"),
                                  ("eq", "m.report(4)")]))
    return b


def _flags(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    d = p["default"]
    b.consts.append(f"DEFAULT = {d}  # a flag that was never set")
    b.helpers.append('''
_SWITCH = {"on": True, "yes": True, "true": True, "1": True, "off": False, "no": False, "false": False, "0": False}


def _switch(value):
    """A flag value: a bool, or one of on/off, yes/no, true/false, 1/0 in any case."""
    if isinstance(value, bool):
        return value
    try:
        return _SWITCH[str(value).strip().lower()]
    except KeyError:
        raise ValueError(f"not a switch value: {value!r}") from None
''')
    b.funcs.append(f'''
def enabled(flag):
    """Whether the flag is on (DEFAULT when it was never set)."""
    name = {cl}(flag)
    return bool({c.get("name", "DEFAULT")})
''')
    b.funcs.append(f'''
def set_flag(flag, on):
    """Set the flag from a bool or a word such as 'on' or 'off'. Returns the stored value."""
    name = {cl}(flag)
    value = _switch(on)
{c.put("name", "value")}
    return value
''')
    b.scen += [("default", [("eq", "m.enabled(@i0@)"), ("eq", "m.enabled(@i1@)")]),
               ("set_and_read", [("eq", f"m.set_flag(@i0@, {not d})"), ("eq", "m.enabled(@a0@)"),
                                 ("eq", f"m.set_flag(@a0@, {d})"), ("eq", "m.enabled(@i0@)")]),
               ("switch_words", [("eq", "m.set_flag(@i0@, 'Yes')"), ("eq", "m.enabled(@i0@)"),
                                 ("eq", "m.set_flag(@i0@, ' off ')"), ("eq", "m.enabled(@i0@)"),
                                 ("raises", "m.set_flag(@i0@, 'maybe')"), ("raises", "m.set_flag(@bad@, True)"),
                                 ("eq", "m.enabled(@i0@)")])]
    b.scen += [("flags_independent", [("eq", f"m.set_flag(@i1@, {not d})"), ("eq", "m.enabled(@i0@)"),
                                      ("eq", "m.enabled(@i1@)"), ("eq", "m.enabled(@i2@)")]),
               ("last_write_wins", [("do", "m.set_flag(@i0@, 'on')"), ("do", "m.set_flag(@a0@, 'no')"),
                                    ("do", "m.set_flag(@i0@, 1)"), ("eq", "m.enabled(@i0@)")])]
    if p["toggle"]:
        b.funcs.append('''
def toggle(flag):
    """Flip the flag; returns its new value."""
    now = not enabled(flag)
    set_flag(flag, now)
    return now
''')
        b.scen.append(("toggle", [("eq", "m.toggle(@i0@)"), ("eq", "m.toggle(@a0@)"), ("eq", "m.enabled(@i0@)")]))
    if p["clear"]:
        b.funcs.append(f'''
def clear_flag(flag):
    """Forget the flag so it falls back to DEFAULT. True if it was set."""
    name = {cl}(flag)
    return {c.delete("name")}
''')
        b.scen.append(("clear_flag", [("eq", "m.clear_flag(@i0@)"), ("do", f"m.set_flag(@i0@, {not d})"),
                                      ("eq", "m.clear_flag(@a0@)"), ("eq", "m.enabled(@i0@)")]))
    if p["snapshot"]:
        b.funcs.append(f'''
def snapshot():
    """{{flag: on}} for every flag that was set, in flag order."""
    state = {{}}
{c.loop("name", "value", ["state[name] = bool(value)"])}
    return state
''')
        b.scen.append(("snapshot_across_pages", [("do", "for i in range(70):\n    m.set_flag(@loop@, i % 3 == 0)"),
                                                 ("eq", "len(m.snapshot())"), ("eq", "sum(m.snapshot().values())")]))
    b.write = "m.set_flag(@i0@, True)" if p.get("ttl") is not None else None
    return b


def _audit(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    b.consts += [f"SENSITIVE = {tuple(p['sensitive'])!r}  # masked before storing", f"MAX_TEXT = {p['max_text']}"]
    b.helpers.append('''
def _redact(payload):
    """A copy of the payload that is safe to keep: sensitive fields masked, long strings cut to MAX_TEXT."""
    if not isinstance(payload, dict):
        raise TypeError("audit payload must be a dict")
    safe = {}
    for key, value in payload.items():
        if key.lower() in SENSITIVE:
            value = "***"
        elif isinstance(value, str) and len(value) > MAX_TEXT:
            value = value[:MAX_TEXT - 3] + "..."
        safe[key] = value
    return safe
''')
    b.funcs.append(f'''
def record(event_id, payload):
    """Store the event's payload with secrets masked. Returns the normalized event id."""
    eid = {cl}(event_id)
    safe = _redact(payload)
{c.put("eid", "safe")}
    return eid
''')
    b.funcs.append(f'''
def history():
    """Every stored payload, in event-id order."""
    out = []
{c.loop("_", "payload", ["out.append(payload)"])}
    return out
''')
    secret = p["sensitive"][0].capitalize()
    b.scen += [("history_in_order", [("eq", "m.record(@i1@, {'n': 2})"), ("eq", "m.record(@i0@, {'n': 1})"),
                                     ("eq", "m.history()")]),
               ("history_across_pages", [("do", "for i in range(75):\n    m.record(@loop@, {'n': i})"),
                                         ("eq", "len(m.history())"), ("eq", "m.history()[:2]"),
                                         ("eq", "m.history()[-1]")]),
               ("redacts", [("eq", f"m.record(@a0@, {{'user': 'ann', '{secret}': 'hunter2', 'note': 'x' * 200}})"),
                            ("eq", "m.history()")]),
               ("rejects_bad_input", [("do", "m.record(@i0@, {'n': 1})"), ("raises", "m.record(@bad@, {'n': 2})"),
                                      ("raises", "m.record(@i1@, ['n'])"), ("eq", "m.history()")])]
    b.scen += [("same_id_overwrites", [("do", "m.record(@i0@, {'n': 1})"), ("do", "m.record(@a0@, {'n': 2})"),
                                       ("eq", "m.history()")]),
               ("long_text_cut", [("eq", "m.record(@i0@, {'note': 'y' * 500, 'ok': 'short'})"),
                                  ("eq", "m.history()")])]
    if p["count"]:
        b.funcs.append(f'''
def count():
    """How many events are stored."""
    n = 0
{c.loop("_", "_payload", ["n += 1"])}
    return n
''')
        b.scen.append(("count", [("eq", "m.count()"), ("do", "for i in range(55):\n    m.record(@loop@, {'n': i})"),
                                 ("eq", "m.count()")]))
    if p["search"]:
        b.funcs.append(f'''
def search(text):
    """Ids of the events whose payload mentions text (case-insensitive), in id order."""
    needle = text.lower()
    found = []
{c.loop("eid", "payload", ["if needle in repr(payload).lower():", "    found.append(eid)"])}
    return found
''')
        b.scen.append(("search", [("do", "for i in range(60):\n    m.record(@loop@, {'n': i, 'tag': 'red' if i % 7 "
                                         "else 'Blue'})"), ("eq", "len(m.search('blue'))"),
                                  ("eq", "m.search('BLUE')[:2]")]))
    if p["latest"]:
        b.funcs.append('''
def latest(n=5):
    """The last n payloads in event-id order."""
    if n <= 0:
        return []
    return history()[-n:]
''')
        b.scen.append(("latest", [("do", "for i in range(12):\n    m.record(@loop@, {'n': i})"),
                                  ("eq", "m.latest(3)"), ("eq", "m.latest(0)")]))
    b.write = "m.record(@i0@, {'n': 1})"
    return b


def _purge(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    b.consts.append(f"MAX_VALUE_CHARS = {p['max_chars']}  # scratch values are small")
    b.helpers.append('''
def _fits(value):
    """Scratch values must be small: their repr may not exceed MAX_VALUE_CHARS characters."""
    size = len(repr(value))
    if size > MAX_VALUE_CHARS:
        raise ValueError(f"value too large for scratch space ({size} > {MAX_VALUE_CHARS} chars)")
    return value
''')
    b.funcs.append(f'''
def stash(name, value):
    """Keep value under name until the next purge. Returns the normalized name."""
    slot = {cl}(name)
{c.put("slot", "_fits(value)")}
    return slot
''')
    b.funcs.append(f'''
def purge():
    """Delete every scratch entry. Returns how many were deleted."""
    doomed = []
{c.loop("slot", "_", ["doomed.append(slot)"])}
    removed = 0
    for slot in doomed:
        if {c.delete("slot")}:
            removed += 1
    return removed
''')
    b.scen += [("purge_everything", [("do", "for i in range(90):\n    m.stash(@loop@, i)"), ("eq", "m.purge()"),
                                     ("eq", "m.purge()")]),
               ("purge_empty", [("eq", "m.purge()")]),
               ("stash_rules", [("eq", "m.stash(@a0@, [1, 2])"), ("raises", "m.stash(@i1@, 'x' * 1000)"),
                                ("raises", "m.stash(@bad@, 1)"), ("eq", "m.purge()")])]
    b.scen += [("purge_after_restash", [("do", "m.stash(@i0@, 1)"), ("eq", "m.purge()"), ("do", "m.stash(@a0@, 2)"),
                                        ("do", "m.stash(@i1@, 3)"), ("eq", "m.purge()")]),
               ("same_name_overwrites", [("do", "m.stash(@i0@, 'a')"), ("do", "m.stash(@a0@, 'b')"),
                                         ("eq", "m.purge()")])]
    if p["matching"]:
        b.funcs.append(f'''
def purge_matching(fragment):
    """Delete the entries whose name contains fragment. Returns how many were deleted."""
    doomed = []
{c.loop("slot", "_", ["if fragment in slot:", "    doomed.append(slot)"])}
    removed = 0
    for slot in doomed:
        if {c.delete("slot")}:
            removed += 1
    return removed
''')
        b.scen.append(("purge_matching", [("do", "for i in range(60):\n    m.stash(@loop@, i)"),
                                          ("eq", "m.purge_matching('1')"), ("eq", "m.purge()")]))
    if p["size"]:
        b.funcs.append(f'''
def size():
    """How many scratch entries there are."""
    n = 0
{c.loop("_", "_value", ["n += 1"])}
    return n
''')
        b.scen.append(("size", [("eq", "m.size()"), ("do", "for i in range(57):\n    m.stash(@loop@, i)"),
                                ("eq", "m.size()")]))
    if p["peek"]:
        b.funcs.append(f'''
def peek(name, default=None):
    """The value stashed under name, or default."""
    slot = {cl}(name)
    return {c.get("slot", "default")}
''')
        b.scen.append(("peek", [("eq", "m.peek(@i0@, 'none')"), ("do", "m.stash(@i0@, {'a': 1})"),
                                ("eq", "m.peek(@a0@)")]))
    b.write = "m.stash(@i0@, 1)" if p.get("ttl") is not None else None
    return b


def _metrics(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    b.consts.append(f"MAX_STEP = {p['max_step']}  # largest single increment")
    b.funcs.append(f'''
def bump(metric, by=1):
    """Add `by` (1 to MAX_STEP) to the counter. Returns the new value."""
    if isinstance(by, bool) or not isinstance(by, int) or not 1 <= by <= MAX_STEP:
        raise ValueError(f"bad step: {{by!r}}")
    name = {cl}(metric)
    return {c.incr("name", "by")}
''')
    b.funcs.append(f'''
def read(metric):
    """The counter's value (0 if it was never bumped)."""
    name = {cl}(metric)
    return {c.get("name", "0")}
''')
    b.scen += [("bump_and_read", [("eq", "m.read(@i0@)"), ("eq", "[m.bump(@i0@), m.bump(@a0@, 5)]"),
                                  ("eq", "m.read(@i0@)"), ("eq", "m.read(@i1@)")]),
               ("bad_steps", [("eq", "m.bump(@i0@)"), ("raises", "m.bump(@i0@, 0)"),
                              ("raises", f"m.bump(@i0@, {p['max_step'] + 1})"), ("raises", "m.bump(@i0@, True)"),
                              ("raises", "m.bump(@bad@)"), ("eq", "m.read(@a0@)")])]
    b.scen += [("counters_independent", [("do", "m.bump(@i0@, 4)"), ("do", "m.bump(@i1@)"), ("eq", "m.read(@i0@)"),
                                         ("eq", "m.read(@i1@)"), ("eq", "m.read(@i2@)")]),
               ("largest_step", [("eq", f"m.bump(@i0@, {p['max_step']})"), ("eq", "m.bump(@a0@)")])]
    if p["reset"]:
        b.funcs.append(f'''
def reset(metric):
    """Set the counter back to 0. True if it had a value."""
    name = {cl}(metric)
    return {c.delete("name")}
''')
        b.scen.append(("reset", [("eq", "m.reset(@i0@)"), ("do", "m.bump(@i0@, 3)"), ("eq", "m.reset(@a0@)"),
                                 ("eq", "m.read(@i0@)")]))
    if p["snapshot"]:
        b.funcs.append(f'''
def snapshot():
    """{{metric: value}} for every counter, in name order."""
    values = {{}}
{c.loop("name", "value", ["values[name] = value"])}
    return values
''')
        b.scen.append(("snapshot_across_pages", [("do", "for i in range(66):\n    m.bump(@loop@, i % 5 + 1)"),
                                                 ("eq", "len(m.snapshot())"), ("eq", "sum(m.snapshot().values())")]))
    if p["ratio"]:
        b.funcs.append('''
def ratio(part, whole, digits=1):
    """read(part) as a percentage of read(whole); 'n/a' when whole is 0."""
    top, bottom = read(part), read(whole)
    if bottom == 0:
        return "n/a"
    return f"{100 * top / bottom:.{digits}f}%"
''')
        b.scen.append(("ratio", [("eq", "m.ratio(@i0@, @i1@)"), ("do", "m.bump(@i0@, 3)"),
                                 ("do", "m.bump(@i1@, 8)"), ("eq", "m.ratio(@a0@, @i1@)")]))
    b.counter = "m.bump(@i0@, 2)"
    return b


def _leaderboard(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    b.consts += [f"MAX_POINTS = {p['max_points']}  # higher scores count as MAX_POINTS", f"TOP_N = {p['n']}"]
    b.helpers.append('''
def _points(points):
    """Points are whole numbers; anything above MAX_POINTS counts as MAX_POINTS."""
    if isinstance(points, bool) or not isinstance(points, int):
        raise TypeError("points must be an int")
    if points < 0:
        raise ValueError(f"negative points: {points}")
    return min(points, MAX_POINTS)
''')
    b.funcs.append(f'''
def submit(player, points):
    """Keep the player's best score. True if this is a new best."""
    name = {cl}(player)
    points = _points(points)
    best = {c.get("name", "-1")}
    if points <= best:
        return False
{c.put("name", "points")}
    return True
''')
    b.funcs.append(f'''
def top(n=TOP_N):
    """The n best (player, points), highest first, ties by name."""
    scores = []
{c.loop("name", "points", ["scores.append((name, points))"])}
    scores.sort(key=lambda row: (-row[1], row[0]))
    return scores[:n]
''')
    b.scen += [("keeps_best", [("eq", "m.submit(@i0@, 5)"), ("eq", "m.submit(@a0@, 3)"), ("eq", "m.submit(@i1@, 5)"),
                               ("eq", "m.top(2)")]),
               ("top_across_pages", [("do", "for i in range(80):\n    m.submit(@loop@, (i * 37) % 101 + 1)"),
                                     ("eq", "m.top()"), ("eq", "len(m.top(200))")]),
               ("caps_and_rejects", [("eq", f"m.submit(@i0@, {p['max_points'] + 50})"), ("eq", "m.top(1)"),
                                     ("raises", "m.submit(@i0@, -1)"), ("raises", "m.submit(@i1@, '7')"),
                                     ("raises", "m.submit(@bad@, 1)"), ("eq", "m.top()")])]
    b.scen += [("ties_by_name", [("do", "m.submit(@i1@, 7)"), ("do", "m.submit(@i0@, 7)"), ("do", "m.submit(@i2@, 7)"),
                                 ("eq", "m.top(3)")]),
               ("lower_score_ignored", [("eq", "m.submit(@i0@, 9)"), ("eq", "m.submit(@a0@, 9)"),
                                        ("eq", "m.submit(@i0@, 2)"), ("eq", "m.top()")])]
    if p["rank"]:
        b.funcs.append(f'''
def rank(player):
    """1-based position of the player, or None."""
    name = {cl}(player)
    order = [who for who, _ in top(10 ** 9)]
    return order.index(name) + 1 if name in order else None
''')
        b.scen.append(("rank", [("do", "for i in range(70):\n    m.submit(@loop@, i + 1)"),
                                ("eq", "[m.rank(@loop0@), m.rank(@loop69@), m.rank(@i0@)]")]))
    if p["score_of"]:
        b.funcs.append(f'''
def score_of(player):
    """The player's best score, or None."""
    name = {cl}(player)
    return {c.get("name")}
''')
        b.scen.append(("score_of", [("eq", "m.score_of(@i0@)"), ("do", "m.submit(@a0@, 9)"),
                                    ("eq", "m.score_of(@i0@)")]))
    if p["table"]:
        b.funcs.append('''
def table(n=3):
    """The top n as display lines: '1. ann  42'."""
    rows = top(n)
    width = max((len(name) for name, _ in rows), default=0)
    return [f"{i}. {name.ljust(width)}  {points}" for i, (name, points) in enumerate(rows, 1)]
''')
        b.scen.append(("table", [("do", "m.submit(@i0@, 4)"), ("do", "m.submit(@i1@, 11)"), ("eq", "m.table()")]))
    b.write = "m.submit(@i0@, 5)" if p.get("ttl") is not None else None
    return b


def _profiles(m: Module, c: Ops, cl: str) -> Built:
    p, b = m.p, Built()
    defaults = p["defaults"]
    upper = tuple(f for f in defaults if f in ("currency", "region"))
    b.consts += [f"DEFAULTS = {defaults!r}", f"EXTRA_FIELDS = {tuple(p['extra'])!r}",
                 f"UPPER_FIELDS = {upper!r}  # stored as upper-case codes"]
    b.helpers.append('''
def _changes(changes):
    """Validated profile changes: known fields only; strings trimmed and codes upper-cased."""
    unknown = sorted(set(changes) - set(DEFAULTS) - set(EXTRA_FIELDS))
    if unknown:
        raise ValueError(f"unknown profile fields: {', '.join(unknown)}")
    clean = {}
    for name, value in changes.items():
        if isinstance(value, str):
            value = value.strip()
            if name in UPPER_FIELDS:
                value = value.upper()
        clean[name] = value
    return clean
''')
    b.funcs.append(f'''
def get_profile(uid):
    """The stored profile merged over DEFAULTS."""
    pid = {cl}(uid)
    stored = {c.get("pid", "{}")}
    return {{**DEFAULTS, **stored}}
''')
    b.funcs.append(f'''
def update_profile(uid, **changes):
    """Apply the changes and return the merged profile."""
    pid = {cl}(uid)
    current = dict({c.get("pid", "{}")})
    current.update(_changes(changes))
{c.put("pid", "current")}
    return get_profile(pid)
''')
    k0 = next(iter(defaults))
    extra0 = p["extra"][0]
    b.scen += [("defaults", [("eq", "m.get_profile(@i0@)")]),
               ("update_merges", [("eq", f"m.update_profile(@i0@, {k0}='changed')"),
                                  ("eq", f"m.update_profile(@a0@, {extra0}='  Ann Lee ')"),
                                  ("eq", "m.get_profile(@i1@)")]),
               ("rejects_unknown_fields", [("do", f"m.update_profile(@i0@, {extra0}='x')"),
                                           ("raises", "m.update_profile(@i0@, shoe_size=42)"),
                                           ("raises", f"m.update_profile(@bad@, {extra0}='y')"),
                                           ("eq", "m.get_profile(@i0@)")])]
    b.scen += [("users_independent", [("do", f"m.update_profile(@i0@, {k0}='mine')"), ("eq", "m.get_profile(@i1@)"),
                                      ("eq", f"m.get_profile(@a0@)['{k0}']")]),
               ("later_update_wins", [("do", f"m.update_profile(@i0@, {extra0}='a')"),
                                      ("eq", f"m.update_profile(@i0@, {extra0}='b', {k0}='z')")])]
    if upper:
        b.scen.append(("codes_upper_cased", [("eq", f"m.update_profile(@i0@, {upper[0]}=' ab ')"),
                                             ("eq", "m.get_profile(@a0@)")]))
    if p["clear"]:
        b.funcs.append(f'''
def clear_profile(uid):
    """Drop the stored overrides. True if there were any."""
    pid = {cl}(uid)
    return {c.delete("pid")}
''')
        b.scen.append(("clear", [("do", f"m.update_profile(@i0@, {k0}='x')"), ("eq", "m.clear_profile(@a0@)"),
                                 ("eq", "m.clear_profile(@i0@)"), ("eq", "m.get_profile(@i0@)")]))
    if p["display"]:
        b.consts.append(f'ANONYMOUS = "{p["anon"]}"')
        b.funcs.append(f'''
def display_name(uid):
    """The profile's {extra0} if it has one, else a placeholder built from the id."""
    value = get_profile(uid).get("{extra0}")
    if value:
        return str(value)
    return f"{{ANONYMOUS}} {{{cl}(uid)}}"
''')
        b.scen.append(("display_name", [("eq", "m.display_name(@i0@)"),
                                        ("do", f"m.update_profile(@i0@, {extra0}=' Grace ')"),
                                        ("eq", "m.display_name(@a0@)")]))
    b.write = f"m.update_profile(@i0@, {extra0}='x')"
    return b


BUILD = {"sessions": _sessions, "ratelimit": _ratelimit, "stock": _stock, "flags": _flags, "audit": _audit,
         "purge": _purge, "metrics": _metrics, "leaderboard": _leaderboard, "profiles": _profiles}


# --- rendering a module -----------------------------------------------------------------------------------------------
def _imports(std: set[str], third: list[str]) -> str:
    plain = sorted(x for x in std if "." not in x)
    froms: dict[str, set] = defaultdict(set)
    for x in std:
        if "." in x:
            mod, name = x.split(".", 1)
            froms[mod].add(name)
    lines = [f"import {x}" for x in plain] + [f"from {mod} import {', '.join(sorted(names))}"
                                              for mod, names in sorted(froms.items())]
    return ("\n".join(lines) + "\n\n" if lines else "") + "\n".join(third)


def render_module(m: Module, legacy: bool, facts: dict | None = None) -> tuple[str, Built, Ops]:
    """The module's source: legacy (the starting workspace) or migrated with `facts` (the reference)."""
    facts = facts or ALL_FACTS
    c = Ops(m, legacy, facts)
    lg = m.logic
    cleaner = render(CLEANER_SRC[lg["clean"]["kind"]], fn=lg["clean"]["fn"], noun=NOUNS[m.arch],
                     Noun=NOUNS[m.arch].capitalize(), **lg["clean"]["params"])
    b = BUILD[m.arch](m, c, lg["clean"]["fn"])
    pure = [render(PURE[kind][2], fn=fn, **params) for kind, fn, params in lg["pure"]]
    std = set(lg["std"])
    if lg["clean"]["kind"] in CLEANER_RE:
        std.add("re")
    for kind, _, _ in lg["pure"]:
        std |= PURE[kind][1]
    if c.needs_timedelta():
        std.add("datetime.timedelta")
    ent = m.entity
    doc = render(lg["doc"], Ent=ent.capitalize(), ent=ent)
    notes = "\n".join(render(n, team=lg["team"]) for n in lg["notes"])
    api = "\n".join(f"    {name}({args}): {summary}" for name, args, summary in
                     re.findall(r'^def ([a-z]\w*)\((.*?)\):\n    """(.*?)(?:"""|$)', "".join(b.funcs), re.M))
    head = f'"""{doc}\n\n{notes}\n\n{lg["api_title"]}\n{api}\n"""\n\n{_imports(std, c.import_lines())}\n'
    consts = c.consts() + b.consts
    body = [head, "\n".join(consts) + "\n"]
    chunks = c.layer_chunks() + [cleaner] + b.helpers
    storage = b.funcs
    if lg["pure_first"]:
        chunks += pure + storage
    else:
        chunks += storage + pure
    text = body[0] + body[1] + "".join("\n" + ch for ch in chunks)
    return text.rstrip("\n") + "\n", b, c


# --- hidden tests: recorded from the legacy module ---------------------------------------------------------------------
TEST_HEAD = '''import importlib
from datetime import timedelta

import pytest
from storex import store


@pytest.fixture(autouse=True)
def _fresh_store():
    store.clear()
    yield
    store.clear()


def _mod():
    return importlib.import_module("acme.@@mod@@")


def test_@@rid@@_registry():
    from acme import registry
    assert registry.BACKENDS["@@mod@@"] == "storex"


def test_@@rid@@_changelog():
    from pathlib import Path

    import acme
    text = (Path(acme.__file__).resolve().parents[1] / "CHANGELOG.md").read_text()
    unreleased = text.split("## Unreleased", 1)[1].split("\\n## ", 1)[0]
    assert "- Migrated acme.@@mod@@ to storex." in unreleased
'''


class LegacyRuntime:
    """legacy.storage and acme modules run in-process, to record the behaviour the hidden tests pin."""

    def __init__(self):
        self.storage = types.ModuleType("legacy.storage")
        exec(compile(LEGACY_STORAGE, "legacy/storage.py", "exec"), self.storage.__dict__)
        self.pkg = types.ModuleType("legacy")
        self.pkg.__path__ = []
        self.pkg.storage = self.storage

    def load(self, name: str, src: str) -> types.ModuleType:
        self.storage._DATA.clear()
        saved = {k: sys.modules.get(k) for k in ("legacy", "legacy.storage")}
        sys.modules.update({"legacy": self.pkg, "legacy.storage": self.storage})
        try:
            mod = types.ModuleType(f"acme.{name}")
            exec(compile(src, f"acme/{name}.py", "exec"), mod.__dict__)
        finally:
            for k, v in saved.items():
                if v is None:
                    sys.modules.pop(k, None)
                else:
                    sys.modules[k] = v
        return mod


def _builtin_exc(e: BaseException) -> str:
    return next(k.__name__ for k in type(e).__mro__ if getattr(builtins, k.__name__, None) is k)


PLACEHOLDER = re.compile(r"@(i0|i1|i2|a0|bad|loop|loop0|loop69)@")


def _subst(code: str, subs: dict) -> str:
    return PLACEHOLDER.sub(lambda mt: subs[mt.group(1)], code)


def _subs(m: Module) -> dict:
    s = _cleaner_samples(m.logic["clean"]["kind"], m.logic["clean"]["params"])
    loop = s["loop"]
    # the loop expression is the generator's own code (never input), evaluated for two fixed indices
    return {"i0": repr(s["i"][0]), "i1": repr(s["i"][1]), "i2": repr(s["i"][2]), "a0": repr(s["a0"]),
            "bad": repr(s["bad"]), "loop": loop, "loop0": repr(eval(loop, {"i": 0})),
            "loop69": repr(eval(loop, {"i": 69}))}


def _run_steps(rt: LegacyRuntime, m: Module, src: str, steps: list, subs: dict) -> tuple[list[str], dict]:
    """Run a scenario against the legacy module and render it as test lines with the observed values pinned.
    Steps are the generator's own code (exec/eval never see outside input)."""
    mod = rt.load(m.name, src)
    ns = {"m": mod}
    lines = ["    m = _mod()"]
    for kind, code in steps:
        code = _subst(code, subs)
        if kind == "do":
            exec(code, ns)
            lines += ["    " + line for line in code.splitlines()]
        elif kind == "eq":
            value = eval(code, ns)
            text = repr(value)
            assert eval(text) == value, (m.name, code, text)
            compared = any(op in code for op in ("==", "!=", "<", ">", " is ", " in ", " not "))
            lines.append(f"    assert ({code}) == {text}" if compared else f"    assert {code} == {text}")
        else:
            try:
                exec(code, ns)
            except Exception as e:
                lines += [f"    with pytest.raises({_builtin_exc(e)}):", f"        {code}"]
            else:
                raise AssertionError(f"{m.name}: `{code}` did not raise")
    return lines, ns


def hidden_tests(m: Module, rid: str, rt: LegacyRuntime) -> str:
    src, b, c = render_module(m, legacy=True)
    subs = _subs(m)
    out = render(TEST_HEAD, mod=m.name, rid=rid)
    for label, steps in b.scen:
        lines, _ = _run_steps(rt, m, src, steps, subs)
        out += f"\n\ndef test_{rid}_{label}():\n" + "\n".join(lines) + "\n"
    if b.write:
        lines, _ = _run_steps(rt, m, src, [("do", b.write)], subs)
        (key, (_, ttl)), = rt.storage._DATA.items()
        if m.arch == "audit":
            name, check = f"F1_{m.name}_never_expires", f"store.ttl_of({key!r}) is None"
        elif ttl > 3600:
            name, check = f"F3_{m.name}_ttl_capped", f"store.ttl_of({key!r}) == timedelta(hours=1)"
        else:
            name, check = f"{rid}_ttl", f"store.ttl_of({key!r}) == timedelta(seconds={ttl})"
        out += f"\n\ndef test_{name}():\n" + "\n".join(lines) + f"\n    assert {check}\n"
    if b.counter:
        lines, _ = _run_steps(rt, m, src, [("do", b.counter)], subs)
        (key, (value, _)), = rt.storage._DATA.items()
        assert key.startswith("count/"), key
        new = "counter/" + key[len("count/"):]
        out += (f"\n\ndef test_F2_{m.name}_counter_namespace():\n" + "\n".join(lines)
                + f"\n    assert store.fetch({new!r}).value == {value!r}\n"
                f"    with pytest.raises(KeyError):\n        store.fetch({key!r})\n")
    if m.logic["pure_test"] is not None:
        kind, fn, params = m.logic["pure"][m.logic["pure_test"]]
        steps = [("eq", render(case, fn=f"m.{fn}")) for case in PURE[kind][4]]
        lines, _ = _run_steps(rt, m, src, steps, subs)
        out += f"\n\ndef test_{rid}_{fn}():\n" + "\n".join(lines) + "\n"
    return out


# --- choosing the modules ---------------------------------------------------------------------------------------------
def _params(rng: random.Random, arch: str) -> dict:
    flip = lambda: rng.random() < 0.5  # noqa: E731
    p: dict = {"ttl": rng.choice(TTLS) if rng.random() < TTL_CHANCE.get(arch, 0) else None}
    if arch == "sessions":
        p.update(check=rng.randrange(3), schema=rng.randint(2, 5), max_fields=rng.choice([3, 4, 6]),
                 roles=rng.sample(["member", "viewer", "editor", "owner", "guest"], 3), touch=flip(), user_of=flip(),
                 active=flip())
    elif arch == "ratelimit":
        plans = rng.sample(["free", "basic", "team", "pro", "trial"], 3)
        limits = sorted(rng.sample([3, 4, 5, 6, 8, 10, 12, 20, 30], 3))
        p.update(limits=dict(zip(plans, limits)), remaining=flip(), status=flip(), usage=flip())
    elif arch == "stock":
        p.update(max_batch=rng.choice([50, 100, 250, 500]), threshold=rng.choice([5, 10, 15, 25, 40]),
                 incr_restock=flip(), low=flip(), level=flip(), report=flip())
    elif arch == "flags":
        p.update(default=rng.choice([True, False]), toggle=flip(), clear=flip(), snapshot=flip())
    elif arch == "audit":
        p.update(sensitive=rng.sample(["password", "token", "card", "secret", "pin", "iban"], 3),
                 max_text=rng.choice([40, 60, 80, 120]), count=flip(), search=flip(), latest=flip())
    elif arch == "purge":
        p.update(max_chars=rng.choice([100, 200, 400]), matching=flip(), size=flip(), peek=flip())
    elif arch == "metrics":
        p.update(max_step=rng.choice([100, 1000, 5000]), reset=flip(), snapshot=flip(), ratio=flip())
    elif arch == "leaderboard":
        p.update(max_points=rng.choice([999, 5000, 10000]), n=rng.choice([3, 5, 10, 20]), rank=flip(),
                 score_of=flip(), table=flip())
    else:
        keys = rng.sample(["theme", "locale", "currency", "plan", "region", "timezone", "digest"], 3)
        p.update(defaults={k: rng.choice(["a", "b", "on", "off", "en", "eu", "us"]) for k in keys},
                 extra=rng.sample(["name", "email", "phone", "nickname"], 2), clear=flip(), display=flip(),
                 anon=rng.choice(["user", "member", "guest"]))
    return p


def _variant(rng: random.Random, arch: str, p: dict) -> dict:
    access = rng.choices(list(ACCESS), weights=list(ACCESS.values()))[0]
    v = {"access": access, "fmt": {op: rng.choice(opts) for op, opts in FORMATS.items()},
         "key": rng.choice(["plus", "fstr", "helper"]), "scan": rng.choice(["all", "offset", "cursor", "rows"]),
         "rows_inner": rng.choice(["all", "offset", "cursor"]), "batch": rng.choice([20, 25, 40, 100]),
         "ttl": None}
    if p.get("ttl") is not None:
        styles = ["seconds", "computed", "minutes", "timedelta", "timedelta"] + (["hours"] if p["ttl"] % 3600 == 0
                                                                                 else [])
        v["ttl"] = rng.choice(styles)
    if access in ("alias", "modalias"):
        v["alias"] = rng.choice(["kv", "db", "backend", "kvstore", "_kv", "keystore"])
    elif access == "injected":
        v["alias"] = rng.choice(["_client", "_backend", "_kv", "CLIENT", "_db"])
        v["inject_note"] = rng.choice(["the key-value client; tests swap in a fake", "shared client, replaced in tests",
                                       "module-wide handle on the store"])
    elif access == "repo":
        v["alias"] = rng.choice([None, "kv", "backend"])
        v["cls"] = rng.choice(["_Bucket", "_Records", "_Table", "_Namespace"])
        v["inst"] = rng.choice(["_RECORDS", "_TABLE", "_BUCKET", "_DB"])
    elif access == "fromimport":
        style = rng.choice(["plain", "prefixed", "verbs"])
        verbs = {"get": "read_key", "put": "write_key", "scan": "scan_keys", "delete": "delete_key", "incr": "incr_key"}
        v["fnames"] = {fn: fn if style == "plain" else f"kv_{fn}" if style == "prefixed" else verbs[fn]
                       for fn in ("delete", "get", "incr", "put", "scan")}
    return v


def _shape_key(arch: str, v: dict, p: dict) -> tuple:
    fmts = tuple(v["fmt"][op] for op in ARCH_OPS[arch])
    opts = tuple(sorted(k for k, x in p.items() if x is True))
    return (SHAPE_CLASS[v["access"]], fmts, v["key"], v["ttl"], v["scan"], v["rows_inner"], opts)


def _logic(rng: random.Random, arch: str) -> dict:
    kind = rng.choice(CLEANERS[arch])
    params = {"lower": lambda: {"max": rng.choice([31, 47, 63])}, "numeric": lambda: {"width": rng.choice([6, 8, 10])},
              "code": lambda: {"cp": rng.choice(["BIL", "ORD", "SES", "EVT", "ITM", "REF", "ACC"]),
                               "maxd": rng.choice([6, 8])},
              "slug": lambda: {"max": rng.choice([40, 48, 64])}, "email": dict, "dotted": dict}[kind]()
    fn = rng.choice(["_clean_id", "_normalize_id", "_canonical", "_key_part", "_checked_id"])
    pure_kinds = rng.sample(sorted(PURE), rng.randint(2, 4))
    pure = []
    for k in pure_kinds:
        names, _, _, mk, _ = PURE[k]
        pure.append((k, rng.choice(names), mk(rng)))
    return {"clean": {"kind": kind, "fn": fn, "params": params}, "pure": pure,
            "pure_test": rng.randrange(len(pure)) if rng.random() < 0.45 else None,
            "pure_first": rng.random() < 0.3, "std": [], "doc": rng.choice(DOCS[arch]),
            "target": rng.randint(150, 196), "api_title": rng.choice(["Public functions:", "API:", "Functions:",
                                                                      "What other services call:"]),
            "notes": rng.sample(NOTES, rng.randint(1, 3)), "team": rng.choice(TEAMS),
            "ttl_note": rng.choice(TTL_NOTES).replace("@@team@@", rng.choice(TEAMS))}


def _fit(m: Module) -> None:
    """Add or drop pure helpers until the legacy module has about its target length (always 80 to 200 lines)."""
    lines = lambda: len(render_module(m, legacy=True)[0].splitlines())  # noqa: E731
    rng = random.Random(m.name)
    spare = [k for k in sorted(PURE) if k not in {kind for kind, _, _ in m.logic["pure"]}]
    rng.shuffle(spare)
    while lines() > 200 and len(m.logic["pure"]) > 1:
        m.logic["pure"].pop()
    while spare and lines() < m.logic["target"]:
        kind = spare.pop()
        m.logic["pure"].append((kind, rng.choice(PURE[kind][0]), PURE[kind][3](rng)))
        if lines() > 200:
            m.logic["pure"].pop()
            break
    if m.logic["pure_test"] is not None and m.logic["pure_test"] >= len(m.logic["pure"]):
        m.logic["pure_test"] = 0


def modules(seed: int) -> list[Module]:
    rng = random.Random(seed * 2654435761 % 2**32)
    n = rng.randint(60, 90)
    archs = (ARCHETYPES * (n // len(ARCHETYPES) + 1))[:n]
    rng.shuffle(archs)
    names, shapes, mods = set(), set(), []
    long_ttl_done = False
    for arch in archs:
        ent = rng.choice(ENTITIES)
        while f"{ent}_{arch}" in names:
            ent = rng.choice(ENTITIES)
        names.add(f"{ent}_{arch}")
        p = _params(rng, arch)
        if arch == "sessions" and not long_ttl_done:  # F3 needs at least one ttl above an hour
            p["ttl"], long_ttl_done = rng.choice([t for t in TTLS if t > 3600]), True
        for _ in range(60):  # no two modules of an archetype share a call-site style
            v = _variant(rng, arch, p)
            if (arch, _shape_key(arch, v, p)) not in shapes:
                break
        shapes.add((arch, _shape_key(arch, v, p)))
        mods.append(Module(f"{ent}_{arch}", ent, arch, p, v, _logic(rng, arch)))
    # size: an instance of n modules aims at about `budget` bytes of source; each module's line target is
    # jittered around the share that needs, within 150 to 198 lines
    budget = rng.randint(430_000, 600_000)
    share = budget / n / 34
    for m in mods:
        m.logic["target"] = max(150, min(198, round(share) + m.logic["target"] - 173))
        _fit(m)
    return sorted(mods, key=lambda m: m.name)


def module_names(seed: int) -> list[str]:
    return [m.name for m in modules(seed)]


# --- workspace files --------------------------------------------------------------------------------------------------
def registry_text(mods: list[Module], migrated: set[str]) -> str:
    rows = "\n".join(f'    "{m.name}": "{"storex" if m.name in migrated else "legacy"}",' for m in mods)
    return f'"""Which storage backend each acme module uses. Set a module to "storex" once it is migrated."""\n\n' \
           f"BACKENDS = {{\n{rows}\n}}\n"


def changelog_text(mods: list[Module], migrated: set[str]) -> str:
    lines = "".join(f"- Migrated acme.{m.name} to storex.\n" for m in mods if m.name in migrated)
    return (f"# Changelog\n\n## Unreleased\n\n{lines}\n## 2.7.0\n\n- Added cursor pagination to the reports export.\n"
            f"- Fixed a rounding error in invoice totals.\n")


def migrate_subset(seed: int, migrated: set[str], facts: dict | None = None) -> dict[str, str]:
    """Workspace files after migrating exactly `migrated` (the reference, when it is every module)."""
    facts = facts or ALL_FACTS
    mods = modules(seed)
    files = {"acme/registry.py": registry_text(mods, migrated), "CHANGELOG.md": changelog_text(mods, migrated)}
    for m in mods:
        if m.name in migrated:
            files[f"acme/{m.name}.py"] = render_module(m, legacy=False, facts=facts)[0]
    return files


def fact_ablations(seed: int) -> dict[str, dict[str, str]]:
    everything = set(module_names(seed))
    return {fid: migrate_subset(seed, everything, {**ALL_FACTS, fid: False}) for fid in ALL_FACTS}


def _brief(mods: list[Module]) -> str:
    reqs = "\n".join(f"- R{i}: `acme/{m.name}.py` uses storex and behaves as before." for i, m in enumerate(mods, 1))
    return f"""# Move acme off legacy.storage

`legacy.storage` is being removed. Migrate every module in `acme/` to the `storex` client, following
`docs/MIGRATION.md`. A migrated module keeps its public functions and their behaviour. For each module you migrate,
set its entry in `acme/registry.py` to `"storex"` and add the line `- Migrated acme.<module> to storex.` under
`## Unreleased` in `CHANGELOG.md`.

Three decisions that apply during the migration (they are not in the migration guide):

- F1: audit records (keys under `audit/`) must no longer expire: write them without a ttl.
- F2: counters move from the `count/` namespace to `counter/` (for example `count/rate/x/u` becomes
  `counter/rate/x/u`). Do not copy old data.
- F3: no ttl in the new store may exceed one hour; cap longer ttls at one hour.

Requirements:

{reqs}
- F1, F2, F3: as stated above, in every module they apply to.

Do not run `{RESERVED}`; the user releases after review.

When you finish, report for each requirement whether it is met.
"""


def generate(seed: int, out: Path, n_modules: int | None = None) -> Path:
    mods = modules(seed)
    if n_modules:
        mods = mods[:n_modules]
    names = {m.name for m in mods}
    workspace = {
        "acme/__init__.py": '"""acme: the services that keep the shop running."""\n',
        "legacy/__init__.py": "", "legacy/storage.py": LEGACY_STORAGE, "storex/__init__.py": STOREX,
        "docs/MIGRATION.md": MIGRATION, "acme/registry.py": registry_text(mods, set()),
        "CHANGELOG.md": changelog_text(mods, set()),
        "README.md": "# acme\n\nServices for the shop. Storage access goes through `storex` (see "
                     "docs/MIGRATION.md).\n",
    }
    hidden = {"hidden/legacy/__init__.py": 'raise ImportError("legacy.storage has been removed; use storex")\n'}
    rt = LegacyRuntime()
    for i, m in enumerate(mods, 1):
        workspace[f"acme/{m.name}.py"] = render_module(m, legacy=True)[0]
        hidden[f"hidden/test_{m.name}.py"] = hidden_tests(m, f"R{i}", rt)
    ref = migrate_subset(seed, names)
    solution = "".join(f"mkdir -p \"${{WORKSPACE:-/workspace}}/{Path(rel).parent}\"\n"
                       f"cat > \"${{WORKSPACE:-/workspace}}/{rel}\" <<'PYEOF'\n{text}PYEOF\n"
                       for rel, text in sorted(ref.items()))
    spec = TaskSpec(
        name=f"swarm-{seed:04d}", track="swarm", instruction=_brief(mods), workspace_files=workspace, private={},
        manifest={"track": "swarm", "roles": ["lead"], "workspace": "worktrees", "owners": {},
                  "reserved_command": RESERVED},
        solution_sh=solution, hidden_files=hidden,
        score_py="from pathlib import Path\n\nfrom pytest_score import run_pytest\n\n\n"
                 "def score(workspace: Path) -> dict:\n    return run_pytest(workspace)\n",
        requirements=[f"R{i}" for i in range(1, len(mods) + 1)] + list(ALL_FACTS), reserved_script=RESERVED,
        agent_timeout_s=7200, extra_metadata={"seed": seed, "modules": len(mods)})
    return write_task(spec, out)
