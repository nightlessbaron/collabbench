#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "allocation": {
  "code": 7.08011,
  "web": 0.0,
  "news": 1.145678,
  "books": 0.0,
  "math": 0.850114,
  "legal": 5.293873,
  "dialog": 3.660111,
  "patents": 0.570114
 }
}
JSONEOF
