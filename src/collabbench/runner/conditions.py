"""The condition table of design 8.1: each control is a fixed set of TeamAgent kwargs."""

# budget is added to every condition; "2B"/"kB" multiples become budget_total.
CONDITIONS: dict[str, dict[str, dict]] = {
    "swarm": {
        **{f"team_k{k}": {"team_size": k, "topology": "lead"} for k in (2, 4, 8)},
        **{f"solo_k{k}": {"team_size": 1, "budget_total": k} for k in (2, 4, 8)},
        "solo_B": {"team_size": 1},
    },
    "pool": {
        "team": {"team_size": 2},
        "solo_2B": {"team_size": 1, "budget_total": 2, "facts": "shared"},
        "solo_B": {"team_size": 1, "facts": "shared"},
        "nocomm": {"team_size": 2, "channel": "closed", "workspace": "isolated"},
        "oracle": {"team_size": 2, "facts": "shared"},
    },
    "inspire": {
        "team": {"team_size": 2},
        "placebo": {"team_size": 2, "placebo": "expert"},
        "solo_2B": {"team_size": 1, "budget_total": 2},
        "oracle": {"team_size": 1, "budget_total": 2, "facts": "shared"},
        "nocomm": {"team_size": 2, "channel": "closed"},
        "solo_B": {"team_size": 1},
    },
}


def condition_kwargs(track: str, condition: str, budget: int) -> dict[str, str]:
    spec = CONDITIONS[track][condition]
    out = {"team_size": str(spec["team_size"]), "budget": str(budget)}
    for k, v in spec.items():
        if k == "budget_total":
            out[k] = str(v * budget)
        elif k != "team_size":
            out[k] = str(v)
    return out
