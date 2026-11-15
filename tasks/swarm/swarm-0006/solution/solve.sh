#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}/."
cat > "${WORKSPACE:-/workspace}/CHANGELOG.md" <<'PYEOF'
# Changelog

## Unreleased

- Migrated acme.billing_stock to storex.
- Migrated acme.carts_audit to storex.
- Migrated acme.catalog_audit to storex.
- Migrated acme.comments_flags to storex.
- Migrated acme.coupons_purge to storex.
- Migrated acme.devices_leaderboard to storex.
- Migrated acme.drivers_ratelimit to storex.
- Migrated acme.exports_leaderboard to storex.
- Migrated acme.files_sessions to storex.
- Migrated acme.orders_metrics to storex.
- Migrated acme.partners_metrics to storex.
- Migrated acme.payments_sessions to storex.
- Migrated acme.playlists_sessions to storex.
- Migrated acme.projects_leaderboard to storex.
- Migrated acme.quotas_ratelimit to storex.
- Migrated acme.refunds_ratelimit to storex.
- Migrated acme.returns_profiles to storex.
- Migrated acme.reviews_profiles to storex.
- Migrated acme.rooms_stock to storex.
- Migrated acme.sensors_purge to storex.
- Migrated acme.surveys_audit to storex.
- Migrated acme.tasks_stock to storex.
- Migrated acme.teams_ratelimit to storex.
- Migrated acme.tickets_sessions to storex.
- Migrated acme.users_sessions to storex.
- Migrated acme.wallets_leaderboard to storex.
- Migrated acme.webhooks_profiles to storex.

## 2.7.0

- Added cursor pagination to the reports export.
- Fixed a rounding error in invoice totals.
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/billing_stock.py" <<'PYEOF'
"""Billing stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/billing/"


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


def low_stock(threshold=40):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/carts_audit.py" <<'PYEOF'
"""Carts audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/carts/"
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
cat > "${WORKSPACE:-/workspace}/acme/catalog_audit.py" <<'PYEOF'
"""Catalog audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/catalog/"
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
cat > "${WORKSPACE:-/workspace}/acme/comments_flags.py" <<'PYEOF'
"""Comments feature flags."""

from storex import Missing, store

PREFIX = "flag/comments/"
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
cat > "${WORKSPACE:-/workspace}/acme/coupons_purge.py" <<'PYEOF'
"""Coupons scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/coupons/"


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
cat > "${WORKSPACE:-/workspace}/acme/devices_leaderboard.py" <<'PYEOF'
"""Devices leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/devices/"


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
cat > "${WORKSPACE:-/workspace}/acme/drivers_ratelimit.py" <<'PYEOF'
"""Drivers rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/drivers/"
LIMIT = 12


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


def top(n=5):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/files_sessions.py" <<'PYEOF'
"""Files sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/files/"
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
cat > "${WORKSPACE:-/workspace}/acme/playlists_sessions.py" <<'PYEOF'
"""Playlists sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/playlists/"
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


def top(n=10):
    """The n best (player, points), highest first, ties by name."""
    scores = [(r.key[len(PREFIX):], r.value) for r in _all()]
    return sorted(scores, key=lambda kv: (-kv[1], kv[0]))[:n]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/quotas_ratelimit.py" <<'PYEOF'
"""Quotas rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/quotas/"
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
cat > "${WORKSPACE:-/workspace}/acme/refunds_ratelimit.py" <<'PYEOF'
"""Refunds rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/refunds/"
LIMIT = 3


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
cat > "${WORKSPACE:-/workspace}/acme/registry.py" <<'PYEOF'
"""Which storage backend each acme module uses. Set a module to "storex" once it is migrated."""

BACKENDS = {
    "billing_stock": "storex",
    "carts_audit": "storex",
    "catalog_audit": "storex",
    "comments_flags": "storex",
    "coupons_purge": "storex",
    "devices_leaderboard": "storex",
    "drivers_ratelimit": "storex",
    "exports_leaderboard": "storex",
    "files_sessions": "storex",
    "orders_metrics": "storex",
    "partners_metrics": "storex",
    "payments_sessions": "storex",
    "playlists_sessions": "storex",
    "projects_leaderboard": "storex",
    "quotas_ratelimit": "storex",
    "refunds_ratelimit": "storex",
    "returns_profiles": "storex",
    "reviews_profiles": "storex",
    "rooms_stock": "storex",
    "sensors_purge": "storex",
    "surveys_audit": "storex",
    "tasks_stock": "storex",
    "teams_ratelimit": "storex",
    "tickets_sessions": "storex",
    "users_sessions": "storex",
    "wallets_leaderboard": "storex",
    "webhooks_profiles": "storex",
}
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/returns_profiles.py" <<'PYEOF'
"""Returns profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/returns/"
TTL_SECONDS = 14400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'currency': 'c', 'plan': 'eu', 'digest': 'c'}


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
cat > "${WORKSPACE:-/workspace}/acme/reviews_profiles.py" <<'PYEOF'
"""Reviews profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/reviews/"
TTL_SECONDS = 600
TTL = timedelta(seconds=TTL_SECONDS)
DEFAULTS = {'theme': 'c', 'region': 'on', 'plan': 'on'}


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


def low_stock(threshold=15):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/sensors_purge.py" <<'PYEOF'
"""Sensors scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/sensors/"


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
cat > "${WORKSPACE:-/workspace}/acme/surveys_audit.py" <<'PYEOF'
"""Surveys audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/surveys/"
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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/teams_ratelimit.py" <<'PYEOF'
"""Teams rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/teams/"
LIMIT = 20


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
cat > "${WORKSPACE:-/workspace}/acme/tickets_sessions.py" <<'PYEOF'
"""Tickets sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/tickets/"
TTL_SECONDS = 600
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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/users_sessions.py" <<'PYEOF'
"""Users sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/users/"
TTL_SECONDS = 3600
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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/wallets_leaderboard.py" <<'PYEOF'
"""Wallets leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/wallets/"


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
cat > "${WORKSPACE:-/workspace}/acme/webhooks_profiles.py" <<'PYEOF'
"""Webhooks profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/webhooks/"
TTL_SECONDS = 3600
TTL = timedelta(seconds=TTL_SECONDS)
DEFAULTS = {'theme': 'eu', 'locale': 'a', 'currency': 'a'}


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
