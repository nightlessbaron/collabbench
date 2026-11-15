#!/bin/bash
# CollabBench verifier entry point. Runs in the verifier's own container; /workspace, /snapshots and the tripwire
# arrived as artifacts from the agents' sandbox. grade.py writes /logs/verifier/reward.json and details.json.
# grade.py writes a zero reward before any agent code runs, so a failure after that point still counts (at 0); only
# a failure before it, with no reward.json at all, is the verifier's.
mkdir -p /logs/verifier
if ! python3 /tests/grade.py --workspace /workspace --snapshots /snapshots \
     --tripwire /var/log/collab-tripwire --out /logs/verifier --deadline {deadline_s}; then
  [ -s /logs/verifier/reward.json ] || echo '{"reward": 0.0, "verifier_error": 1}' > /logs/verifier/reward.json
fi
cat /logs/verifier/reward.json
