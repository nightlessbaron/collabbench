#!/bin/bash
set -euo pipefail
mkdir -p "${WORKSPACE:-/workspace}"
cat > "${WORKSPACE:-/workspace}/plan.json" <<'JSONEOF'
{
 "dwell_minutes": {
  "jobs.example": 14.352496,
  "shop.example": 8.202464,
  "forum.example": 20.465721,
  "wiki.example": 0.0,
  "docs.example": 6.998448,
  "news.example": 2.963306
 }
}
JSONEOF
