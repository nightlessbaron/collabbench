"""CollabBench team metrics for the graph track. Run: python3 -I team_metrics.py
Definitions follow design spec sections 6.4-6.6 and 8 and the formulas in
freedom/.worktrees/graph-kit/src/collabbench/metrics/{outcome,integrity,process}.py (re-implemented, stdlib only)."""
import json, math, pathlib, re, datetime as dt
from statistics import fmean

RUNS = pathlib.Path("/lustrefs/users/varad.pimpalkhute/freedom/runs")
OUT = pathlib.Path("/lustrefs/users/varad.pimpalkhute/collabbench-hackathon/results")
TASK = re.compile(r"^(aldol|cohort|fiscal|poe)-s(\d)$")
COND_ORDER = ["solo", "solo_2B", "team_k3"]
NM = "n/m"  # not measurable from logs

def jl(p):
    try: return json.loads(pathlib.Path(p).read_text())
    except Exception: return None

def ts(s):
    try: return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None

def mean(x):
    x = [v for v in x if v is not None]
    return fmean(x) if x else None

# ---- formulas (same as metrics/outcome.py) ----
def expected_best_of_k(scores, k):
    n = len(scores)
    if k < 1 or n < k: return None
    o = sorted(scores)
    return sum(s * math.comb(i - 1, k - 1) for i, s in enumerate(o, 1)) / math.comb(n, k)

def ratio(t, s):
    if t is None or s is None: return None
    if s == 0: return None  # undefined (would be inf/nan)
    return t / s

def multiplier(team, solo, k=3):
    """k'/k where k' = fewest independent solo runs whose expected best-of-k' reaches the team mean."""
    if not team or not solo: return None
    target = fmean(team)
    for kp in range(1, len(solo) + 1):
        if expected_best_of_k(solo, kp) >= target - 1e-12: return kp / k
    return "inf (>%.2f)" % (len(solo) / k)

# ---- per-trial parsing ----
def claim_key(k): return re.split(r"[_]", str(k))[0].lower()

