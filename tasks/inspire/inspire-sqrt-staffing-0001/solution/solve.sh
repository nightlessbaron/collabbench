#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "agents": {
  "shipping": 50.822723,
  "sales": 9.757981,
  "billing": 15.162145,
  "tech": 30.843217,
  "fraud": 6.654717,
  "returns": 97.559217
 }
}
JSONEOF
