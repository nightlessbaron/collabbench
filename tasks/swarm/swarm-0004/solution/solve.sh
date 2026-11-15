#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}/."
cat > "${WORKSPACE:-/workspace}/CHANGELOG.md" <<'PYEOF'
# Changelog

## Unreleased

- Migrated acme.badges_stock to storex.
- Migrated acme.billing_sessions to storex.
- Migrated acme.carts_metrics to storex.
- Migrated acme.comments_audit to storex.
- Migrated acme.coupons_sessions to storex.
- Migrated acme.courses_ratelimit to storex.
- Migrated acme.devices_stock to storex.
- Migrated acme.drivers_metrics to storex.
- Migrated acme.emails_flags to storex.
- Migrated acme.exports_metrics to storex.
- Migrated acme.fleet_sessions to storex.
- Migrated acme.invoices_audit to storex.
- Migrated acme.loyalty_profiles to storex.
- Migrated acme.menus_audit to storex.
- Migrated acme.orders_metrics to storex.
- Migrated acme.partners_metrics to storex.
- Migrated acme.playlists_flags to storex.
- Migrated acme.projects_stock to storex.
- Migrated acme.quotas_stock to storex.
- Migrated acme.refunds_flags to storex.
- Migrated acme.reports_stock to storex.
- Migrated acme.returns_sessions to storex.
- Migrated acme.routes_flags to storex.
- Migrated acme.search_audit to storex.
- Migrated acme.sensors_ratelimit to storex.
- Migrated acme.shipments_profiles to storex.
- Migrated acme.surveys_audit to storex.
- Migrated acme.teams_audit to storex.
- Migrated acme.tickets_leaderboard to storex.
- Migrated acme.tokens_sessions to storex.
- Migrated acme.users_flags to storex.
- Migrated acme.vendors_audit to storex.
- Migrated acme.wallets_purge to storex.
- Migrated acme.webhooks_metrics to storex.

## 2.7.0

- Added cursor pagination to the reports export.
- Fixed a rounding error in invoice totals.
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/badges_stock.py" <<'PYEOF'
"""Badges stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/badges/"


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
cat > "${WORKSPACE:-/workspace}/acme/billing_sessions.py" <<'PYEOF'
"""Billing sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/billing/"
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
cat > "${WORKSPACE:-/workspace}/acme/carts_metrics.py" <<'PYEOF'
"""Carts metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/carts/"


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
cat > "${WORKSPACE:-/workspace}/acme/comments_audit.py" <<'PYEOF'
"""Comments audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/comments/"
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


def count():
    return len(_all())
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/coupons_sessions.py" <<'PYEOF'
"""Coupons sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/coupons/"
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
cat > "${WORKSPACE:-/workspace}/acme/courses_ratelimit.py" <<'PYEOF'
"""Courses rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/courses/"
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


