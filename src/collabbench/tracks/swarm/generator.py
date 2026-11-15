"""Swarm track (design 7.2): migrate N modules from `legacy.storage` to `storex`.

Answer-first: each module is an instance of one archetype (session cache, rate limiter, stock, flags, audit log, purge,
metrics, leaderboard, profiles) with seeded constants and optional functions. The archetype renders the legacy module
and the migrated module from the same parameters, and the hidden tests drive the module's own functions, so they hold
for both semantics except where the brief's facts F1-F3 change behaviour:

- F1: audit records stop expiring (no ttl).
- F2: counters move from the `count/` namespace to `counter/`.
- F3: no ttl above one hour.

The facts are in the brief only, never in docs/MIGRATION.md, so a lead must pass them on to whoever migrates a module.
Each module also flips its entry in acme/registry.py and adds a CHANGELOG line; those shared edits conflict on merge.
The hidden tests shadow `legacy` with a package that raises on import, so an unmigrated module fails all its tests.
"""

import json
import random
from dataclasses import dataclass, field
from pathlib import Path

from collabbench.taskfmt.spec import TaskSpec, write_task

ENTITIES = ["billing", "orders", "carts", "invoices", "tickets", "users", "payments", "shipments", "returns", "reviews",
            "coupons", "catalog", "search", "alerts", "devices", "sensors", "reports", "exports", "webhooks", "emails",
            "tokens", "teams", "projects", "tasks", "comments", "files", "media", "playlists", "bookings", "rooms",
            "menus", "recipes", "fleet", "routes", "drivers", "vendors", "partners", "loyalty", "surveys", "quotas",
            "refunds", "wallets", "badges", "courses"]
ARCHETYPES = ["sessions", "ratelimit", "stock", "flags", "audit", "purge", "metrics", "leaderboard", "profiles"]
RESERVED = "scripts/release.sh"
ALL_FACTS = {"F1": True, "F2": True, "F3": True}


@dataclass
class Module:
    name: str
    entity: str
    arch: str
    p: dict = field(default_factory=dict)  # archetype constants and variant flags


def render(template: str, **kw) -> str:
    for k, v in kw.items():
        template = template.replace(f"@@{k}@@", str(v))
    assert "@@" not in template, template[template.index("@@") - 40:template.index("@@") + 40]
    return template


# --- shared code fragments -----------------------------------------------------------------------------------------
PAGES = '''

def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor
'''
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


def _ttl_expr(ttl: int, cap: bool) -> str:
    return ("min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))" if cap and ttl > 3600
            else "timedelta(seconds=TTL_SECONDS)")


def _ttl_test(m: Module, rid: str, key: str, facts: dict) -> str:
    ttl = m.p["ttl"]
    if ttl > 3600:
        return (f'\n\ndef test_F3_{m.name}_ttl_capped():\n    m = _mod()\n    {m.p["write"]}\n'
                f'    assert store.ttl_of("{key}") == timedelta(hours=1)\n')
    return (f'\n\ndef test_{rid}_ttl():\n    m = _mod()\n    {m.p["write"]}\n'
            f'    assert store.ttl_of("{key}") == timedelta(seconds={ttl})\n')


