#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}/."
cat > "${WORKSPACE:-/workspace}/CHANGELOG.md" <<'PYEOF'
# Changelog

## Unreleased

- Migrated acme.alerts_ratelimit to storex.
- Migrated acme.badges_flags to storex.
- Migrated acme.bookings_metrics to storex.
- Migrated acme.carts_stock to storex.
- Migrated acme.catalog_stock to storex.
- Migrated acme.coupons_ratelimit to storex.
- Migrated acme.courses_audit to storex.
- Migrated acme.devices_stock to storex.
- Migrated acme.drivers_sessions to storex.
- Migrated acme.emails_sessions to storex.
- Migrated acme.exports_leaderboard to storex.
- Migrated acme.files_leaderboard to storex.
- Migrated acme.fleet_audit to storex.
- Migrated acme.invoices_purge to storex.
- Migrated acme.loyalty_profiles to storex.
- Migrated acme.menus_purge to storex.
- Migrated acme.orders_audit to storex.
- Migrated acme.partners_audit to storex.
- Migrated acme.payments_metrics to storex.
- Migrated acme.playlists_ratelimit to storex.
- Migrated acme.projects_leaderboard to storex.
- Migrated acme.recipes_purge to storex.
- Migrated acme.refunds_flags to storex.
- Migrated acme.reports_profiles to storex.
- Migrated acme.returns_ratelimit to storex.
- Migrated acme.reviews_flags to storex.
- Migrated acme.rooms_stock to storex.
- Migrated acme.routes_purge to storex.
- Migrated acme.search_purge to storex.
- Migrated acme.shipments_profiles to storex.
- Migrated acme.surveys_leaderboard to storex.
- Migrated acme.tasks_audit to storex.
- Migrated acme.tokens_stock to storex.
- Migrated acme.users_sessions to storex.
- Migrated acme.vendors_flags to storex.

## 2.7.0

- Added cursor pagination to the reports export.
- Fixed a rounding error in invoice totals.
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/alerts_ratelimit.py" <<'PYEOF'
"""Alerts rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/alerts/"
LIMIT = 5


def hit(user):
    """Count one action. True while the user is within the limit."""
    return store.add(PREFIX + user) <= LIMIT


def reset(user):
    try:
        store.remove(PREFIX + user)
    except Missing:
        pass


def remaining(user):
    try:
        used = store.fetch(PREFIX + user).value
    except Missing:
        used = 0
    return max(0, LIMIT - used)
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/badges_flags.py" <<'PYEOF'
"""Badges feature flags."""

from storex import Missing, store

PREFIX = "flag/badges/"
DEFAULT = True


def enabled(flag):
    try:
        return bool(store.fetch(PREFIX + flag).value)
    except Missing:
        return DEFAULT


def set_flag(flag, on):
    store.put(PREFIX + flag, bool(on))
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/bookings_metrics.py" <<'PYEOF'
"""Bookings metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/bookings/"


def bump(metric, by=1):
    """Add `by` to the counter and return its new value."""
    return store.add(PREFIX + metric, by)


def read(metric):
    try:
        return store.fetch(PREFIX + metric).value
    except Missing:
        return 0


def reset(metric):
    try:
        store.remove(PREFIX + metric)
    except Missing:
        pass
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/carts_stock.py" <<'PYEOF'
"""Carts stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/carts/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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


def low_stock(threshold=10):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/catalog_stock.py" <<'PYEOF'
"""Catalog stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/catalog/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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


def low_stock(threshold=5):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/coupons_ratelimit.py" <<'PYEOF'
"""Coupons rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/coupons/"
LIMIT = 12


def hit(user):
    """Count one action. True while the user is within the limit."""
    return store.add(PREFIX + user) <= LIMIT


def reset(user):
    try:
        store.remove(PREFIX + user)
    except Missing:
        pass


def remaining(user):
    try:
        used = store.fetch(PREFIX + user).value
    except Missing:
        used = 0
    return max(0, LIMIT - used)
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/courses_audit.py" <<'PYEOF'
"""Courses audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/courses/"
TTL_SECONDS = 3600  # legacy only


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def record(event_id, payload):
    store.put(PREFIX + event_id, payload)  # audit records never expire


def history():
    """Every payload, in event-id order."""
    return [r.value for r in _all()]


