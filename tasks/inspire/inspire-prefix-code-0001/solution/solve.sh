#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "depth": {
  "messages": 2,
  "lights": 5,
  "translate": 4,
  "shopping": 3,
  "weather": 3,
  "news": 5,
  "traffic": 4,
  "recipes": 4,
  "podcasts": 4,
  "music": 3,
  "timer": 4
 }
}
JSONEOF