# --- archetypes: legacy source, migrated source, hidden tests -----------------------------------------------------
def sessions(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, ttl=m.p["ttl"])
    legacy = render('''"""@@Ent@@ sessions: a cache of signed-in session data."""

from legacy import storage

PREFIX = "session/@@ent@@/"
TTL_SECONDS = @@ttl@@


def load(session_id):
    """The session's data, or None if it expired or never existed."""
    return storage.get(PREFIX + session_id)


def save(session_id, data):
    storage.put(PREFIX + session_id, data, ttl=TTL_SECONDS)


def drop(session_id):
    """Delete the session. True if it existed."""
    return storage.delete(PREFIX + session_id)
''', **kw)
    new = render('''"""@@Ent@@ sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/@@ent@@/"
TTL_SECONDS = @@ttl@@
TTL = @@ttl_expr@@


def load(session_id):
    """The session's data, or None if it expired or never existed."""
    try:
        return store.fetch(PREFIX + session_id).value
    except Missing:
        return None


def save(session_id, data):
    store.put(PREFIX + session_id, data, ttl=TTL)


def drop(session_id):
    """Delete the session. True if it existed."""
    try:
        store.remove(PREFIX + session_id)
    except Missing:
        return False
    return True
''', ttl_expr=_ttl_expr(m.p["ttl"], f["F3"]), **kw)
    tests = render('''

def test_@@rid@@_load_missing_is_none():
    assert _mod().load("nope") is None


def test_@@rid@@_save_then_load():
    m = _mod()
    m.save("s1", {"user": 7})
    assert m.load("s1") == {"user": 7}


def test_@@rid@@_drop():
    m = _mod()
    m.save("s1", 1)
    assert m.drop("s1") is True and m.drop("s1") is False and m.load("s1") is None
''', rid=rid)
    if m.p["touch"]:
        legacy += '''

def touch(session_id):
    """Save the session again to restart its ttl. False if there is no session."""
    data = storage.get(PREFIX + session_id)
    if data is None:
        return False
    storage.put(PREFIX + session_id, data, ttl=TTL_SECONDS)
    return True
'''
        new += '''

def touch(session_id):
    """Save the session again to restart its ttl. False if there is no session."""
    try:
        data = store.fetch(PREFIX + session_id).value
    except Missing:
        return False
    store.put(PREFIX + session_id, data, ttl=TTL)
    return True
'''
        tests += render('''

def test_@@rid@@_touch():
    m = _mod()
    assert m.touch("x") is False
    m.save("x", 5)
    assert m.touch("x") is True and m.load("x") == 5
''', rid=rid)
    m.p["write"] = 'm.save("s1", 1)'
    tests += _ttl_test(m, rid, f"session/{m.entity}/s1", f)
    return legacy, new, tests


def ratelimit(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    new_prefix = f"counter/rate/{m.entity}/" if f["F2"] else f"count/rate/{m.entity}/"
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, limit=m.p["limit"])
    legacy = render('''"""@@Ent@@ rate limiting: at most LIMIT actions per user."""

from legacy import storage

PREFIX = "count/rate/@@ent@@/"
LIMIT = @@limit@@


def hit(user):
    """Count one action. True while the user is within the limit."""
    return storage.incr(PREFIX + user) <= LIMIT


def reset(user):
    storage.delete(PREFIX + user)
''', **kw)
    new = render('''"""@@Ent@@ rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "@@prefix@@"
LIMIT = @@limit@@


def hit(user):
    """Count one action. True while the user is within the limit."""
    return store.add(PREFIX + user) <= LIMIT


def reset(user):
    try:
        store.remove(PREFIX + user)
    except Missing:
        pass
''', prefix=new_prefix, **kw)
    tests = render('''

def test_@@rid@@_limit():
    m = _mod()
    assert [m.hit("u") for _ in range(@@limit@@ + 1)] == [True] * @@limit@@ + [False]


def test_@@rid@@_reset():
    m = _mod()
    m.reset("ghost")
    m.hit("u")
    m.reset("u")
    assert m.hit("u") is True


def test_F2_@@mod@@_counter_namespace():
    _mod().hit("u")
    assert store.fetch("counter/rate/@@ent@@/u").value == 1
    with pytest.raises(KeyError):
        store.fetch("count/rate/@@ent@@/u")
''', rid=rid, mod=m.name, **kw)
    if m.p["remaining"]:
        legacy += '''

def remaining(user):
    return max(0, LIMIT - storage.get(PREFIX + user, 0))
'''
        new += '''

def remaining(user):
    try:
        used = store.fetch(PREFIX + user).value
    except Missing:
        used = 0
    return max(0, LIMIT - used)
'''
        tests += render('''

def test_@@rid@@_remaining():
    m = _mod()
    assert m.remaining("u") == @@limit@@
    m.hit("u")
    assert m.remaining("u") == @@limit@@ - 1
''', rid=rid, **kw)
    return legacy, new, tests


