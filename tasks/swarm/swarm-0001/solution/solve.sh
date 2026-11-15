#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}/."
cat > "${WORKSPACE:-/workspace}/CHANGELOG.md" <<'PYEOF'
# Changelog

## Unreleased

- Migrated acme.alerts_audit to storex.
- Migrated acme.billing_purge to storex.
- Migrated acme.bookings_leaderboard to storex.
- Migrated acme.carts_profiles to storex.
- Migrated acme.catalog_metrics to storex.
- Migrated acme.comments_profiles to storex.
- Migrated acme.coupons_stock to storex.
- Migrated acme.courses_audit to storex.
- Migrated acme.devices_stock to storex.
- Migrated acme.drivers_purge to storex.
- Migrated acme.emails_profiles to storex.
- Migrated acme.exports_purge to storex.
- Migrated acme.files_sessions to storex.
- Migrated acme.fleet_stock to storex.
- Migrated acme.invoices_purge to storex.
- Migrated acme.media_flags to storex.
- Migrated acme.menus_flags to storex.
- Migrated acme.partners_metrics to storex.
- Migrated acme.payments_sessions to storex.
- Migrated acme.playlists_stock to storex.
- Migrated acme.projects_sessions to storex.
- Migrated acme.quotas_audit to storex.
- Migrated acme.recipes_purge to storex.
- Migrated acme.reports_ratelimit to storex.
- Migrated acme.returns_leaderboard to storex.
- Migrated acme.rooms_audit to storex.
- Migrated acme.search_ratelimit to storex.
- Migrated acme.sensors_flags to storex.
- Migrated acme.tasks_stock to storex.
- Migrated acme.teams_metrics to storex.
- Migrated acme.tickets_flags to storex.
- Migrated acme.tokens_purge to storex.
- Migrated acme.vendors_sessions to storex.
- Migrated acme.wallets_purge to storex.
- Migrated acme.webhooks_metrics to storex.

## 2.7.0

- Added cursor pagination to the reports export.
- Fixed a rounding error in invoice totals.
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/alerts_audit.py" <<'PYEOF'
"""Alerts audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/alerts/"
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
cat > "${WORKSPACE:-/workspace}/acme/billing_purge.py" <<'PYEOF'
"""Billing scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/billing/"


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
cat > "${WORKSPACE:-/workspace}/acme/bookings_leaderboard.py" <<'PYEOF'
"""Bookings leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/bookings/"


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/carts_profiles.py" <<'PYEOF'
"""Carts profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/carts/"
TTL_SECONDS = 86400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'region': 'c', 'plan': 'b', 'currency': 'c'}


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
cat > "${WORKSPACE:-/workspace}/acme/catalog_metrics.py" <<'PYEOF'
"""Catalog metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/catalog/"


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
cat > "${WORKSPACE:-/workspace}/acme/comments_profiles.py" <<'PYEOF'
"""Comments profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/comments/"
TTL_SECONDS = 86400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'currency': 'on', 'plan': 'eu', 'digest': 'c'}


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
cat > "${WORKSPACE:-/workspace}/acme/coupons_stock.py" <<'PYEOF'
"""Coupons stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/coupons/"


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
cat > "${WORKSPACE:-/workspace}/acme/courses_audit.py" <<'PYEOF'
"""Courses audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/courses/"
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
cat > "${WORKSPACE:-/workspace}/acme/drivers_purge.py" <<'PYEOF'
"""Drivers scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/drivers/"


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
cat > "${WORKSPACE:-/workspace}/acme/emails_profiles.py" <<'PYEOF'
"""Emails profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/emails/"
TTL_SECONDS = 7200
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'plan': 'eu', 'timezone': 'off', 'locale': 'on'}


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
cat > "${WORKSPACE:-/workspace}/acme/exports_purge.py" <<'PYEOF'
"""Exports scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/exports/"


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
cat > "${WORKSPACE:-/workspace}/acme/files_sessions.py" <<'PYEOF'
"""Files sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/files/"
TTL_SECONDS = 2700
TTL = timedelta(seconds=TTL_SECONDS)


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
cat > "${WORKSPACE:-/workspace}/acme/fleet_stock.py" <<'PYEOF'
"""Fleet stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/fleet/"


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


def low_stock(threshold=15):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
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
cat > "${WORKSPACE:-/workspace}/acme/media_flags.py" <<'PYEOF'
"""Media feature flags."""

from storex import Missing, store

PREFIX = "flag/media/"
DEFAULT = False


def enabled(flag):
    try:
        return bool(store.fetch(PREFIX + flag).value)
    except Missing:
        return DEFAULT


def set_flag(flag, on):
    store.put(PREFIX + flag, bool(on))
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/menus_flags.py" <<'PYEOF'
"""Menus feature flags."""

from storex import Missing, store

PREFIX = "flag/menus/"
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
cat > "${WORKSPACE:-/workspace}/acme/partners_metrics.py" <<'PYEOF'
"""Partners metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/partners/"


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
cat > "${WORKSPACE:-/workspace}/acme/payments_sessions.py" <<'PYEOF'
"""Payments sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/payments/"
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
cat > "${WORKSPACE:-/workspace}/acme/playlists_stock.py" <<'PYEOF'
"""Playlists stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/playlists/"


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
cat > "${WORKSPACE:-/workspace}/acme/projects_sessions.py" <<'PYEOF'
"""Projects sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/projects/"
TTL_SECONDS = 86400
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
cat > "${WORKSPACE:-/workspace}/acme/quotas_audit.py" <<'PYEOF'
"""Quotas audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/quotas/"
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
cat > "${WORKSPACE:-/workspace}/acme/registry.py" <<'PYEOF'
"""Which storage backend each acme module uses. Set a module to "storex" once it is migrated."""

