# The verifier kit

`taskfmt/spec.py` (`write_task`) copies these files into every task it writes: `grade.py`, `pytest_score.py`,
`test.sh` and `hidden_conftest.py` into `tests/`, the Dockerfiles and `tripwire.sh` into their directories, and
`frontier/isolation.py` as `tests/isolation.py`. This README is not copied.

## What a trial's verifier output holds, and who may see it

`grade.py` writes `reward.json` and `details.json` into the verifier's output directory, which Harbor collects under
`runs/`. `details.json` keeps, for every failed hidden test, the first line of its failure message (the exception and
its message; pytest's assertion introspection after it is dropped). That line can still name a hidden expected value,
and the per-requirement results describe the hidden tests.

**Nothing under `runs/` may ever reach an agent**: not a trial's `details.json` or `reward.json`, not a gate log, not
in a feedback, relay or self-improvement loop. Today only `metrics/trial.py` reads `details.json`, and only its
`trace`.

## Isolation layers, and which holds on which platform

A task that names an agent UID (`tests/agent_uid`) runs agent code during grading as that UID; `isolation.py`'s
docstring is the full account. The layers that stop an agent program's output from making the grader read the tests:

| Layer | Linux | gVisor (Modal) |
| --- | --- | --- |
| Tests closed to the agent UID (`lockdown`, checked by `probe` before any agent code) | holds | holds |
| `read_under` reads as the agent UID, in a helper | holds | holds |
| `read_under` walk: lstat each component, then open and match `(st_dev, st_ino)` | holds | holds |
| `O_NOFOLLOW` on each open | holds | not for `O_DIRECTORY` opens before gVisor f667de8e |

Every trial records `nofollow_ok` in `reward.json`. `nofollow_preflight` builds `real/f`, `link -> real` and
`real/flink -> f` in a temp directory (modes set explicitly, whatever the umask). As the agent UID it reads `real/f`,
which must succeed or the trial is a verifier error. It then reads `link/f` and `real/flink`, which the walk itself
must refuse. A timeout or any other failure of those two reads is not a refusal. `nofollow_ok` 0 means the walk was
not shown to refuse a symlink on that platform (`details.json` `preflight.unrefused` says why). It does not void the
trial, since the UID drop still bounds every read, but a gate should report it.

The helpers that act as the agent UID (kill, read, hash) keep a spare real and saved UID (agent UID + 1), so agent
processes cannot signal or trace them. `grade.py` refuses to grade (`verifier_error`, before any agent code) when
that spare UID is privileged, equal to the agent UID, or held by any running process (`isolation.check_spare`).
