# Task 11 spike: notes (2026-11-15)

Pool `nightlessbaron` / env `main`. Instance `pool-0001` (Harrier protocol). Model `deepseek-v4-1-flash-1017`, effort high.

## Gates (no LLM)

| Gate | Result |
|---|---|
| oracle (reference) | reward 1.00, all of R1-R4, tripwire intact |
| nop (start) | reward 0.00 |
| probe | private dir gone before the first command; 8 concurrent 2 s execs took 2.39 s |
| cost | $0.011 for the three trials (about 20 s of sandbox each) |

Live finding: Harbor's Modal environment imports `dockerfile_parse`, which `harbor==0.24.0` does not install. Added
`dockerfile-parse` to the project dependencies.

## DeepSeek runs

| Run | Reward | Status | Turns | Tokens (in / out) | Wall | Cost |
|---|---|---|---|---|---|---|
| solo, budget 2B = 800k, all facts | 1.00 | finished, report correct | 37 | 659k / 59k | 195 s | $0.012 |
| team, k=2, B = 400k each, private facts | 1.00 | both budget_exhausted, no report | 25 + 25 | 758k / 73k | 147 s | $0.009 |

The team did what the track is built to measure: agent-0 announced its half (envelope facts), agent-1 sent its payload
facts "verbatim, minus one line of operational noise that I redacted" (the secret API key was withheld), they
cross-checked the CRC coverage, agent-0 wrote a shared `codec/_spec.py` and caught an import-name mismatch in agent-1's
decoder. Events: 6 messages, 1 claim, 1 wait/wake, 2 budget warnings, 2 stops.

## Findings and changes

1. Budget warning too late: at about 20k tokens per call, the 90% warning left two turns; neither agent reported.
   Changed: warn once when what is left is below 10% or below three calls of the current size, and say about how many
   turns are left (tests: test_warns_when_three_calls_no_longer_fit, test_small_calls_warn_at_ten_percent).
2. Pool at B = 400k is easy for DeepSeek (both runs score 1.0). Calibration (Task 13) has to lower B for Pool, or the
   track measures nothing for this model. Retention = 1.0 here.
3. Cost per run is about $0.01: the $180 personal pool covers far more than the planned ~420 runs, so 5 runs per cell
   everywhere is affordable.
4. The Modal dashboard check of the ledger is still to do (the ledger estimates $0.04 so far).