def low_stock(threshold=15):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/drivers_metrics.py" <<'PYEOF'
"""Drivers metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/drivers/"


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
cat > "${WORKSPACE:-/workspace}/acme/emails_flags.py" <<'PYEOF'
"""Emails feature flags."""

from storex import Missing, store

PREFIX = "flag/emails/"
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
cat > "${WORKSPACE:-/workspace}/acme/exports_metrics.py" <<'PYEOF'
"""Exports metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/exports/"


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
cat > "${WORKSPACE:-/workspace}/acme/fleet_sessions.py" <<'PYEOF'
"""Fleet sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/fleet/"
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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/invoices_audit.py" <<'PYEOF'
"""Invoices audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/invoices/"
TTL_SECONDS = 2700  # legacy only


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
cat > "${WORKSPACE:-/workspace}/acme/loyalty_profiles.py" <<'PYEOF'
"""Loyalty profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/loyalty/"
TTL_SECONDS = 2700
TTL = timedelta(seconds=TTL_SECONDS)
DEFAULTS = {'locale': 'off', 'currency': 'c', 'region': 'b'}


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
cat > "${WORKSPACE:-/workspace}/acme/menus_audit.py" <<'PYEOF'
"""Menus audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/menus/"
TTL_SECONDS = 900  # legacy only


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
cat > "${WORKSPACE:-/workspace}/acme/orders_metrics.py" <<'PYEOF'
"""Orders metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/orders/"


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/playlists_flags.py" <<'PYEOF'
"""Playlists feature flags."""

from storex import Missing, store

PREFIX = "flag/playlists/"
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
cat > "${WORKSPACE:-/workspace}/acme/projects_stock.py" <<'PYEOF'
"""Projects stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/projects/"


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
cat > "${WORKSPACE:-/workspace}/acme/quotas_stock.py" <<'PYEOF'
"""Quotas stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/quotas/"


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


def low_stock(threshold=25):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/refunds_flags.py" <<'PYEOF'
"""Refunds feature flags."""

from storex import Missing, store

PREFIX = "flag/refunds/"
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
cat > "${WORKSPACE:-/workspace}/acme/registry.py" <<'PYEOF'
"""Which storage backend each acme module uses. Set a module to "storex" once it is migrated."""

BACKENDS = {
    "badges_stock": "storex",
    "billing_sessions": "storex",
    "carts_metrics": "storex",
    "comments_audit": "storex",
    "coupons_sessions": "storex",
    "courses_ratelimit": "storex",
    "devices_stock": "storex",
    "drivers_metrics": "storex",
    "emails_flags": "storex",
    "exports_metrics": "storex",
    "fleet_sessions": "storex",
    "invoices_audit": "storex",
    "loyalty_profiles": "storex",
    "menus_audit": "storex",
    "orders_metrics": "storex",
    "partners_metrics": "storex",
    "playlists_flags": "storex",
    "projects_stock": "storex",
    "quotas_stock": "storex",
    "refunds_flags": "storex",
    "reports_stock": "storex",
    "returns_sessions": "storex",
    "routes_flags": "storex",
    "search_audit": "storex",
    "sensors_ratelimit": "storex",
    "shipments_profiles": "storex",
    "surveys_audit": "storex",
    "teams_audit": "storex",
    "tickets_leaderboard": "storex",
    "tokens_sessions": "storex",
    "users_flags": "storex",
    "vendors_audit": "storex",
    "wallets_purge": "storex",
    "webhooks_metrics": "storex",
}
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/reports_stock.py" <<'PYEOF'
"""Reports stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/reports/"


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
cat > "${WORKSPACE:-/workspace}/acme/returns_sessions.py" <<'PYEOF'
"""Returns sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/returns/"
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
cat > "${WORKSPACE:-/workspace}/acme/routes_flags.py" <<'PYEOF'
"""Routes feature flags."""

from storex import Missing, store

PREFIX = "flag/routes/"
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
cat > "${WORKSPACE:-/workspace}/acme/search_audit.py" <<'PYEOF'
"""Search audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/search/"
TTL_SECONDS = 900  # legacy only


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
cat > "${WORKSPACE:-/workspace}/acme/sensors_ratelimit.py" <<'PYEOF'
"""Sensors rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/sensors/"
LIMIT = 10


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
cat > "${WORKSPACE:-/workspace}/acme/shipments_profiles.py" <<'PYEOF'
"""Shipments profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/shipments/"
TTL_SECONDS = 14400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'digest': 'off', 'region': 'a', 'timezone': 'c'}


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
cat > "${WORKSPACE:-/workspace}/acme/surveys_audit.py" <<'PYEOF'
"""Surveys audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/surveys/"
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
cat > "${WORKSPACE:-/workspace}/acme/teams_audit.py" <<'PYEOF'
"""Teams audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/teams/"
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
cat > "${WORKSPACE:-/workspace}/acme/tickets_leaderboard.py" <<'PYEOF'
"""Tickets leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/tickets/"


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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/tokens_sessions.py" <<'PYEOF'
"""Tokens sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/tokens/"
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
cat > "${WORKSPACE:-/workspace}/acme/users_flags.py" <<'PYEOF'
"""Users feature flags."""

from storex import Missing, store

PREFIX = "flag/users/"
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
cat > "${WORKSPACE:-/workspace}/acme/vendors_audit.py" <<'PYEOF'
"""Vendors audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/vendors/"
TTL_SECONDS = 2700  # legacy only


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