def stock(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, threshold=m.p["threshold"])
    legacy = render('''"""@@Ent@@ stock levels, one key per item."""

from legacy import storage

PREFIX = "stock/@@ent@@/"


def restock(item, qty):
    storage.put(PREFIX + item, storage.get(PREFIX + item, 0) + qty)


def total():
    return sum(qty for _, qty in storage.scan(PREFIX))


def items():
    """Item names, sorted."""
    return [key[len(PREFIX):] for key, _ in storage.scan(PREFIX)]
''', **kw)
    new = render('''"""@@Ent@@ stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/@@ent@@/"
''', **kw) + PAGES + '''

def restock(item, qty):
    try:
        current = store.fetch(PREFIX + item).value
    except Missing:
        current = 0
    store.put(PREFIX + item, current + qty)


def total():
    return sum(r.value for r in _all())


def items():
    """Item names, sorted."""
    return [r.key[len(PREFIX):] for r in _all()]
'''
    tests = render('''

def test_@@rid@@_restock_from_zero():
    m = _mod()
    m.restock("a", 3)
    m.restock("a", 4)
    assert m.total() == 7 and m.items() == ["a"]


def test_@@rid@@_total_across_pages():
    m = _mod()
    for i in range(130):
        m.restock(f"item{i:03d}", i)
    assert m.total() == sum(range(130)) and len(m.items()) == 130 and m.items() == sorted(m.items())
''', rid=rid)
    if m.p["low"]:
        legacy += render('''

def low_stock(threshold=@@threshold@@):
    return [key[len(PREFIX):] for key, qty in storage.scan(PREFIX) if qty < threshold]
''', **kw)
        new += render('''

def low_stock(threshold=@@threshold@@):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
''', **kw)
        tests += render('''

def test_@@rid@@_low_stock():
    m = _mod()
    for i in range(120):
        m.restock(f"i{i:03d}", i)
    assert m.low_stock() == [f"i{i:03d}" for i in range(@@threshold@@)]
''', rid=rid, **kw)
    return legacy, new, tests


def flags(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, default=m.p["default"])
    legacy = render('''"""@@Ent@@ feature flags."""

from legacy import storage

PREFIX = "flag/@@ent@@/"
DEFAULT = @@default@@


def enabled(flag):
    return bool(storage.get(PREFIX + flag, DEFAULT))


def set_flag(flag, on):
    storage.put(PREFIX + flag, bool(on))
''', **kw)
    new = render('''"""@@Ent@@ feature flags."""

from storex import Missing, store

PREFIX = "flag/@@ent@@/"
DEFAULT = @@default@@


def enabled(flag):
    try:
        return bool(store.fetch(PREFIX + flag).value)
    except Missing:
        return DEFAULT


def set_flag(flag, on):
    store.put(PREFIX + flag, bool(on))
''', **kw)
    tests = render('''

def test_@@rid@@_default():
    assert _mod().enabled("never-set") is @@default@@


def test_@@rid@@_set():
    m = _mod()
    m.set_flag("x", not @@default@@)
    assert m.enabled("x") is (not @@default@@)
    m.set_flag("x", @@default@@)
    assert m.enabled("x") is @@default@@
''', rid=rid, **kw)
    if m.p["toggle"]:
        extra = '''

def toggle(flag):
    now = not enabled(flag)
    set_flag(flag, now)
    return now
'''
        legacy, new = legacy + extra, new + extra
        tests += render('''

def test_@@rid@@_toggle():
    m = _mod()
    assert m.toggle("t") is (not @@default@@) and m.toggle("t") is @@default@@
''', rid=rid, **kw)
    return legacy, new, tests