def count():
    return len(_all())
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/devices_stock.py" <<'PYEOF'
"""Devices stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/devices/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/drivers_sessions.py" <<'PYEOF'
"""Drivers sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/drivers/"
TTL_SECONDS = 14400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/emails_sessions.py" <<'PYEOF'
"""Emails sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/emails/"
TTL_SECONDS = 43200
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))


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


def touch(session_id):
    """Save the session again to restart its ttl. False if there is no session."""
    try:
        data = store.fetch(PREFIX + session_id).value
    except Missing:
        return False
    store.put(PREFIX + session_id, data, ttl=TTL)
    return True
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/exports_leaderboard.py" <<'PYEOF'
"""Exports leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/exports/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def submit(player, points):
    try:
        best = store.fetch(PREFIX + player).value
    except Missing:
        best = 0
    if points > best:
        store.put(PREFIX + player, points)


def top(n=3):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/files_leaderboard.py" <<'PYEOF'
"""Files leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/files/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def submit(player, points):
    try:
        best = store.fetch(PREFIX + player).value
    except Missing:
        best = 0
    if points > best:
        store.put(PREFIX + player, points)


def top(n=10):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]


def rank(player):
    """1-based position of the player, or None."""
    order = [name for name, _ in top(10**9)]
    return order.index(player) + 1 if player in order else None
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/fleet_audit.py" <<'PYEOF'
"""Fleet audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/fleet/"
TTL_SECONDS = 86400  # legacy only


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def record(event_id, payload):
    store.put(PREFIX + event_id, payload)  # audit records never expire


def history():
    """Every payload, in event-id order."""
    return [r.value for r in _all()]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/invoices_purge.py" <<'PYEOF'
"""Invoices scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/invoices/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/loyalty_profiles.py" <<'PYEOF'
"""Loyalty profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/loyalty/"
TTL_SECONDS = 600
TTL = timedelta(seconds=TTL_SECONDS)
DEFAULTS = {'locale': 'on', 'digest': 'en', 'currency': 'eu'}


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


def clear_profile(uid):
    try:
        store.remove(PREFIX + uid)
    except Missing:
        return False
    return True
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/menus_purge.py" <<'PYEOF'
"""Menus scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/menus/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/orders_audit.py" <<'PYEOF'
"""Orders audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/orders/"
TTL_SECONDS = 7200  # legacy only


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def record(event_id, payload):
    store.put(PREFIX + event_id, payload)  # audit records never expire


def history():
    """Every payload, in event-id order."""
    return [r.value for r in _all()]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/partners_audit.py" <<'PYEOF'
"""Partners audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/partners/"
TTL_SECONDS = 1800  # legacy only


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def record(event_id, payload):
    store.put(PREFIX + event_id, payload)  # audit records never expire


def history():
    """Every payload, in event-id order."""
    return [r.value for r in _all()]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/payments_metrics.py" <<'PYEOF'
"""Payments metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/payments/"


def bump(metric, by=1):
    """Add `by` to the counter and return its new value."""
    return store.add(PREFIX + metric, by)


def read(metric):
    try:
        return store.fetch(PREFIX + metric).value
    except Missing:
        return 0
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/playlists_ratelimit.py" <<'PYEOF'
"""Playlists rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/playlists/"
LIMIT = 5


def hit(user):
    """Count one action. True while the user is within the limit."""
    return store.add(PREFIX + user) <= LIMIT


def reset(user):
    try:
        store.remove(PREFIX + user)
    except Missing:
        pass
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/projects_leaderboard.py" <<'PYEOF'
"""Projects leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/projects/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def submit(player, points):
    try:
        best = store.fetch(PREFIX + player).value
    except Missing:
        best = 0
    if points > best:
        store.put(PREFIX + player, points)


def top(n=3):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]


