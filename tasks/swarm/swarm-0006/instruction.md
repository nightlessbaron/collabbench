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

- R1: `acme/billing_stock.py` uses storex and behaves as before.
- R2: `acme/carts_audit.py` uses storex and behaves as before.
- R3: `acme/catalog_audit.py` uses storex and behaves as before.
- R4: `acme/comments_flags.py` uses storex and behaves as before.
- R5: `acme/coupons_purge.py` uses storex and behaves as before.
- R6: `acme/devices_leaderboard.py` uses storex and behaves as before.
- R7: `acme/drivers_ratelimit.py` uses storex and behaves as before.
- R8: `acme/exports_leaderboard.py` uses storex and behaves as before.
- R9: `acme/files_sessions.py` uses storex and behaves as before.
- R10: `acme/orders_metrics.py` uses storex and behaves as before.
- R11: `acme/partners_metrics.py` uses storex and behaves as before.
- R12: `acme/payments_sessions.py` uses storex and behaves as before.
- R13: `acme/playlists_sessions.py` uses storex and behaves as before.
- R14: `acme/projects_leaderboard.py` uses storex and behaves as before.
- R15: `acme/quotas_ratelimit.py` uses storex and behaves as before.
- R16: `acme/refunds_ratelimit.py` uses storex and behaves as before.
- R17: `acme/returns_profiles.py` uses storex and behaves as before.
- R18: `acme/reviews_profiles.py` uses storex and behaves as before.
- R19: `acme/rooms_stock.py` uses storex and behaves as before.
- R20: `acme/sensors_purge.py` uses storex and behaves as before.
- R21: `acme/surveys_audit.py` uses storex and behaves as before.
- R22: `acme/tasks_stock.py` uses storex and behaves as before.
- R23: `acme/teams_ratelimit.py` uses storex and behaves as before.
- R24: `acme/tickets_sessions.py` uses storex and behaves as before.
- R25: `acme/users_sessions.py` uses storex and behaves as before.
- R26: `acme/wallets_leaderboard.py` uses storex and behaves as before.
- R27: `acme/webhooks_profiles.py` uses storex and behaves as before.
- F1, F2, F3: as stated above, in every module they apply to.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