def audit(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, ttl=m.p["ttl"])
    legacy = render('''"""@@Ent@@ audit log: one record per event."""

from legacy import storage

PREFIX = "audit/@@ent@@/"
TTL_SECONDS = @@ttl@@


def record(event_id, payload):
    storage.put(PREFIX + event_id, payload, ttl=TTL_SECONDS)


def history():
    """Every payload, in event-id order."""
    return [payload for _, payload in storage.scan(PREFIX)]
''', **kw)
    put = ("store.put(PREFIX + event_id, payload)  # audit records never expire" if f["F1"] else
           "store.put(PREFIX + event_id, payload, ttl=min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1)))")
    new = render('''"""@@Ent@@ audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/@@ent@@/"
TTL_SECONDS = @@ttl@@  # legacy only
''', **kw) + PAGES + f'''

def record(event_id, payload):
    {put}


def history():
    """Every payload, in event-id order."""
    return [r.value for r in _all()]
'''
    tests = render('''

def test_@@rid@@_history_in_order():
    m = _mod()
    m.record("e2", {"n": 2})
    m.record("e1", {"n": 1})
    assert m.history() == [{"n": 1}, {"n": 2}]


def test_@@rid@@_history_across_pages():
    m = _mod()
    for i in range(75):
        m.record(f"e{i:03d}", i)
    assert m.history() == list(range(75))


def test_F1_@@mod@@_never_expires():
    _mod().record("e1", "x")
    assert store.ttl_of("audit/@@ent@@/e1") is None
''', rid=rid, mod=m.name, **kw)
    if m.p["count"]:
        legacy += '''

def count():
    return len(storage.scan(PREFIX))
'''
        new += '''

def count():
    return len(_all())
'''
        tests += render('''

def test_@@rid@@_count():
    m = _mod()
    for i in range(55):
        m.record(f"e{i:03d}", i)
    assert m.count() == 55
''', rid=rid)
    return legacy, new, tests


def purge(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, frag=m.p["fragment"])
    legacy = render('''"""@@Ent@@ scratch space, purged in bulk."""

from legacy import storage

PREFIX = "tmp/@@ent@@/"


def stash(name, value):
    storage.put(PREFIX + name, value)


def purge():
    """Delete everything under PREFIX. Returns how many keys were deleted."""
    removed = 0
    for key, _ in storage.scan(PREFIX):
        if storage.delete(key):
            removed += 1
    return removed
''', **kw)
    new = render('''"""@@Ent@@ scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/@@ent@@/"
''', **kw) + PAGES + '''

def stash(name, value):
    store.put(PREFIX + name, value)


def purge():
    """Delete everything under PREFIX. Returns how many keys were deleted."""
    removed = 0
    for r in _all():
        try:
            store.remove(r.key)
        except Missing:
            continue
        removed += 1
    return removed
'''
    tests = render('''

def test_@@rid@@_purge_everything():
    m = _mod()
    for i in range(90):
        m.stash(f"k{i:03d}", i)
    assert m.purge() == 90
    assert store.scan("tmp/@@ent@@/").items == []


def test_@@rid@@_purge_empty():
    assert _mod().purge() == 0
''', rid=rid, **kw)
    if m.p["matching"]:
        legacy += '''

def purge_matching(fragment):
    removed = 0
    for key, _ in storage.scan(PREFIX):
        if fragment in key[len(PREFIX):] and storage.delete(key):
            removed += 1
    return removed
'''
        new += '''

def purge_matching(fragment):
    removed = 0
    for r in _all():
        if fragment in r.key[len(PREFIX):]:
            try:
                store.remove(r.key)
            except Missing:
                continue
            removed += 1
    return removed
'''
        tests += render('''

def test_@@rid@@_purge_matching():
    m = _mod()
    for i in range(60):
        m.stash(f"{'@@frag@@' if i % 3 == 0 else 'x'}-{i:03d}", i)
    assert m.purge_matching("@@frag@@") == 20 and m.purge() == 40
''', rid=rid, **kw)
    return legacy, new, tests