def rank(player):
    """1-based position of the player, or None."""
    order = [name for name, _ in top(10**9)]
    return order.index(player) + 1 if player in order else None
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/recipes_purge.py" <<'PYEOF'
"""Recipes scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/recipes/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/refunds_flags.py" <<'PYEOF'
"""Refunds feature flags."""

from storex import Missing, store

PREFIX = "flag/refunds/"
DEFAULT = True


def enabled(flag):
    try:
        return bool(store.fetch(PREFIX + flag).value)
    except Missing:
        return DEFAULT


def set_flag(flag, on):
    store.put(PREFIX + flag, bool(on))


def toggle(flag):
    now = not enabled(flag)
    set_flag(flag, now)
    return now
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/registry.py" <<'PYEOF'
"""Which storage backend each acme module uses. Set a module to "storex" once it is migrated."""

BACKENDS = {
    "alerts_ratelimit": "storex",
    "badges_flags": "storex",
    "bookings_metrics": "storex",
    "carts_stock": "storex",
    "catalog_stock": "storex",
    "coupons_ratelimit": "storex",
    "courses_audit": "storex",
    "devices_stock": "storex",
    "drivers_sessions": "storex",
    "emails_sessions": "storex",
    "exports_leaderboard": "storex",
    "files_leaderboard": "storex",
    "fleet_audit": "storex",
    "invoices_purge": "storex",
    "loyalty_profiles": "storex",
    "menus_purge": "storex",
    "orders_audit": "storex",
    "partners_audit": "storex",
    "payments_metrics": "storex",
    "playlists_ratelimit": "storex",
    "projects_leaderboard": "storex",
    "recipes_purge": "storex",
    "refunds_flags": "storex",
    "reports_profiles": "storex",
    "returns_ratelimit": "storex",
    "reviews_flags": "storex",
    "rooms_stock": "storex",
    "routes_purge": "storex",
    "search_purge": "storex",
    "shipments_profiles": "storex",
    "surveys_leaderboard": "storex",
    "tasks_audit": "storex",
    "tokens_stock": "storex",
    "users_sessions": "storex",
    "vendors_flags": "storex",
}
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/reports_profiles.py" <<'PYEOF'
"""Reports profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/reports/"
TTL_SECONDS = 900
TTL = timedelta(seconds=TTL_SECONDS)
DEFAULTS = {'timezone': 'eu', 'digest': 'b', 'currency': 'b'}


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/returns_ratelimit.py" <<'PYEOF'
"""Returns rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/returns/"
LIMIT = 7


def hit(user):
    """Count one action. True while the user is within the limit."""
    return store.add(PREFIX + user) <= LIMIT


def reset(user):
    try:
        store.remove(PREFIX + user)
    except Missing:
        pass


def remaining(user):
    try:
        used = store.fetch(PREFIX + user).value
    except Missing:
        used = 0
    return max(0, LIMIT - used)
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/reviews_flags.py" <<'PYEOF'
"""Reviews feature flags."""

from storex import Missing, store

PREFIX = "flag/reviews/"
DEFAULT = False


def enabled(flag):
    try:
        return bool(store.fetch(PREFIX + flag).value)
    except Missing:
        return DEFAULT


def set_flag(flag, on):
    store.put(PREFIX + flag, bool(on))


def toggle(flag):
    now = not enabled(flag)
    set_flag(flag, now)
    return now
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/rooms_stock.py" <<'PYEOF'
"""Rooms stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/rooms/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/routes_purge.py" <<'PYEOF'
"""Routes scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/routes/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/search_purge.py" <<'PYEOF'
"""Search scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/search/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/shipments_profiles.py" <<'PYEOF'
"""Shipments profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/shipments/"
TTL_SECONDS = 43200
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'region': 'on', 'currency': 'c', 'timezone': 'en'}


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/surveys_leaderboard.py" <<'PYEOF'
"""Surveys leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/surveys/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def submit(player, points):
    try:
        best = store.fetch(PREFIX + player).value
    except Missing:
        best = 0
    if points > best:
        store.put(PREFIX + player, points)


def top(n=20):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]


def rank(player):
    """1-based position of the player, or None."""
    order = [name for name, _ in top(10**9)]
    return order.index(player) + 1 if player in order else None
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/tasks_audit.py" <<'PYEOF'
"""Tasks audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/tasks/"
TTL_SECONDS = 43200  # legacy only


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


def record(event_id, payload):
    store.put(PREFIX + event_id, payload)  # audit records never expire


def history():
    """Every payload, in event-id order."""
    return [r.value for r in _all()]


def count():
    return len(_all())
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/tokens_stock.py" <<'PYEOF'
"""Tokens stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/tokens/"


def _all():
    """Every record under PREFIX, across all pages, in key order."""
    records, cursor = [], None
    while True:
        page = store.scan(PREFIX, cursor=cursor)
        records += page.items
        if page.next_cursor is None:
            return records
        cursor = page.next_cursor


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/users_sessions.py" <<'PYEOF'
"""Users sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/users/"
TTL_SECONDS = 7200
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/vendors_flags.py" <<'PYEOF'
"""Vendors feature flags."""

from storex import Missing, store

PREFIX = "flag/vendors/"
DEFAULT = False


def enabled(flag):
    try:
        return bool(store.fetch(PREFIX + flag).value)
    except Missing:
        return DEFAULT


def set_flag(flag, on):
    store.put(PREFIX + flag, bool(on))
PYEOF
