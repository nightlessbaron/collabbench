#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "stake_share": {
  "onboarding": 0.378596,
  "support": 0.386209,
  "search": 0.317951,
  "pricing": 0.306644,
  "checkout": 0.0,
  "ads": 0.0
 }
}
JSONEOF
