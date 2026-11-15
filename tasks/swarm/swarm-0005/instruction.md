# Move acme off legacy.storage

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

- R1: `acme/alerts_flags.py` uses storex and behaves as before.
- R2: `acme/billing_ratelimit.py` uses storex and behaves as before.
- R3: `acme/bookings_flags.py` uses storex and behaves as before.
- R4: `acme/carts_profiles.py` uses storex and behaves as before.
- R5: `acme/catalog_sessions.py` uses storex and behaves as before.
- R6: `acme/comments_profiles.py` uses storex and behaves as before.
- R7: `acme/coupons_leaderboard.py` uses storex and behaves as before.
- R8: `acme/devices_sessions.py` uses storex and behaves as before.
- R9: `acme/drivers_ratelimit.py` uses storex and behaves as before.
- R10: `acme/emails_stock.py` uses storex and behaves as before.
- R11: `acme/exports_audit.py` uses storex and behaves as before.
- R12: `acme/files_audit.py` uses storex and behaves as before.
- R13: `acme/invoices_ratelimit.py` uses storex and behaves as before.
- R14: `acme/loyalty_stock.py` uses storex and behaves as before.
- R15: `acme/media_metrics.py` uses storex and behaves as before.
- R16: `acme/menus_purge.py` uses storex and behaves as before.
- R17: `acme/orders_audit.py` uses storex and behaves as before.
- R18: `acme/partners_profiles.py` uses storex and behaves as before.
- R19: `acme/payments_ratelimit.py` uses storex and behaves as before.
- R20: `acme/playlists_leaderboard.py` uses storex and behaves as before.
- R21: `acme/projects_stock.py` uses storex and behaves as before.
- R22: `acme/quotas_leaderboard.py` uses storex and behaves as before.
- R23: `acme/recipes_flags.py` uses storex and behaves as before.
- R24: `acme/refunds_ratelimit.py` uses storex and behaves as before.
- R25: `acme/reports_ratelimit.py` uses storex and behaves as before.
- R26: `acme/returns_stock.py` uses storex and behaves as before.
- R27: `acme/reviews_metrics.py` uses storex and behaves as before.
- R28: `acme/rooms_sessions.py` uses storex and behaves as before.
- R29: `acme/routes_stock.py` uses storex and behaves as before.
- R30: `acme/search_leaderboard.py` uses storex and behaves as before.
- R31: `acme/sensors_flags.py` uses storex and behaves as before.
- R32: `acme/shipments_flags.py` uses storex and behaves as before.
- R33: `acme/tasks_purge.py` uses storex and behaves as before.
- R34: `acme/teams_ratelimit.py` uses storex and behaves as before.
- R35: `acme/tickets_sessions.py` uses storex and behaves as before.
- R36: `acme/tokens_flags.py` uses storex and behaves as before.
- R37: `acme/users_flags.py` uses storex and behaves as before.
- R38: `acme/vendors_flags.py` uses storex and behaves as before.
- R39: `acme/wallets_metrics.py` uses storex and behaves as before.
- F1, F2, F3: as stated above, in every module they apply to.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
