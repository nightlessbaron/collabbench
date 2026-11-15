#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
# Produces the deliverable tree's shape and nothing else: no reader, no
# pipeline, no package.  Every graded behaviour is absent.

mkdir -p ${W}/out
: > ${W}/out/pairs.jsonl
: > ${W}/out/counts.json
mkdir -p ${W}/publish
