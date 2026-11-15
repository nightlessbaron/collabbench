"""TeamSettings: every condition of a run, set through Harbor's `--ak key=value` agent kwargs (design 6.1)."""

from dataclasses import dataclass, fields
from typing import Any

_CHOICES = {
    "topology": {"lead", "peers"},
    "channel": {"open", "closed"},
    "facts": {"private", "shared"},
    "workspace": {None, "shared", "worktrees", "isolated"},
    "effort": {None, "low", "high", "max"},
}
_NONE = {None, "", "none", "None", "null"}


@dataclass(frozen=True)
class TeamSettings:
    team_size: int = 1  # 1 is a solo agent
    topology: str = "peers"  # "lead": agent 0 sees the brief and spawns up to team_size - 1 subagents
    budget: int = 400_000  # tokens per agent: prompt + completion over all calls
    budget_total: int | None = None  # default team_size * budget; the solo matched control sets it
    channel: str = "open"  # "closed": no send, wait, publish, read_finding
    facts: str = "private"  # "shared": every agent gets every role's private context
    placebo: str | None = None  # a role whose context is swapped for its placebo
    workspace: str | None = None  # None: the task's default (manifest)
    context_cap: int | None = None  # None: the model's full window; compaction only past 1M tokens
    effort: str | None = "high"  # DeepSeek reasoning effort
    max_turns: int = 400
    evaluate_cap: int = 12
    snapshot_every_s: int = 180
    max_snapshots: int = 24
    idle_grace_s: int = 60
    probe: bool = False  # setup only, then sandbox checks; no LLM

    def __post_init__(self) -> None:
        for name, allowed in _CHOICES.items():
            if getattr(self, name) not in allowed:
                raise ValueError(f"{name}={getattr(self, name)!r}; expected one of {sorted(map(str, allowed))}")
        if self.team_size < 1:
            raise ValueError("team_size must be >= 1")
        if self.topology == "lead" and self.team_size < 2:
            raise ValueError("topology=lead needs team_size >= 2 (a solo run uses peers)")
        if self.workspace == "isolated" and self.channel != "closed":
            raise ValueError("workspace=isolated is the no-communication control: it needs channel=closed")

    @classmethod
    def from_kwargs(cls, kw: dict[str, Any]) -> "TeamSettings":
        """Build from Harbor agent kwargs. Values may be strings ("4", "none", "true") or already typed."""
        types = {f.name: f.type for f in fields(cls)}
        unknown = set(kw) - set(types)
        if unknown:
            raise ValueError(f"unknown team settings {sorted(unknown)}; known: {sorted(types)}")
        return cls(**{k: _cast(v, types[k]) for k, v in kw.items()})

    def pool_total(self) -> int:
        return self.budget_total or self.team_size * self.budget

    def solo_budget(self) -> int:
        return self.budget_total or self.budget


def _cast(value: Any, type_: Any) -> Any:
    text = str(type_)
    optional = "None" in text
    if optional and value in _NONE:
        return None
    if text.startswith("bool") or type_ is bool:
        return value if isinstance(value, bool) else str(value).lower() in {"1", "true", "yes"}
    if text.startswith("int") or type_ is int:
        return int(value)
    return value if isinstance(value, str) or value is None else str(value)
