"""The poe graph's scoring rule, pure and standard-library only (build.py ships this file into the task's tests/ as
units_score.py, so it must not import anything from collabbench).

hidden/units.json (written by pin.py from the gate runs):
    {"units": {"u05": {"a": [test key, ...], "b": [...]}, ...},   scored units: pinned tests, by origin
     "gate_only": ["u01", ...],                                   units with no pinned test: graded by the gate alone
     "regression": [test key, ...],                               tests that pass on the start and on the reference
     "regression_min": 0.98}

Reward: the mean over the scored units of the pass rate of the unit's pinned tests, gated on the suite not regressing:
if fewer than `regression_min` of the regression tests pass the reward is 0. A gate-only unit is not in the mean; its
`req_<unit>` is the regression gate itself (so an empty change does not look like a failure, and a change that
breaks the suite does).
"""

REGRESSION_MIN = 0.98


def pinned(unit: dict) -> list[str]:
    return list(unit.get("a", [])) + [t for t in unit.get("b", []) if t not in unit.get("a", [])]


def score_units(tests: dict[str, bool], units: dict) -> dict:
    """{"reward", "requirements", "extras"} from the pinned tests' outcomes (a missing test counts as failed)."""
    rates, requirements, extras = {}, {}, {}
    for uid, unit in units["units"].items():
        keys = pinned(unit)
        passed = sum(bool(tests.get(k, False)) for k in keys)
        rates[uid] = passed / len(keys) if keys else 0.0
        requirements[uid] = bool(keys) and passed == len(keys)
        extras[f"unit_{uid}"] = rates[uid]
    regression = units.get("regression", [])
    reg_rate = (sum(bool(tests.get(k, False)) for k in regression) / len(regression)) if regression else 1.0
    gate_ok = reg_rate >= units.get("regression_min", REGRESSION_MIN)
    for uid in units.get("gate_only", []):
        requirements[uid] = gate_ok
    mean = sum(rates.values()) / len(rates) if rates else 0.0
    extras.update(regression_rate=reg_rate, regression_ok=1.0 if gate_ok else 0.0, units_scored=float(len(rates)),
                  units_gate_only=float(len(units.get("gate_only", []))), unit_mean=mean)
    return {"reward": mean if gate_ok else 0.0, "requirements": requirements, "extras": extras}
