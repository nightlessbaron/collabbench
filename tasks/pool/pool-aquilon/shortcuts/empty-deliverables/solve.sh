#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
mkdir -p "${W}/tools"
: > "${W}/tools/restore_aquilon.py"
mkdir -p "${W}/migration/tcanon"
: > "${W}/migration/tcanon/tcanon.py"