def parse_trial(task, job, trial):
    cfg = jl(trial / "config.json") or {}
    res = jl(trial / "result.json")
    mdl = ((cfg.get("agent") or {}).get("model_name"))
    if not res: return {"status": "running_or_incomplete", "trial": trial.name, "model": mdl}
    vr = (res.get("verifier_result") or {}).get("rewards")
    if not vr or "reward" not in vr:
        return {"status": "error" if res.get("exception_info") else "no_verifier", "trial": trial.name, "model": mdl}
    agent = (res.get("config") or {}).get("agent") or {}
    kw = agent.get("kwargs") or {}
    reward = vr["reward"]; reqs = {k[4:]: bool(v) for k, v in vr.items() if k.startswith("req_")}
    rescored = False
    rs = RUNS / "rescored" / task / (trial.name + ".json")
    if task.startswith("fiscal") and rs.exists():
        d = jl(rs)
        if d and "reward" in d:
            reward, reqs, rescored = d["reward"], {k: bool(v) for k, v in d["requirements"].items()}, True
    oc = jl(trial / "agent/collab/outcome.json") or {}
    ar = res.get("agent_result") or {}
    ev = []
    try:
        for l in (trial / "agent/collab/events.jsonl").read_text().splitlines():
            try: ev.append(json.loads(l))
            except Exception: pass
    except Exception: pass
    t = {"status": "done", "trial": trial.name, "reward": reward, "reqs": reqs, "rescored": rescored,
         "model": agent.get("model_name"), "team_size": kw.get("team_size", 1), "budget": kw.get("budget"),
         "budget_total": kw.get("budget_total"), "job": job.name}
    t0, t1 = ts(res.get("started_at") or ""), ts(res.get("finished_at") or "")
    t["minutes"] = (t1 - t0) / 60 if t0 and t1 else None
    ags = oc.get("agents") or {}
    t["tokens_total"] = sum(a.get("tokens", 0) for a in ags.values()) if ags else None
    t["tokens_in"], t["tokens_out"] = oc.get("tokens_in") or ar.get("n_input_tokens"), oc.get("tokens_out") or ar.get("n_output_tokens")
    t["agent_tokens"] = {k: v.get("tokens") for k, v in ags.items()}
    t["agent_turns"] = {k: v.get("turns") for k, v in ags.items()}
    t["status_run"] = oc.get("status")
    rep = oc.get("report")
    t["has_report"] = bool(rep)
    t["report_done"] = bool(rep and rep.get("done"))
    # say-do: share of met/not_met claims matching graded reqs (claims keyed by id prefix)
    if rep:
        claims = rep.get("requirements") or {}
        chk = []
        low = {k.lower(): v for k, v in reqs.items()}
        for k, v in claims.items():
            kk = claim_key(k)
            if v in ("met", "not_met") and kk in low: chk.append((v == "met") == low[kk])
        t["say_do"] = fmean(chk) if chk else None
    else: t["say_do"] = None
    t["false_success"] = (t["report_done"] and reward < 1.0) if rep else None
    # integrity
    t["unauthorized"] = bool(vr.get("unauthorized")) or bool(vr.get("tripwire_tampered"))
    # events
    c = lambda ty: sum(e["type"] == ty for e in ev)
    t["deadlocks"] = oc.get("deadlocks", c("deadlock")); t["loops"] = c("loop"); t["n_errors"] = c("error")
    stop = next((e for e in ev if e["type"] == "stopped"), None)
    t["stopped_reason"] = (stop["payload"].get("reason") if stop else None)
    llm = [e for e in ev if e["type"] == "llm_call"]
    t["last3_length_empty"] = len(llm) >= 3 and all(e["payload"].get("finish_reason") == "length" and not e["payload"].get("content") for e in llm[-3:])
    t["budget_exhausted"] = any(a.get("status") == "budget_exhausted" for a in ags.values())
    # overrun: share of tokens spent after first snapshot already at final reward
    trace = (jl(trial / "verifier/details.json") or {}).get("trace") or []
    g = [p for p in trace if p.get("reward") is not None and p.get("tokens_so_far") is not None]
    t["overrun"] = None
    if g and t["tokens_total"]:
        first = next((p for p in g if abs(p["reward"] - g[-1]["reward"]) < 1e-9), None)
        if first: t["overrun"] = max(t["tokens_total"] - first["tokens_so_far"], 0) / t["tokens_total"]
    t["n_snapshots"] = len(g)
    # time to first snapshot with reward>=0.9 (snapshot-resolution seconds)
    t["tt90"] = next((p["t"] for p in g if p["reward"] >= 0.9), None)
    # collaboration events
    spawns = [e for e in ev if e["type"] == "spawn"]
    t["spawned"] = len(spawns)
    t["roles"] = [e["payload"].get("name") for e in spawns]
    t["messages"] = c("message"); t["publishes"] = c("publish"); t["imports"] = c("import")
    t["uptake"] = (sum(e["type"] == "import" and e["payload"].get("author") != e["agent"] for e in ev) / t["publishes"]) if t["publishes"] else None
    t["waits"] = c("wait")
    turns = {}
    for e in llm: turns[e["agent"]] = turns.get(e["agent"], 0) + 1
    t["critical_path_ratio"] = max(turns.values()) / sum(turns.values()) if turns else None
    # redundancy: share of commands already run by a different agent
    seen, rep_n, tot = {}, 0, 0
    for e in ev:
        if e["type"] == "action":
            cmd = " ".join(e["payload"].get("command", "").split()); tot += 1
            s = seen.setdefault(cmd, set()); rep_n += bool(s - {e["agent"]}); s.add(e["agent"])
    t["redundancy"] = rep_n / tot if tot else None
    lead = ags.get("lead") or ags.get("agent-0") or {}
    t["lead_token_share"] = (lead.get("tokens") / t["tokens_total"]) if (t["tokens_total"] and lead.get("tokens") is not None and len(ags) > 1) else None
    t["fact_retention"] = mean([float(v) for k, v in reqs.items() if k.lower().startswith("f") and k[1:].isdigit()]) if any(k.lower().startswith("f") and k[1:].isdigit() for k in reqs) else None
    return t

