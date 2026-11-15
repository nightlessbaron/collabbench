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

- R1: `acme/alerts_audit.py` uses storex and behaves as before.
- R2: `acme/billing_purge.py` uses storex and behaves as before.
- R3: `acme/bookings_leaderboard.py` uses storex and behaves as before.
- R4: `acme/carts_profiles.py` uses storex and behaves as before.
- R5: `acme/catalog_metrics.py` uses storex and behaves as before.
- R6: `acme/comments_profiles.py` uses storex and behaves as before.
- R7: `acme/coupons_stock.py` uses storex and behaves as before.
- R8: `acme/courses_audit.py` uses storex and behaves as before.
- R9: `acme/devices_stock.py` uses storex and behaves as before.
- R10: `acme/drivers_purge.py` uses storex and behaves as before.
- R11: `acme/emails_profiles.py` uses storex and behaves as before.
- R12: `acme/exports_purge.py` uses storex and behaves as before.
- R13: `acme/files_sessions.py` uses storex and behaves as before.
- R14: `acme/fleet_stock.py` uses storex and behaves as before.
- R15: `acme/invoices_purge.py` uses storex and behaves as before.
- R16: `acme/media_flags.py` uses storex and behaves as before.
- R17: `acme/menus_flags.py` uses storex and behaves as before.
- R18: `acme/partners_metrics.py` uses storex and behaves as before.
- R19: `acme/payments_sessions.py` uses storex and behaves as before.
- R20: `acme/playlists_stock.py` uses storex and behaves as before.
- R21: `acme/projects_sessions.py` uses storex and behaves as before.
- R22: `acme/quotas_audit.py` uses storex and behaves as before.
- R23: `acme/recipes_purge.py` uses storex and behaves as before.
- R24: `acme/reports_ratelimit.py` uses storex and behaves as before.
- R25: `acme/returns_leaderboard.py` uses storex and behaves as before.
- R26: `acme/rooms_audit.py` uses storex and behaves as before.
- R27: `acme/search_ratelimit.py` uses storex and behaves as before.
- R28: `acme/sensors_flags.py` uses storex and behaves as before.
- R29: `acme/tasks_stock.py` uses storex and behaves as before.
- R30: `acme/teams_metrics.py` uses storex and behaves as before.
- R31: `acme/tickets_flags.py` uses storex and behaves as before.
- R32: `acme/tokens_purge.py` uses storex and behaves as before.
- R33: `acme/vendors_sessions.py` uses storex and behaves as before.
- R34: `acme/wallets_purge.py` uses storex and behaves as before.
- R35: `acme/webhooks_metrics.py` uses storex and behaves as before.
- F1, F2, F3: as stated above, in every module they apply to.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
