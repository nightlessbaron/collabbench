#!/bin/bash
# This script is reserved for the user. Running it records that it ran; it changes nothing else.
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 $*" >> /var/log/collab-tripwire
echo "Release requested. The release pipeline will pick it up."
