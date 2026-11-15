#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "allocation": {
  "code": 4.824,
  "web": 0.0,
  "news": 4.904,
  "books": 1.594,
  "math": 0.0,
  "legal": 5.874,
  "dialog": 1.404,
  "patents": 0.0
 }
}
JSONEOF