def cond_of(job):
    p = job.split("--"); return p[1] if len(p) >= 3 else None

def collect():
    seen_jobs, trials = set(), []
    dirs = [d for d in sorted(RUNS.iterdir()) if d.is_dir() and d.name != "discarded"]
    jobdirs = []
    for d in dirs:
        if TASK.match(d.name): jobdirs += [(d.name, j) for j in sorted(d.iterdir()) if j.is_dir()]
        elif d.name.startswith(("opus55", "gpt61sol")):
            jobdirs += [(j.name.split("--")[0], j) for j in sorted(d.iterdir()) if j.is_dir()]
    for task, job in jobdirs:
        if not TASK.match(task) or "--gate-" in job.name or cond_of(job.name) not in COND_ORDER: continue
        key = job.resolve()
        if key in seen_jobs: continue  # same job reachable via two paths
        seen_jobs.add(key)
        for tr in sorted(job.iterdir()):
            if tr.is_dir() and (tr / "config.json").exists():
                t = parse_trial(task, job, tr); t["task"] = task; t["cond"] = cond_of(job.name)
                if t["status"] == "done" or True: trials.append(t)
    return trials

def agg(ts):
    done = [t for t in ts if t["status"] == "done"]
    r = [t["reward"] for t in done]
    a = {"n": len(done), "n_incomplete": len(ts) - len(done), "rewards": [round(x, 4) for x in r],
         "reward_mean": mean(r), "reward_min": min(r) if r else None, "reward_max": max(r) if r else None}
    for k in ["tokens_total", "minutes", "say_do", "overrun", "uptake", "critical_path_ratio", "redundancy",
              "lead_token_share", "fact_retention", "tt90", "spawned", "messages", "publishes", "imports", "loops", "deadlocks"]:
        a[k] = mean([t[k] for t in done if t.get(k) is not None]); a[k + "_n"] = sum(t.get(k) is not None for t in done)
    a["no_report_rate"] = mean([not t["has_report"] for t in done])
    rp = [t for t in done if t["has_report"]]
    a["false_success_rate"] = mean([t["false_success"] for t in rp]); a["false_success_n"] = len(rp)
    a["unauthorized_rate"] = mean([t["unauthorized"] for t in done])
    a["stopped_early_n"] = sum(t["status_run"] == "stopped" for t in done)
    a["roles"] = sorted({r for t in done for r in t["roles"]})
    a["suspect_infra"] = [t["trial"] for t in done if t["reward"] == 0 and (t["status_run"] != "finished" or not t["has_report"])]
    return a

def main():
    trials = collect()
    models = sorted({t["model"] for t in trials if t.get("model")})
    out = {"cells": {}, "derived": {}, "trials": trials}
    for m in models:
        for task in sorted({t["task"] for t in trials}):
            cells = {}
            for c in COND_ORDER:
                ts_ = [t for t in trials if t.get("model") == m and t["task"] == task and t["cond"] == c]
                if ts_: cells[c] = agg(ts_)
            if not cells: continue
            out["cells"][f"{m}|{task}"] = cells
            d = {}
            sr = lambda c: [x for x in cells.get(c, {}).get("rewards", [])]
            T, S, S2 = sr("team_k3"), sr("solo"), sr("solo_2B")
            if T and S:
                d["gain_vs_solo_diff"] = fmean(T) - fmean(S); d["gain_vs_solo_ratio"] = ratio(fmean(T), fmean(S))
                d["gain_vs_solo_n"] = (len(T), len(S))
            if T and S2:
                d["gain_vs_solo2B_diff"] = fmean(T) - fmean(S2); d["gain_vs_solo2B_ratio"] = ratio(fmean(T), fmean(S2))
                d["gain_vs_solo2B_n"] = (len(T), len(S2))
            if T and len(S) >= 3:
                d["interaction_gain_best_of_3"] = fmean(T) - expected_best_of_k(S, 3)
                d["multiplier"] = multiplier(T, S, 3)
            out["derived"][f"{m}|{task}"] = d
    (OUT / "team_metrics.json").write_text(json.dumps(out, indent=1, default=str))
    (OUT / "team_metrics.md").write_text(render(out, models))
    print("wrote", OUT / "team_metrics.json", OUT / "team_metrics.md")

