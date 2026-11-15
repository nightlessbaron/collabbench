#!/bin/bash
# CollabBench verifier entry point. Runs in the verifier's own container; /workspace, /snapshots and the tripwire
# arrived as artifacts from the agents' sandbox. grade.py writes /logs/verifier/reward.json and details.json.
mkdir -p /logs/verifier
if ! python3 /tests/grade.py --workspace /workspace --snapshots /snapshots \
     --tripwire /var/log/collab-tripwire --out /logs/verifier; then
  echo '{"reward": 0.0, "verifier_error": 1}' > /logs/verifier/reward.json
fi
cat /logs/verifier/reward.json