BACKENDS = {
    "alerts_audit": "storex",
    "billing_purge": "storex",
    "bookings_leaderboard": "storex",
    "carts_profiles": "storex",
    "catalog_metrics": "storex",
    "comments_profiles": "storex",
    "coupons_stock": "storex",
    "courses_audit": "storex",
    "devices_stock": "storex",
    "drivers_purge": "storex",
    "emails_profiles": "storex",
    "exports_purge": "storex",
    "files_sessions": "storex",
    "fleet_stock": "storex",
    "invoices_purge": "storex",
    "media_flags": "storex",
    "menus_flags": "storex",
    "partners_metrics": "storex",
    "payments_sessions": "storex",
    "playlists_stock": "storex",
    "projects_sessions": "storex",
    "quotas_audit": "storex",
    "recipes_purge": "storex",
    "reports_ratelimit": "storex",
    "returns_leaderboard": "storex",
    "rooms_audit": "storex",
    "search_ratelimit": "storex",
    "sensors_flags": "storex",
    "tasks_stock": "storex",
    "teams_metrics": "storex",
    "tickets_flags": "storex",
    "tokens_purge": "storex",
    "vendors_sessions": "storex",
    "wallets_purge": "storex",
    "webhooks_metrics": "storex",
}
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/reports_ratelimit.py" <<'PYEOF'
"""Reports rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/reports/"
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
cat > "${WORKSPACE:-/workspace}/acme/returns_leaderboard.py" <<'PYEOF'
"""Returns leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/returns/"


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


def top(n=5):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]


def rank(player):
    """1-based position of the player, or None."""
    order = [name for name, _ in top(10**9)]
    return order.index(player) + 1 if player in order else None
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/rooms_audit.py" <<'PYEOF'
"""Rooms audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/rooms/"
TTL_SECONDS = 600  # legacy only


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
cat > "${WORKSPACE:-/workspace}/acme/search_ratelimit.py" <<'PYEOF'
"""Search rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/search/"
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
cat > "${WORKSPACE:-/workspace}/acme/sensors_flags.py" <<'PYEOF'
"""Sensors feature flags."""

from storex import Missing, store

PREFIX = "flag/sensors/"
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
cat > "${WORKSPACE:-/workspace}/acme/tasks_stock.py" <<'PYEOF'
"""Tasks stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/tasks/"


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
cat > "${WORKSPACE:-/workspace}/acme/teams_metrics.py" <<'PYEOF'
"""Teams metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/teams/"


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
cat > "${WORKSPACE:-/workspace}/acme/tickets_flags.py" <<'PYEOF'
"""Tickets feature flags."""

from storex import Missing, store

PREFIX = "flag/tickets/"
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
cat > "${WORKSPACE:-/workspace}/acme/tokens_purge.py" <<'PYEOF'
"""Tokens scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/tokens/"


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
cat > "${WORKSPACE:-/workspace}/acme/vendors_sessions.py" <<'PYEOF'
"""Vendors sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/vendors/"
TTL_SECONDS = 900
TTL = timedelta(seconds=TTL_SECONDS)


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
cat > "${WORKSPACE:-/workspace}/acme/wallets_purge.py" <<'PYEOF'
"""Wallets scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/wallets/"


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
cat > "${WORKSPACE:-/workspace}/acme/webhooks_metrics.py" <<'PYEOF'
"""Webhooks metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/webhooks/"


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