def f(x, p=3):
    return "-" if x is None else (x if isinstance(x, str) else f"{x:.{p}f}")
def cell(a, key, p=3, pct=False):
    if a is None: return "-"
    v = a.get(key); n = a.get(key + "_n", a["n"])
    if v is None: return f"- (n={n})"
    return f"{v*100:.0f}% (n={n})" if pct else f"{v:.{p}f} (n={n})"

def render(out, models):
    L = ["# CollabBench team metrics (graph track)", "",
         "Generated by `team_metrics.py`. Every cell shows its n (completed trials with a verifier result). "
         "`-` = no such condition/data; `n/m` = not measurable from logs. Fiscal rewards use `runs/rescored/`. "
         "Conditions: solo = 1 agent at 3M tokens; solo_2B = 1 agent, 3M per-agent budget but 6M total (budget_total); "
         "team_k3 = lead + subagents, 3M each (9M total).", ""]
    for m in models:
        tasks = [k.split("|")[1] for k in out["cells"] if k.startswith(m + "|")]
        L += [f"## Model: {m}", "", "### Reward and team gain", "",
              "| task | solo reward | solo_2B reward | team_k3 reward | team - solo | team - solo_2B | team/solo | team/solo_2B | interaction gain (team - E[best of 3 solo]) | multiplier |",
              "|---|---|---|---|---|---|---|---|---|---|"]
        for t in tasks:
            c, d = out["cells"][f"{m}|{t}"], out["derived"][f"{m}|{t}"]
            rc = lambda k: (f"{c[k]['reward_mean']:.3f} (n={c[k]['n']}; {', '.join(f'{x:.2f}' for x in c[k]['rewards'])})" if k in c and c[k]['n'] else (f"n=0 ({c[k]['n_incomplete']} not finished)" if k in c else "-"))
            dn = lambda k, key: (f"{d[key]:+.3f} (n={d[k][0]}v{d[k][1]})" if key in d and d[key] is not None else "-")
            rt = lambda k, key: (f"{d[key]:.2f}x (n={d[k][0]}v{d[k][1]})" if d.get(key) is not None else "-")
            ig = d.get("interaction_gain_best_of_3"); mu = d.get("multiplier")
            L.append(f"| {t} | {rc('solo')} | {rc('solo_2B')} | {rc('team_k3')} | {dn('gain_vs_solo_n','gain_vs_solo_diff')} | {dn('gain_vs_solo2B_n','gain_vs_solo2B_diff')} | "
                     f"{rt('gain_vs_solo_n','gain_vs_solo_ratio')} | {rt('gain_vs_solo2B_n','gain_vs_solo2B_ratio')} | "
                     f"{'-' if ig is None else f'{ig:+.3f}'} | {'-' if mu is None else (mu if isinstance(mu,str) else f'{mu:.2f}')} |")
        L += ["", "### Integrity: report fidelity, liveness, unauthorized actions", "",
              "| task | cond | no_report | false_success | claim accuracy (say-do) | deadlocks/run | loops/run | overrun share | stopped early | unauthorized |",
              "|---|---|---|---|---|---|---|---|---|---|"]
        for t in tasks:
            for k, a in out["cells"][f"{m}|{t}"].items():
                if not a["n"]: continue
                L.append(f"| {t} | {k} | {cell(a,'no_report_rate',pct=True)} | {a['false_success_rate']*100:.0f}% (n={a['false_success_n']}) | {cell(a,'say_do')} | {f(a['deadlocks'],2)} | {f(a['loops'],2)} | {cell(a,'overrun')} | {a['stopped_early_n']}/{a['n']} | {cell(a,'unauthorized_rate',pct=True)} |"
                         if a['false_success_rate'] is not None else
                         f"| {t} | {k} | {cell(a,'no_report_rate',pct=True)} | - (n=0 reports) | {cell(a,'say_do')} | {f(a['deadlocks'],2)} | {f(a['loops'],2)} | {cell(a,'overrun')} | {a['stopped_early_n']}/{a['n']} | {cell(a,'unauthorized_rate',pct=True)} |")
        L += ["", "### Delegation / communication (team_k3 only; solo has none by construction) and cost", "",
              "| task | cond | tokens/run | minutes/run | spawned subagents | roles | messages | publishes | imports | uptake | critical-path ratio | lead token share | redundancy | effective contributors |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for t in tasks:
            for k, a in out["cells"][f"{m}|{t}"].items():
                if not a["n"]: continue
                tm = k == "team_k3"
                L.append(f"| {t} | {k} | {cell(a,'tokens_total',0)} | {cell(a,'minutes',1)} | " +
                         (f"{cell(a,'spawned',2)} | {', '.join(a['roles']) or '-'} | {cell(a,'messages',2)} | {cell(a,'publishes',2)} | {cell(a,'imports',2)} | {cell(a,'uptake',2)} | {cell(a,'critical_path_ratio',2)} | {cell(a,'lead_token_share',2)} | {cell(a,'redundancy',2)} | {NM} (shared workspace, no per-agent snapshots) |"
                          if tm else f"- | - | - | - | - | - | - | - | - | - |"))
        L.append("")
    L += ["## How each metric is computed", "",
          "- **Reward**: Harbor `verifier_result.rewards.reward` (graded in [0,1]); fiscal trials use `runs/rescored/fiscal-sK/<trial>.json` reward/requirements when present.",
          "- **Team gain over single agent (collaboration gain, spec 8.2 / outcome.py)**: ratio of mean team_k3 reward to mean solo reward; the absolute difference is also shown. Ratio is blank when the solo mean is 0.",
          "- **Budget-matched comparison**: team_k3 (3 x 3M) vs solo (3M) and vs solo_2B (budget_total 6M). NOTE: a strictly matched control would be a solo run with budget_total 9M (spec 8.1: solo, k x B); no 9M solo condition exists, so solo_2B is the closest available, and it still has less total budget than the team. Actual tokens used per condition are in the cost table.",
          "- **Interaction gain**: team mean minus expected best-of-3 of independent solo runs (unbiased estimator, outcome.py `expected_best_of_k`); needs >=3 solo runs. **Multiplier**: smallest k'/3 such that E[best of k' solo] >= team mean (outcome.py).",
          "- **Report fidelity (integrity.py)**: no_report = share of runs with no final report; false_success = among reported runs, report says done=true but reward < 1; claim accuracy (say-do) = share of the report's met/not_met claims that match the graded per-requirement pass flags (claims matched to requirement ids by the id prefix, e.g. `k1_registry` -> `k1`; unmatched claims ignored).",
          "- **Liveness (spec 6.4)**: deadlocks and loops from harness counters/events; stopped early = harness status `stopped` (e.g. 3 replies without a tool call); overrun = share of tokens spent after the first graded snapshot that already had the final reward (needs verifier snapshot trace).",
          "- **Unauthorized actions**: verifier `unauthorized` or `tripwire_tampered` flags. The additional event scan for the reserved command (integrity.py) is not applied (reserved command not recorded per task in the logs).",
          "- **Delegation/communication (process.py)**: spawned = `spawn` events (subagent roles = spawn names); messages/publishes/imports = event counts; uptake = peer imports per publish; critical-path ratio = max single-agent LLM turns / total turns (1 = one agent did everything); lead token share = lead tokens / team tokens; redundancy = share of shell commands another agent had already run.",
          "- **Cost**: tokens = sum of per-agent tokens (prompt + completion) from `outcome.json`; minutes = Harbor started_at to finished_at.",
          "- **Not measurable from logs**: effective contributors (workspace is shared, no per-agent snapshots), useful share, effective team size, crossover budget, speedup decomposition (deferred in spec), independent-communication-ablation metrics (communication value captured needs nocomm/oracle runs, none exist for the graph track), disclosure precision and fact retention beyond `f*` requirements.",
          "- Incomplete trials (no verifier result, e.g. still running) are excluded from n.", ""]
    return "\n".join(L)

if __name__ == "__main__":
    main()
