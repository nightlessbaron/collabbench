#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "markup": {
  "storage": 0.11563,
  "exports": 0.067065,
  "seats": 0.145794,
  "sso": 0.060419,
  "analytics": 0.038766,
  "api_calls": 0.181258,
  "domains": 0.024211
 }
}
JSONEOF