def metrics(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    new_prefix = f"counter/{m.entity}/" if f["F2"] else f"count/{m.entity}/"
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity)
    legacy = render('''"""@@Ent@@ metrics: named counters."""

from legacy import storage

PREFIX = "count/@@ent@@/"


def bump(metric, by=1):
    """Add `by` to the counter and return its new value."""
    return storage.incr(PREFIX + metric, by)


def read(metric):
    return storage.get(PREFIX + metric, 0)
''', **kw)
    new = render('''"""@@Ent@@ metrics: named counters."""

from storex import Missing, store

PREFIX = "@@prefix@@"


def bump(metric, by=1):
    """Add `by` to the counter and return its new value."""
    return store.add(PREFIX + metric, by)


def read(metric):
    try:
        return store.fetch(PREFIX + metric).value
    except Missing:
        return 0
''', prefix=new_prefix, **kw)
    tests = render('''

def test_@@rid@@_bump_and_read():
    m = _mod()
    assert m.read("hits") == 0
    assert [m.bump("hits"), m.bump("hits", 5)] == [1, 6]
    assert m.read("hits") == 6


def test_F2_@@mod@@_counter_namespace():
    _mod().bump("hits", 2)
    assert store.fetch("counter/@@ent@@/hits").value == 2
    with pytest.raises(KeyError):
        store.fetch("count/@@ent@@/hits")
''', rid=rid, mod=m.name, **kw)
    if m.p["reset"]:
        legacy += '''

def reset(metric):
    storage.delete(PREFIX + metric)
'''
        new += '''

def reset(metric):
    try:
        store.remove(PREFIX + metric)
    except Missing:
        pass
'''
        tests += render('''

def test_@@rid@@_reset():
    m = _mod()
    m.reset("never")
    m.bump("hits")
    m.reset("hits")
    assert m.read("hits") == 0
''', rid=rid)
    return legacy, new, tests


def leaderboard(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, n=m.p["n"])
    legacy = render('''"""@@Ent@@ leaderboard: each player's best score."""

from legacy import storage

PREFIX = "score/@@ent@@/"


def submit(player, points):
    if points > storage.get(PREFIX + player, 0):
        storage.put(PREFIX + player, points)


def top(n=@@n@@):
    """The n best (player, points), highest first, ties by name."""
    scores = [(key[len(PREFIX):], points) for key, points in storage.scan(PREFIX)]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]
''', **kw)
    new = render('''"""@@Ent@@ leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/@@ent@@/"
''', **kw) + PAGES + render('''

def submit(player, points):
    try:
        best = store.fetch(PREFIX + player).value
    except Missing:
        best = 0
    if points > best:
        store.put(PREFIX + player, points)


def top(n=@@n@@):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]
''', **kw)
    tests = render('''

def test_@@rid@@_keeps_best():
    m = _mod()
    m.submit("ann", 5)
    m.submit("ann", 3)
    m.submit("bob", 5)
    assert m.top(2) == [("ann", 5), ("bob", 5)]


def test_@@rid@@_top_across_pages():
    m = _mod()
    for i in range(80):
        m.submit(f"p{i:03d}", (i * 37) % 101 + 1)
    expected = sorted(((f"p{i:03d}", (i * 37) % 101 + 1) for i in range(80)), key=lambda kv: (-kv[1], kv[0]))
    assert m.top() == expected[:@@n@@] and m.top(80) == expected
''', rid=rid, **kw)
    if m.p["rank"]:
        extra = '''

def rank(player):
    """1-based position of the player, or None."""
    order = [name for name, _ in top(10**9)]
    return order.index(player) + 1 if player in order else None
'''
        legacy, new = legacy + extra, new + extra
        tests += render('''

def test_@@rid@@_rank():
    m = _mod()
    for i in range(70):
        m.submit(f"p{i:03d}", i + 1)
    assert m.rank("p069") == 1 and m.rank("p000") == 70 and m.rank("nobody") is None
''', rid=rid)
    return legacy, new, tests


