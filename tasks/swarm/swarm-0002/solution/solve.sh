#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}/."
cat > "${WORKSPACE:-/workspace}/CHANGELOG.md" <<'PYEOF'
# Changelog

## Unreleased

- Migrated acme.alerts_leaderboard to storex.
- Migrated acme.badges_flags to storex.
- Migrated acme.billing_flags to storex.
- Migrated acme.bookings_flags to storex.
- Migrated acme.carts_metrics to storex.
- Migrated acme.comments_ratelimit to storex.
- Migrated acme.coupons_leaderboard to storex.
- Migrated acme.devices_leaderboard to storex.
- Migrated acme.drivers_sessions to storex.
- Migrated acme.emails_leaderboard to storex.
- Migrated acme.exports_leaderboard to storex.
- Migrated acme.files_ratelimit to storex.
- Migrated acme.fleet_ratelimit to storex.
- Migrated acme.loyalty_profiles to storex.
- Migrated acme.media_sessions to storex.
- Migrated acme.menus_stock to storex.
- Migrated acme.orders_purge to storex.
- Migrated acme.partners_audit to storex.
- Migrated acme.payments_metrics to storex.
- Migrated acme.playlists_purge to storex.
- Migrated acme.projects_flags to storex.
- Migrated acme.quotas_stock to storex.
- Migrated acme.recipes_purge to storex.
- Migrated acme.refunds_profiles to storex.
- Migrated acme.reports_metrics to storex.
- Migrated acme.returns_flags to storex.
- Migrated acme.reviews_sessions to storex.
- Migrated acme.rooms_ratelimit to storex.
- Migrated acme.routes_audit to storex.
- Migrated acme.search_ratelimit to storex.
- Migrated acme.sensors_profiles to storex.
- Migrated acme.shipments_stock to storex.
- Migrated acme.surveys_ratelimit to storex.
- Migrated acme.tasks_metrics to storex.
- Migrated acme.teams_flags to storex.
- Migrated acme.tickets_metrics to storex.
- Migrated acme.tokens_metrics to storex.
- Migrated acme.users_flags to storex.
- Migrated acme.vendors_stock to storex.
- Migrated acme.wallets_sessions to storex.

## 2.7.0

- Added cursor pagination to the reports export.
- Fixed a rounding error in invoice totals.
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/alerts_leaderboard.py" <<'PYEOF'
"""Alerts leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/alerts/"


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
cat > "${WORKSPACE:-/workspace}/acme/badges_flags.py" <<'PYEOF'
"""Badges feature flags."""

from storex import Missing, store

PREFIX = "flag/badges/"
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
cat > "${WORKSPACE:-/workspace}/acme/billing_flags.py" <<'PYEOF'
"""Billing feature flags."""

from storex import Missing, store

PREFIX = "flag/billing/"
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
cat > "${WORKSPACE:-/workspace}/acme/bookings_flags.py" <<'PYEOF'
"""Bookings feature flags."""

from storex import Missing, store

PREFIX = "flag/bookings/"
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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/comments_ratelimit.py" <<'PYEOF'
"""Comments rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/comments/"
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
cat > "${WORKSPACE:-/workspace}/acme/coupons_leaderboard.py" <<'PYEOF'
"""Coupons leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/coupons/"


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
cat > "${WORKSPACE:-/workspace}/acme/emails_leaderboard.py" <<'PYEOF'
"""Emails leaderboard: each player's best score."""

from storex import Missing, store

PREFIX = "score/emails/"


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
cat > "${WORKSPACE:-/workspace}/acme/files_ratelimit.py" <<'PYEOF'
"""Files rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/files/"
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
cat > "${WORKSPACE:-/workspace}/acme/fleet_ratelimit.py" <<'PYEOF'
"""Fleet rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/fleet/"
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
cat > "${WORKSPACE:-/workspace}/acme/loyalty_profiles.py" <<'PYEOF'
"""Loyalty profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/loyalty/"
TTL_SECONDS = 600
TTL = timedelta(seconds=TTL_SECONDS)
DEFAULTS = {'locale': 'a', 'currency': 'c', 'digest': 'a'}


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
cat > "${WORKSPACE:-/workspace}/acme/media_sessions.py" <<'PYEOF'
"""Media sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/media/"
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
cat > "${WORKSPACE:-/workspace}/acme/menus_stock.py" <<'PYEOF'
"""Menus stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/menus/"


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
cat > "${WORKSPACE:-/workspace}/acme/orders_purge.py" <<'PYEOF'
"""Orders scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/orders/"


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
cat > "${WORKSPACE:-/workspace}/acme/partners_audit.py" <<'PYEOF'
"""Partners audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/partners/"
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


def reset(metric):
    try:
        store.remove(PREFIX + metric)
    except Missing:
        pass
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/playlists_purge.py" <<'PYEOF'
"""Playlists scratch space, purged in bulk."""

from storex import Missing, store

PREFIX = "tmp/playlists/"


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
cat > "${WORKSPACE:-/workspace}/acme/projects_flags.py" <<'PYEOF'
"""Projects feature flags."""

from storex import Missing, store

PREFIX = "flag/projects/"
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


def low_stock(threshold=40):
    return [r.key[len(PREFIX):] for r in _all() if r.value < threshold]
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
cat > "${WORKSPACE:-/workspace}/acme/refunds_profiles.py" <<'PYEOF'
"""Refunds profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/refunds/"
TTL_SECONDS = 14400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'theme': 'off', 'region': 'b', 'locale': 'c'}


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
cat > "${WORKSPACE:-/workspace}/acme/registry.py" <<'PYEOF'
"""Which storage backend each acme module uses. Set a module to "storex" once it is migrated."""

