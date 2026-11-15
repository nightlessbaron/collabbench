#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
mkdir -p "${W}/."
: > "${W}/pressproof.py"