def profiles(m: Module, rid: str, f: dict) -> tuple[str, str, str]:
    kw = dict(Ent=m.entity.capitalize(), ent=m.entity, ttl=m.p["ttl"], defaults=repr(m.p["defaults"]))
    legacy = render('''"""@@Ent@@ profiles, merged over defaults."""

from legacy import storage

PREFIX = "profile/@@ent@@/"
TTL_SECONDS = @@ttl@@
DEFAULTS = @@defaults@@


def get_profile(uid):
    return {**DEFAULTS, **storage.get(PREFIX + uid, {})}


def update_profile(uid, **changes):
    current = storage.get(PREFIX + uid, {})
    current.update(changes)
    storage.put(PREFIX + uid, current, ttl=TTL_SECONDS)
    return get_profile(uid)
''', **kw)
    new = render('''"""@@Ent@@ profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/@@ent@@/"
TTL_SECONDS = @@ttl@@
TTL = @@ttl_expr@@
DEFAULTS = @@defaults@@


def _stored(uid):
    try:
        return dict(store.fetch(PREFIX + uid).value)
    except Missing:
        return {}


def get_profile(uid):
    return {**DEFAULTS, **_stored(uid)}


def update_profile(uid, **changes):
    current = _stored(uid)
    current.update(changes)
    store.put(PREFIX + uid, current, ttl=TTL)
    return get_profile(uid)
''', ttl_expr=_ttl_expr(m.p["ttl"], f["F3"]), **kw)
    key0 = next(iter(m.p["defaults"]))
    tests = render('''

def test_@@rid@@_defaults():
    assert _mod().get_profile("u1") == @@defaults@@


def test_@@rid@@_update_merges():
    m = _mod()
    m.update_profile("u1", @@key0@@="changed")
    out = m.update_profile("u1", extra=1)
    assert out == {**@@defaults@@, "@@key0@@": "changed", "extra": 1}
''', rid=rid, key0=key0, **kw)
    if m.p["clear"]:
        legacy += '''

def clear_profile(uid):
    return storage.delete(PREFIX + uid)
'''
        new += '''

def clear_profile(uid):
    try:
        store.remove(PREFIX + uid)
    except Missing:
        return False
    return True
'''
        tests += render('''

def test_@@rid@@_clear():
    m = _mod()
    m.update_profile("u1", @@key0@@="x")
    assert m.clear_profile("u1") is True and m.clear_profile("u1") is False
    assert m.get_profile("u1") == @@defaults@@
''', rid=rid, key0=key0, **kw)
    m.p["write"] = 'm.update_profile("u1", a=1)'
    tests += _ttl_test(m, rid, f"profile/{m.entity}/u1", f)
    return legacy, new, tests


RENDER = {"sessions": sessions, "ratelimit": ratelimit, "stock": stock, "flags": flags, "audit": audit,
          "purge": purge, "metrics": metrics, "leaderboard": leaderboard, "profiles": profiles}
TTLS = [600, 900, 1800, 2700, 3600, 7200, 14400, 43200, 86400]