BACKENDS = {
    "alerts_leaderboard": "storex",
    "badges_flags": "storex",
    "billing_flags": "storex",
    "bookings_flags": "storex",
    "carts_metrics": "storex",
    "comments_ratelimit": "storex",
    "coupons_leaderboard": "storex",
    "devices_leaderboard": "storex",
    "drivers_sessions": "storex",
    "emails_leaderboard": "storex",
    "exports_leaderboard": "storex",
    "files_ratelimit": "storex",
    "fleet_ratelimit": "storex",
    "loyalty_profiles": "storex",
    "media_sessions": "storex",
    "menus_stock": "storex",
    "orders_purge": "storex",
    "partners_audit": "storex",
    "payments_metrics": "storex",
    "playlists_purge": "storex",
    "projects_flags": "storex",
    "quotas_stock": "storex",
    "recipes_purge": "storex",
    "refunds_profiles": "storex",
    "reports_metrics": "storex",
    "returns_flags": "storex",
    "reviews_sessions": "storex",
    "rooms_ratelimit": "storex",
    "routes_audit": "storex",
    "search_ratelimit": "storex",
    "sensors_profiles": "storex",
    "shipments_stock": "storex",
    "surveys_ratelimit": "storex",
    "tasks_metrics": "storex",
    "teams_flags": "storex",
    "tickets_metrics": "storex",
    "tokens_metrics": "storex",
    "users_flags": "storex",
    "vendors_stock": "storex",
    "wallets_sessions": "storex",
}
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/reports_metrics.py" <<'PYEOF'
"""Reports metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/reports/"


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
cat > "${WORKSPACE:-/workspace}/acme/returns_flags.py" <<'PYEOF'
"""Returns feature flags."""

from storex import Missing, store

PREFIX = "flag/returns/"
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
cat > "${WORKSPACE:-/workspace}/acme/reviews_sessions.py" <<'PYEOF'
"""Reviews sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/reviews/"
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
PYEOF
mkdir -p "${WORKSPACE:-/workspace}/acme"
cat > "${WORKSPACE:-/workspace}/acme/rooms_ratelimit.py" <<'PYEOF'
"""Rooms rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/rooms/"
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
cat > "${WORKSPACE:-/workspace}/acme/routes_audit.py" <<'PYEOF'
"""Routes audit log: one record per event."""

from datetime import timedelta  # noqa: F401

from storex import store

PREFIX = "audit/routes/"
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
cat > "${WORKSPACE:-/workspace}/acme/search_ratelimit.py" <<'PYEOF'
"""Search rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/search/"
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
cat > "${WORKSPACE:-/workspace}/acme/sensors_profiles.py" <<'PYEOF'
"""Sensors profiles, merged over defaults."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "profile/sensors/"
TTL_SECONDS = 14400
TTL = min(timedelta(seconds=TTL_SECONDS), timedelta(hours=1))
DEFAULTS = {'currency': 'off', 'theme': 'eu', 'region': 'a'}


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
cat > "${WORKSPACE:-/workspace}/acme/shipments_stock.py" <<'PYEOF'
"""Shipments stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/shipments/"


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
cat > "${WORKSPACE:-/workspace}/acme/surveys_ratelimit.py" <<'PYEOF'
"""Surveys rate limiting: at most LIMIT actions per user."""

from storex import Missing, store

PREFIX = "counter/rate/surveys/"
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
cat > "${WORKSPACE:-/workspace}/acme/tasks_metrics.py" <<'PYEOF'
"""Tasks metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/tasks/"


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
cat > "${WORKSPACE:-/workspace}/acme/teams_flags.py" <<'PYEOF'
"""Teams feature flags."""

from storex import Missing, store

PREFIX = "flag/teams/"
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
cat > "${WORKSPACE:-/workspace}/acme/tickets_metrics.py" <<'PYEOF'
"""Tickets metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/tickets/"


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
cat > "${WORKSPACE:-/workspace}/acme/tokens_metrics.py" <<'PYEOF'
"""Tokens metrics: named counters."""

from storex import Missing, store

PREFIX = "counter/tokens/"


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
cat > "${WORKSPACE:-/workspace}/acme/users_flags.py" <<'PYEOF'
"""Users feature flags."""

from storex import Missing, store

PREFIX = "flag/users/"
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
cat > "${WORKSPACE:-/workspace}/acme/vendors_stock.py" <<'PYEOF'
"""Vendors stock levels, one key per item."""

from storex import Missing, store

PREFIX = "stock/vendors/"


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
cat > "${WORKSPACE:-/workspace}/acme/wallets_sessions.py" <<'PYEOF'
"""Wallets sessions: a cache of signed-in session data."""

from datetime import timedelta

from storex import Missing, store

PREFIX = "session/wallets/"
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
PYEOF
