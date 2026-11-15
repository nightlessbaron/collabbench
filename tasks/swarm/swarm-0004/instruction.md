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

- R1: `acme/badges_stock.py` uses storex and behaves as before.
- R2: `acme/billing_sessions.py` uses storex and behaves as before.
- R3: `acme/carts_metrics.py` uses storex and behaves as before.
- R4: `acme/comments_audit.py` uses storex and behaves as before.
- R5: `acme/coupons_sessions.py` uses storex and behaves as before.
- R6: `acme/courses_ratelimit.py` uses storex and behaves as before.
- R7: `acme/devices_stock.py` uses storex and behaves as before.
- R8: `acme/drivers_metrics.py` uses storex and behaves as before.
- R9: `acme/emails_flags.py` uses storex and behaves as before.
- R10: `acme/exports_metrics.py` uses storex and behaves as before.
- R11: `acme/fleet_sessions.py` uses storex and behaves as before.
- R12: `acme/invoices_audit.py` uses storex and behaves as before.
- R13: `acme/loyalty_profiles.py` uses storex and behaves as before.
- R14: `acme/menus_audit.py` uses storex and behaves as before.
- R15: `acme/orders_metrics.py` uses storex and behaves as before.
- R16: `acme/partners_metrics.py` uses storex and behaves as before.
- R17: `acme/playlists_flags.py` uses storex and behaves as before.
- R18: `acme/projects_stock.py` uses storex and behaves as before.
- R19: `acme/quotas_stock.py` uses storex and behaves as before.
- R20: `acme/refunds_flags.py` uses storex and behaves as before.
- R21: `acme/reports_stock.py` uses storex and behaves as before.
- R22: `acme/returns_sessions.py` uses storex and behaves as before.
- R23: `acme/routes_flags.py` uses storex and behaves as before.
- R24: `acme/search_audit.py` uses storex and behaves as before.
- R25: `acme/sensors_ratelimit.py` uses storex and behaves as before.
- R26: `acme/shipments_profiles.py` uses storex and behaves as before.
- R27: `acme/surveys_audit.py` uses storex and behaves as before.
- R28: `acme/teams_audit.py` uses storex and behaves as before.
- R29: `acme/tickets_leaderboard.py` uses storex and behaves as before.
- R30: `acme/tokens_sessions.py` uses storex and behaves as before.
- R31: `acme/users_flags.py` uses storex and behaves as before.
- R32: `acme/vendors_audit.py` uses storex and behaves as before.
- R33: `acme/wallets_purge.py` uses storex and behaves as before.
- R34: `acme/webhooks_metrics.py` uses storex and behaves as before.
- F1, F2, F3: as stated above, in every module they apply to.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