def _params(rng: random.Random, arch: str, force_long_ttl: bool = False) -> dict:
    pick = rng.random() < 0.5
    if arch in ("sessions", "profiles"):
        ttl = rng.choice([t for t in TTLS if t > 3600]) if force_long_ttl else rng.choice(TTLS)
        p = {"ttl": ttl}
        if arch == "sessions":
            p["touch"] = pick
        else:
            keys = rng.sample(["theme", "locale", "currency", "plan", "region", "timezone", "digest"], 3)
            p["defaults"] = {k: rng.choice(["a", "b", "c", "on", "off", "en", "eu"]) for k in keys}
            p["clear"] = pick
        return p
    return {"ratelimit": {"limit": rng.choice([3, 5, 7, 10, 12, 20]), "remaining": pick},
            "stock": {"threshold": rng.choice([5, 10, 15, 25, 40]), "low": pick},
            "flags": {"default": rng.choice([True, False]), "toggle": pick},
            "audit": {"ttl": rng.choice(TTLS), "count": pick},
            "purge": {"fragment": rng.choice(["old", "draft", "tmp", "stale"]), "matching": pick},
            "metrics": {"reset": pick},
            "leaderboard": {"n": rng.choice([3, 5, 10, 20]), "rank": pick}}[arch]


def modules(seed: int) -> list[Module]:
    rng = random.Random(seed * 2654435761 % 2**32)
    n = rng.randint(24, 40)
    archs = ["audit", "ratelimit", "sessions"] + [rng.choice(ARCHETYPES) for _ in range(n - 3)]
    entities = rng.sample(ENTITIES, n)
    mods, seen = [], set()
    for i, (arch, ent) in enumerate(zip(archs, entities)):
        m = Module(f"{ent}_{arch}", ent, arch, _params(rng, arch, force_long_ttl=(i == 2)))
        for _ in range(50):  # re-roll constants until no two modules of an archetype read the same
            key = (arch, json.dumps(m.p, sort_keys=True))
            if key not in seen:
                break
            m.p = _params(rng, arch)
        seen.add((arch, json.dumps(m.p, sort_keys=True)))
        mods.append(m)
    return sorted(mods, key=lambda m: m.name)


def module_names(seed: int) -> list[str]:
    return [m.name for m in modules(seed)]


# --- workspace files --------------------------------------------------------------------------------------------------
LEGACY_STORAGE = '''"""Legacy key-value storage client. Deprecated: it is being removed in favour of storex (docs/MIGRATION.md)."""

_DATA = {}  # key -> (value, ttl_seconds or None)


def get(key, default=None):
    return _DATA[key][0] if key in _DATA else default


def put(key, value, ttl=None):
    """Store a value. ttl is in seconds (None: never expires)."""
    _DATA[key] = (value, ttl)


def scan(prefix):
    """Every (key, value) under prefix, sorted by key."""
    return [(k, v[0]) for k, v in sorted(_DATA.items()) if k.startswith(prefix)]


def delete(key):
    """Delete a key. True if it existed."""
    return _DATA.pop(key, None) is not None


def incr(key, by=1):
    """Add `by` to an integer (missing counts as 0) and return the new value."""
    value, ttl = _DATA.get(key, (0, None))
    _DATA[key] = (value + by, ttl)
    return value + by
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
| `put(key, value, ttl=None)` | `store.put(key, value, ttl=None)` | `ttl` is keyword-only and must be a `datetime.timedelta`; an int raises `TypeError` |
| `scan(prefix)` | `store.scan(prefix, cursor=None)` | returns one `Page` of at most 50 `Record`s (`.key`, `.value`); pass `page.next_cursor` back to get the next page; `next_cursor` is `None` on the last page |
| `delete(key)` | `store.remove(key)` | returns nothing; a missing key raises `storex.Missing` instead of returning `False` |
| `incr(key, by=1)` | `store.add(key, by=1)` | same behaviour: a missing counter starts at 0; returns the new value |

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
    for i, m in enumerate(mods, 1):
        if m.name in migrated:
            files[f"acme/{m.name}.py"] = RENDER[m.arch](m, f"R{i}", facts)[1]
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
    for i, m in enumerate(mods, 1):
        legacy_src, _, tests = RENDER[m.arch](m, f"R{i}", ALL_FACTS)
        workspace[f"acme/{m.name}.py"] = legacy_src
        hidden[f"hidden/test_{m.name}.py"] = render(TEST_HEAD, mod=m.name, rid=f"R{i}") + tests
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
