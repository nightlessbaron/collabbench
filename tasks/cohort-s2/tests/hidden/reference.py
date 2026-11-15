"""Reference for the cohort graph (Olmsted County free light chain cohort). Stage 1 (levels 1 to 3): c1 c2 c3 c4 c5 c6 c7 c8 s1 m0 v0 R1.

One pure function per node: node_<id>(up, src) -> JSON-able output. `src` is the source directory (the graph's assets
directory, or a workspace with the same layout: data/flchain.csv). Standard library and numpy.
CLI: python reference.py <src_dir> <out_dir> --stage S   writes every implemented node of level <= S.

The decisions the reference takes (graph.json "decisions" carries the question, both answers and the source):
  Q1  FLC groups: the published `flc_group` column (not deciles recomputed from the 7,874 records).
  Q2  Zero follow-up: the three records with followup_days 0 are out of the analysis cohort.
  Q3  Missing creatinine: complete-case is the main analysis (the model cohort is the analysis cohort with creatinine
      recorded); inverse-probability weights are for the sensitivity reruns.
Conventions (graph.json facts): a year is 365.25 days; a person died iff cause_chapter is filled; enrolment is at exact
age `age` and calendar time sample_year + 0.5 (the file has no dates).
"""

import csv
import json
import sys
import types
from pathlib import Path

import numpy as np

DECISIONS = {"Q1": "published", "Q2": "exclude_zero_followup", "Q3": "complete_case"}
YEAR = 365.25
BANDS = [("50-59", 50, 59), ("60-69", 60, 69), ("70-79", 70, 79), ("80+", 80, 200)]
CAUSES = ["Circulatory", "Neoplasms", "Respiratory", "Other"]
ENTRY_OFFSET = 0.5
AGE_BAND_WIDTH = 5
TOP_AGE_BAND = 100
YEARS = list(range(1995, 2004))
TIERS = [("low", 1, 3), ("mid", 4, 7), ("high", 8, 10)]


def load(src):
    """Rows of data/flchain.csv as dicts; `dead` is the cause field being filled (there is no status column)."""
    rows = []
    with open(Path(src) / "data" / "flchain.csv", newline="") as f:
        for r in csv.DictReader(f):
            cause = r["cause_chapter"].strip()
            rows.append({"id": int(r["id"]), "age": int(r["age"]), "sex": r["sex"], "year": int(r["sample_year"]),
                         "kappa": float(r["kappa"]), "lambda": float(r["lambda"]), "group": int(r["flc_group"]),
                         "days": int(r["followup_days"]), "cause": cause, "dead": bool(cause),
                         "creat": float(r["creatinine"]) if r["creatinine"].strip() else None, "mgus": int(r["mgus"])})
    return rows


def node_c1(up, src):
    rows = load(src)
    excluded = [r for r in rows if r["days"] == 0]
    by_year = {}
    for y in YEARS:
        ys = [r for r in rows if r["year"] == y]
        z = sum(1 for r in ys if r["days"] == 0)
        by_year[str(y)] = {"n_records": len(ys), "n_zero_followup": z, "n_analysis": len(ys) - z}
    return {"n_records": len(rows), "n_analysis": len(rows) - len(excluded),
            "excluded": [{"id": r["id"], "reason": "zero_followup"} for r in excluded], "by_year": by_year}


def quantile7(xs, p):
    """Linear-interpolation quantile (the numpy default, type 7)."""
    s = sorted(xs)
    h = (len(s) - 1) * p
    lo = int(h)
    return s[lo] + (h - lo) * (s[min(lo + 1, len(s) - 1)] - s[lo])


def recomputed_deciles(sums):
    """Group 1..10 from the nine decile cut points of these records: group = 1 + number of cuts strictly below."""
    cuts = [quantile7(sums, k / 10) for k in range(1, 10)]
    return [1 + sum(1 for c in cuts if v > c) for v in sums]


def tier_of(group):
    return next(name for name, lo, hi in TIERS if lo <= group <= hi)


def node_c3(up, src, decision=None):
    rows = load(src)
    sums = [round(r["kappa"] + r["lambda"], 3) for r in rows]
    groups = recomputed_deciles(sums) if (decision or DECISIONS["Q1"]) == "recomputed" else [r["group"] for r in rows]
    persons = {str(r["id"]): {"flc_sum": s, "flc_ratio": round(r["kappa"] / r["lambda"], 4), "decile": g,
                              "tier": tier_of(g)} for r, s, g in zip(rows, sums, groups)}
    return {"persons": persons, "summary": {
        "decile_n": [sum(1 for g in groups if g == k) for k in range(1, 11)],
        "tier_n": {name: sum(1 for g in groups if lo <= g <= hi) for name, lo, hi in TIERS},
        "decile_min_sum": [min(s for s, g in zip(sums, groups) if g == k) for k in range(1, 11)],
        "n_kappa_dominant": sum(1 for r in rows if r["kappa"] > r["lambda"])}}




# ---- helpers ------------------------------------------------------------------------------------------------------

def analysis_rows(up, src):
    """The analysis cohort, from whichever upstream output the node reads (c1's exclusions, or a person table)."""
    if "c1" in up:
        excluded = {e["id"] for e in up["c1"]["excluded"]}
        return [r for r in load(src) if r["id"] not in excluded]
    ids = {int(i) for i in (up.get("c4") or up["c2"])["persons"]}
    return [r for r in load(src) if r["id"] in ids]


def band_of(age):
    return next(name for name, lo, hi in BANDS if lo <= age <= hi)


def product_limit(items):
    """[(time, S after it)] at each distinct event time; items are (time, died). Deaths and censorings at one time
    are both at risk just before it."""
    items = sorted(items)
    at_risk, s, out, i = len(items), 1.0, [], 0
    while i < len(items):
        t, d, c = items[i][0], 0, 0
        while i < len(items) and items[i][0] == t:
            d += items[i][1]
            c += 1
            i += 1
        s *= 1 - d / at_risk
        at_risk -= c
        if d:
            out.append((t, s))
    return out


def surv_at(curve, h):
    s = 1.0
    for t, v in curve:
        if t > h:
            break
        s = v
    return s


def restricted_mean(curve, h):
    area, prev, s = 0.0, 0.0, 1.0
    for t, v in curve:
        if t > h:
            break
        area += s * (t - prev)
        prev, s = t, v
    return area + s * (h - prev)


def cox_fit(X, start, stop, event, weight=None, iters=60):
    """Cox partial likelihood in counting-process form (risk set at t: start < t <= stop), Breslow ties, optional case
    weights, Newton-Raphson to |step| < 1e-10. Returns (coef, se from the observed information, partial loglik)."""
    X = np.asarray(X, float)
    n, p = X.shape
    w = np.ones(n) if weight is None else np.asarray(weight, float)
    start, stop, event = np.asarray(start, float), np.asarray(stop, float), np.asarray(event, float)
    ev = event > 0
    times = np.unique(stop[ev])
    so, sa = np.argsort(stop, kind="stable"), np.argsort(start, kind="stable")
    stop_s, start_s = stop[so], start[sa]
    i_stop = np.searchsorted(stop_s, times, "left")      # rows with stop >= t are from here on
    i_start = np.searchsorted(start_s, times, "left")    # rows with start >= t (not yet at risk)
    ti = np.searchsorted(times, stop[ev])
    D = np.bincount(ti, weights=w[ev], minlength=len(times))

    def suffix(arr, order, idx):
        cs = np.concatenate([np.cumsum(arr[order][::-1], axis=0)[::-1], np.zeros((1,) + arr.shape[1:])])
        return cs[idx]

    def moments(beta):
        e = w * np.exp(X @ beta)
        xe = X * e[:, None]
        xxe = X[:, :, None] * xe[:, None, :]
        s0 = suffix(e, so, i_stop) - suffix(e, sa, i_start)
        s1 = suffix(xe, so, i_stop) - suffix(xe, sa, i_start)
        s2 = suffix(xxe, so, i_stop) - suffix(xxe, sa, i_start)
        return s0, s1, s2

    def info_grad(beta):
        s0, s1, s2 = moments(beta)
        grad = (X[ev] * w[ev][:, None]).sum(axis=0) - (D[:, None] * s1 / s0[:, None]).sum(axis=0)
        info = (D[:, None, None] * (s2 / s0[:, None, None] - s1[:, :, None] * s1[:, None, :] / s0[:, None, None] ** 2)).sum(axis=0)
        return s0, grad, info

    def loglik(beta):
        s0, _, _ = moments(beta)
        return float((w[ev] * (X[ev] @ beta)).sum() - (D * np.log(s0)).sum())
    beta = np.zeros(p)
    for _ in range(iters):
        _, grad, info = info_grad(beta)
        step = np.linalg.solve(info, grad)
        for _ in range(30):  # halve a step that lowers the likelihood
            if loglik(beta + step) >= loglik(beta) - 1e-9:
                break
            step = step / 2
        beta = beta + step
        if np.max(np.abs(step)) < 1e-10:
            break
    _, _, info = info_grad(beta)
    return beta, np.sqrt(np.diag(np.linalg.inv(info))), loglik(beta)


def cox_breslow(X, days, dead, weight=None):
    """Cox model from times and a status: coef, se, partial loglik."""
    return cox_fit(X, np.zeros(len(days)), days, dead, weight)


def logistic(X, y, iters=100):
    """Logistic regression by Newton-Raphson to |step| < 1e-10 (X already holds the intercept column)."""
    beta = np.zeros(X.shape[1])
    for _ in range(iters):
        p = 1 / (1 + np.exp(-X @ beta))
        info = X.T @ (X * (p * (1 - p))[:, None])
        step = np.linalg.solve(info, X.T @ (y - p))
        beta = beta + step
        if np.max(np.abs(step)) < 1e-10:
            break
    return beta


# ---- level 2 ------------------------------------------------------------------------------------------------------

def node_c2(up, src):
    rows = analysis_rows(up, src)
    persons = {str(r["id"]): {"time_years": round(r["days"] / YEAR, 4), "event": int(r["dead"])} for r in rows}
    by_year = {str(y): sum(1 for r in rows if r["year"] == y and r["dead"]) for y in YEARS}
    return {"persons": persons, "summary": {
        "deaths": sum(1 for r in rows if r["dead"]),
        "person_years": round(sum(r["days"] for r in rows) / YEAR, 4),
        "deaths_by_year": by_year,
        "n_followed_past_10y": sum(1 for r in rows if r["days"] / YEAR > 10)}}


def node_c4(up, src):
    rows = analysis_rows(up, src)
    return {"persons": {str(r["id"]): {"age_band": band_of(r["age"]), "age_per_10y": r["age"] / 10,
                                       "sex_male": int(r["sex"] == "M"), "mgus": r["mgus"], "creatinine": r["creat"]}
                        for r in rows}}


def node_c5(up, src):
    rows = analysis_rows(up, src)
    miss = lambda rs: sum(1 for r in rs if r["creat"] is None)  # noqa: E731

    def cell(rs):
        return {"n": len(rs), "n_missing": miss(rs), "pct_missing": round(100 * miss(rs) / len(rs), 3)}
    return {"approach": "complete_case" if DECISIONS["Q3"] == "complete_case" else "weighted",
            "counts": {"n_analysis": len(rows), "n_missing": miss(rows), "n_model": len(rows) - miss(rows)},
            "by_age_band": {name: cell([r for r in rows if band_of(r["age"]) == name]) for name, _, _ in BANDS},
            "by_sex": {s: cell([r for r in rows if r["sex"] == s]) for s in ("F", "M")},
            "by_year": {str(y): cell([r for r in rows if r["year"] == y]) for y in YEARS}}


# ---- level 3 ------------------------------------------------------------------------------------------------------

def _missing_design(rows):
    cols = [[1.0, r["age"] / 10, float(r["sex"] == "M"), float(r["mgus"])] + [float(r["year"] == y) for y in YEARS[1:]]
            for r in rows]
    return np.array(cols)


MISSING_TERMS = ["intercept", "age_per_10y", "sex_male", "mgus"] + [f"year_{y}" for y in YEARS[1:]]


def node_c6(up, src):
    """P(creatinine recorded | age, sex, MGUS, sample year) by logistic regression on the analysis cohort; the weight of
    a person with creatinine recorded is 1 / P. People without creatinine have no weight."""
    rows = analysis_rows(up, src)
    X = _missing_design(rows)
    y = np.array([float(r["creat"] is not None) for r in rows])
    beta = logistic(X, y)
    p = 1 / (1 + np.exp(-X @ beta))
    w = {str(r["id"]): round(float(1 / pi), 4) for r, pi, yi in zip(rows, p, y) if yi == 1}
    vals = list(w.values())
    return {"coef": {t: round(float(b), 5) for t, b in zip(MISSING_TERMS, beta)}, "weights": {k: {"weight": v}
            for k, v in w.items()}, "summary": {"n_weighted": len(vals), "sum_weights": round(sum(vals), 2),
                                                 "max_weight": max(vals)}}


def node_c7(up, src):
    rows = [r for r in analysis_rows(up, src) if r["dead"]]
    cls = lambda c: c if c in CAUSES[:3] else "Other"  # noqa: E731
    counts = {k: sum(1 for r in rows if cls(r["cause"]) == k) for k in CAUSES}
    other = {}
    for r in rows:
        if cls(r["cause"]) == "Other":
            other[r["cause"]] = other.get(r["cause"], 0) + 1
    return {"persons": {str(r["id"]): {"cause": cls(r["cause"])} for r in rows},
            "summary": {"n_deaths": len(rows), "class_n": counts, "n_other_chapters": len(other),
                        "class_pct": {k: round(100 * v / len(rows), 3) for k, v in counts.items()},
                        "other_by_chapter": dict(sorted(other.items()))}}


def node_c8(up, src):
    """Person-time and deaths in cells of sex x FLC tier x attained 5-year age band (100+ is one band) x calendar year.
    Entry is at age `age` and calendar time sample_year + 0.5; a death belongs to the cell holding its exit point
    (cells are closed on the left)."""
    rows = analysis_rows(up, src)
    tiers = {int(i): p["tier"] for i, p in up["c3"]["persons"].items()}
    pyrs, deaths = {}, {}
    for r in rows:
        t0, a0 = r["year"] + ENTRY_OFFSET, float(r["age"])
        T = r["days"] / YEAR
        # breakpoints: attained age multiples of the band width and calendar integers, within (0, T)
        cuts = {0.0, T}
        k = int(a0 // AGE_BAND_WIDTH) + 1
        while k * AGE_BAND_WIDTH - a0 < T and k * AGE_BAND_WIDTH <= TOP_AGE_BAND:
            cuts.add(k * AGE_BAND_WIDTH - a0)
            k += 1
        y = int(t0) + 1
        while y - t0 < T:
            cuts.add(y - t0)
            y += 1
        pts = sorted(cuts)
        for lo, hi in zip(pts, pts[1:]):
            mid = (lo + hi) / 2
            key = _cell_key(r["sex"], tiers[r["id"]], a0 + mid, t0 + mid)
            pyrs[key] = pyrs.get(key, 0.0) + (hi - lo)
        if r["dead"]:
            key = _cell_key(r["sex"], tiers[r["id"]], a0 + T, t0 + T)
            deaths[key] = deaths.get(key, 0) + 1
    keys = sorted(set(pyrs) | set(deaths))
    cells = {k: {"person_years": round(pyrs.get(k, 0.0), 4), "deaths": deaths.get(k, 0)} for k in keys}
    return {"cells": cells, "summary": {"person_years": round(sum(pyrs.values()), 4),
                                        "deaths": sum(deaths.values())}}


def _cell_key(sex, tier, age, cal):
    lo = min(int(age // AGE_BAND_WIDTH) * AGE_BAND_WIDTH, TOP_AGE_BAND)
    return f"{sex}|{tier}|{lo}|{int(cal)}"


def node_s1(up, src):
    persons = up["c2"]["persons"]
    cov, grp = up["c4"]["persons"], up["c3"]["persons"]
    strata = {}
    for pid, p in persons.items():
        keys = [f"{cov[pid]['age_band']}/{'M' if cov[pid]['sex_male'] else 'F'}", f"flc_{grp[pid]['decile']}"]
        for k in keys:
            strata.setdefault(k, []).append((p["time_years"], bool(p["event"])))
    out = {}
    for k, items in strata.items():
        curve = product_limit(items)
        out[k] = {"n": len(items), "surv_5y": round(surv_at(curve, 5.0), 5), "surv_10y": round(surv_at(curve, 10.0), 5),
                  "rmst_5y": round(restricted_mean(curve, 5.0), 4), "rmst_10y": round(restricted_mean(curve, 10.0), 4)}
    order = [f"{b}/{s}" for b, _, _ in BANDS for s in "FM"] + [f"flc_{g}" for g in range(1, 11)]
    return {"strata": {k: out[k] for k in order}}


def node_m0(up, src):
    ids = [i for i, p in up["c4"]["persons"].items() if p["creatinine"] is not None]
    X = np.array([[up["c4"]["persons"][i]["age_per_10y"], up["c4"]["persons"][i]["sex_male"]] for i in ids])
    days = np.array([up["c2"]["persons"][i]["time_years"] for i in ids])
    dead = np.array([up["c2"]["persons"][i]["event"] for i in ids])
    beta, se, ll = cox_breslow(X, days, dead)
    return {"coef": {"age_per_10y": round(float(beta[0]), 5), "sex_male": round(float(beta[1]), 5)},
            "se": {"age_per_10y": round(float(se[0]), 5), "sex_male": round(float(se[1]), 5)},
            "partial_loglik": round(ll, 3), "counts": {"n": len(ids), "events": int(dead.sum())}}


def node_v0(up, src):
    """Censoring survival G (Kaplan-Meier with censoring as the event; deaths at a time are still at risk then) and the
    10-year weights: 1 / G(T-) for a death at or before 10 years, 1 / G(10-) for everyone followed past 10 years, 0 for
    people censored before 10 years. G(t-) uses censorings strictly before t."""
    persons = up["c2"]["persons"]
    items = [(p["time_years"], not p["event"]) for p in persons.values()]
    curve = product_limit(items)

    def g_before(t):
        s = 1.0
        for u, v in curve:
            if u >= t:
                break
            s = v
        return s
    w = {}
    for pid, p in persons.items():
        t = p["time_years"]
        if t > 10:
            w[pid] = 1 / g_before(10.0)
        elif p["event"]:
            w[pid] = 1 / g_before(t)
        else:
            w[pid] = 0.0
    return {"weights": {k: {"weight": round(v, 5)} for k, v in w.items()},
            "summary": {"g_10y": round(g_before(10.0), 5), "sum_weights": round(sum(w.values()), 2),
                        "n_censored_before_10y": sum(1 for v in w.values() if v == 0.0)}}


def node_R1(up, src):
    c1, c5 = up["c1"], up["c5"]
    cnt = c5["counts"]
    return {"n_records": c1["n_records"], "n_zero_followup": c1["n_records"] - c1["n_analysis"],
            "n_analysis": c1["n_analysis"], "n_missing_creatinine": cnt["n_missing"], "n_model": cnt["n_model"],
            "model_by_year": {y: v["n"] - v["n_missing"] for y, v in c5["by_year"].items()},
            "model_by_sex": {s: v["n"] - v["n_missing"] for s, v in c5["by_sex"].items()},
            "model_by_age_band": {b: v["n"] - v["n_missing"] for b, v in c5["by_age_band"].items()}}



# ---- stage 2 (levels 4 to 6) ----------------------------------------------------------------------------------------

import math
import re
import zipfile
import xml.etree.ElementTree as ET

LIFE_TABLES = {"F": "lifetables/nchs2008_Table03_Intercensal.xlsx", "M": "lifetables/nchs2008_Table02_Intercensal.xlsx"}
STD_GROUP_FIRST = 11   # SEER group 011 is ages 50-54; group 018 is 85 and over
_NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def read_xlsx(path):
    """Rows of the first sheet of an .xlsx as lists of str/float/None, with the standard library only."""
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", _NS):
                shared.append("".join(x.text or "" for x in si.iter("{%s}t" % _NS["m"])))
        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = []
    for row in sheet.iter("{%s}row" % _NS["m"]):
        cells = {}
        for c in row.findall("m:c", _NS):
            col = re.match(r"[A-Z]+", c.get("r")).group()
            v = c.find("m:v", _NS)
            if v is None:
                continue
            cells[col] = shared[int(v.text)] if c.get("t") == "s" else float(v.text)
        if cells:
            rows.append([cells.get(ch) for ch in "ABCDEFG"])
    return rows


def life_rates(src):
    """{sex: {band_lower_edge: death rate per person-year}} for the 5-year bands 50..95 and 100 and over of the life
    table: sum of d(x) over sum of L(x) across the single years of the band; the open interval is l(100) / T(100)."""
    out = {}
    for sex, rel in LIFE_TABLES.items():
        d, L, top = {}, {}, None
        for r in read_xlsx(Path(src) / rel):
            label = r[0]
            if not isinstance(label, str):
                continue
            m = re.fullmatch(r"(\d+)-(\d+)", label.strip())
            if m:
                d[int(m.group(1))], L[int(m.group(1))] = r[3], r[4]
            elif label.strip().lower().startswith("100 and over"):
                top = r[2] / r[5]
        out[sex] = {lo: sum(d[x] for x in range(lo, lo + 5)) / sum(L[x] for x in range(lo, lo + 5)) for lo in range(50, 100, 5)}
        out[sex][100] = top
    return out


def _split_key(key):
    sex, tier, age, year = key.split("|")
    return sex, tier, int(age), int(year)


# ---- level 4 ----

def node_e1(up, src):
    rates = life_rates(src)
    cells = {}
    for key in up["c8"]["cells"]:
        sex, _, age, year = _split_key(key)
        cells[f"{sex}|{age}|{year}"] = {"sex": sex, "age": age, "year": year, "rate": round(rates[sex][age], 7)}
    return {"cells": dict(sorted(cells.items()))}


def _band85(age):
    return min(age, 85)


def node_s2(up, src):
    py, dt = {}, {}
    for key, c in up["c8"]["cells"].items():
        sex, tier, age, _ = _split_key(key)
        k = f"{tier}|{sex}|{_band85(age)}"
        py[k] = py.get(k, 0.0) + c["person_years"]
        dt[k] = dt.get(k, 0) + c["deaths"]
    order = [f"{t}|{s}|{a}" for t in ("low", "mid", "high") for s in "FM" for a in range(50, 90, 5)]
    return {"strata": {k: {"person_years": round(py[k], 4), "deaths": dt[k], "rate_per_1000": round(1000 * dt[k] / py[k], 4)}
                       for k in order}}


def cumulative_incidence(items, cause, h):
    """Aalen-Johansen: items (time, cause or None); sum over event times <= h of S(before) * d_cause / at_risk."""
    items = sorted(items, key=lambda x: x[0])
    at_risk, s, cif, i = len(items), 1.0, 0.0, 0
    while i < len(items):
        t, d, dk, c = items[i][0], 0, 0, 0
        while i < len(items) and items[i][0] == t:
            d += items[i][1] is not None
            dk += items[i][1] == cause
            c += 1
            i += 1
        if t > h:
            break
        cif += s * dk / at_risk
        s *= 1 - d / at_risk
        at_risk -= c
    return cif


def node_k1(up, src):
    persons, causes, cov = up["c2"]["persons"], up["c7"]["persons"], up["c4"]["persons"]
    out = {}
    for cause in CAUSES:
        row = {}
        for label, pick in (("overall_pct", lambda i: True), ("female_pct", lambda i: not cov[i]["sex_male"]),
                            ("male_pct", lambda i: bool(cov[i]["sex_male"]))):
            items = [(p["time_years"], causes[i]["cause"] if p["event"] else None) for i, p in persons.items() if pick(i)]
            row[label] = round(100 * cumulative_incidence(items, cause, 10.0), 4)
        out[cause] = row
    return {"causes": out}


MODEL_TERMS = {"A": ["age_per_10y", "sex_male"], "B": ["age_per_10y", "sex_male", "log_flc_total"],
               "C": ["age_per_10y", "sex_male", "log_flc_total", "mgus"],
               "D": ["age_per_10y", "sex_male", "log_flc_total", "mgus", "creatinine"]}


def model_table(up):
    """Rows of the model cohort (creatinine recorded) with every covariate the models use."""
    cov, c2, c3 = up["c4"]["persons"], up["c2"]["persons"], up["c3"]["persons"]
    rows = []
    for i, c in cov.items():
        if c["creatinine"] is None:
            continue
        rows.append({"id": i, "time": c2[i]["time_years"], "event": c2[i]["event"], "age_per_10y": c["age_per_10y"],
                     "sex_male": c["sex_male"], "mgus": c["mgus"], "creatinine": c["creatinine"],
                     "flc_sum": c3[i]["flc_sum"], "log_flc_total": math.log(c3[i]["flc_sum"]),
                     "decile": c3[i]["decile"], "tier": c3[i]["tier"]})
    return rows


def fit_terms(rows, terms, weight=None, start=None, stop=None):
    X = np.array([[r[t] for t in terms] for r in rows], float)
    time = np.array([r["time"] for r in rows])
    ev = np.array([r["event"] for r in rows])
    return cox_fit(X, np.zeros(len(rows)) if start is None else start, time if stop is None else stop, ev, weight)


def node_m1(up, src):
    rows = model_table(up)
    models = {}
    for name, terms in MODEL_TERMS.items():
        b, s, ll = fit_terms(rows, terms)
        models[name] = {"coef": {t: round(float(x), 5) for t, x in zip(terms, b)},
                        "se": {t: round(float(x), 5) for t, x in zip(terms, s)}, "loglik": round(ll, 3)}
    w = np.array([up["c6"]["weights"][r["id"]]["weight"] for r in rows])
    b, _, ll = fit_terms(rows, MODEL_TERMS["D"], weight=w)
    models["E"] = {"coef": {t: round(float(x), 5) for t, x in zip(MODEL_TERMS["D"], b)}, "loglik": round(ll, 3)}
    return {"models": models}


# ---- level 5 ----

def std_population(src):
    """US 2000 standard population (SEER standard 203) for the groups 50-54 ... 80-84 and 85+."""
    pops = {}
    for line in (Path(src) / "standard" / "stdpop.19ages.txt").read_text().split():
        if line[:3] == "203":
            pops[int(line[3:6])] = int(line[6:])
    return {50 + 5 * (g - STD_GROUP_FIRST): pops[g] for g in range(STD_GROUP_FIRST, 19)}


def node_s3(up, src):
    pop = std_population(src)
    total = sum(pop.values())
    weights = {a: pop[a] / total for a in pop}
    rates = {}
    for tier in ("low", "mid", "high"):
        for sex in "FM":
            rates[f"{tier}|{sex}"] = round(sum(weights[a] * up["s2"]["strata"][f"{tier}|{sex}|{a}"]["rate_per_1000"]
                                               for a in weights), 4)
    return {"rates": rates, "weights": {str(a): round(w, 6) for a, w in weights.items()}}


def node_s4(up, src):
    rate = {k: v["rate"] for k, v in up["e1"]["cells"].items()}
    acc = {}
    for key, c in up["c8"]["cells"].items():
        sex, tier, age, year = _split_key(key)
        e = rate[f"{sex}|{age}|{year}"] * c["person_years"]
        for t in (tier, "all"):
            for s in (sex, "all"):
                o = acc.setdefault(f"{t}|{s}", [0, 0.0])
                o[0] += c["deaths"]
                o[1] += e
    order = [f"{t}|{s}" for t in ("low", "mid", "high", "all") for s in ("F", "M", "all")]
    return {"strata": {k: {"observed": acc[k][0], "expected": round(acc[k][1], 3), "smr": round(acc[k][0] / acc[k][1], 4)}
                       for k in order}}


def node_r1(up, src):
    """Ederer II expected survival with annual intervals: the interval hazard is the expected deaths over the person-years
    of everyone still under observation in the interval; S_exp(k) is exp(minus the sum of the first k interval hazards)."""
    rate = {k: v["rate"] for k, v in up["e1"]["cells"].items()}
    years = {int(r["id"]): r["year"] for r in load(src)}
    acc = {}
    for i, p in up["c2"]["persons"].items():
        c = up["c4"]["persons"][i]
        sex, a0, t0, T = ("M" if c["sex_male"] else "F"), round(c["age_per_10y"] * 10), years[int(i)] + ENTRY_OFFSET, p["time_years"]
        cuts = {0.0, T}
        k = int(a0 // AGE_BAND_WIDTH) + 1
        while k * AGE_BAND_WIDTH - a0 < T and k * AGE_BAND_WIDTH <= TOP_AGE_BAND:
            cuts.add(k * AGE_BAND_WIDTH - a0)
            k += 1
        y = int(t0) + 1
        while y - t0 < T:
            cuts.add(y - t0)
            y += 1
        j = 1
        while j < T:
            cuts.add(float(j))
            j += 1
        pts = sorted(cuts)
        keys = [f"{c['age_band']}/{sex}"]
        for lo, hi in zip(pts, pts[1:]):
            mid = (lo + hi) / 2
            h = rate[f"{sex}|{min(int((a0 + mid) // AGE_BAND_WIDTH) * AGE_BAND_WIDTH, TOP_AGE_BAND)}|{int(t0 + mid)}"]
            interval = int(mid)
            for key in keys:
                cell = acc.setdefault((key, interval), [0.0, 0.0])
                cell[0] += h * (hi - lo)
                cell[1] += hi - lo
    out = {}
    for b, _, _ in BANDS:
        for s in "FM":
            key = f"{b}/{s}"
            cum = lambda k: math.exp(-sum(acc[(key, j)][0] / acc[(key, j)][1] for j in range(k)))  # noqa: E731
            out[key] = {"exp_5y": round(cum(5), 5), "exp_10y": round(cum(10), 5)}
    return {"strata": out}


def node_r3(up, src):
    """Poisson model of the observed deaths of each split cell against the expected deaths: d ~ Poisson(d* exp(x b)), that is
    log(mu) = log(d*) + x b, the log ratio of observed to expected. (The additive Esteve form mu = d* + y exp(x b) has no
    maximum on this cohort: observed deaths are below the life-table expectation overall, so its intercept runs to minus
    infinity; see the review file.)"""
    rate = {k: v["rate"] for k, v in up["e1"]["cells"].items()}
    X, d, ds = [], [], []
    for key, c in up["c8"]["cells"].items():
        sex, tier, age, year = _split_key(key)
        X.append([1.0, (age + 2.5) / 10, float(sex == "M"), float(tier == "mid"), float(tier == "high")])
        d.append(c["deaths"])
        ds.append(rate[f"{sex}|{age}|{year}"] * c["person_years"])
    X, d, ds = np.array(X), np.array(d, float), np.array(ds)
    off = np.log(ds)

    def ll(b):
        mu = np.exp(off + X @ b)
        return float((d * (off + X @ b) - mu).sum())
    b = np.zeros(5)
    for _ in range(100):
        mu = np.exp(off + X @ b)
        step = np.linalg.solve((X * mu[:, None]).T @ X, X.T @ (d - mu))
        for _ in range(30):
            if ll(b + step) >= ll(b) - 1e-9:
                break
            step = step / 2
        b = b + step
        if np.max(np.abs(step)) < 1e-10:
            break
    mu = np.exp(off + X @ b)
    se = np.sqrt(np.diag(np.linalg.inv((X * mu[:, None]).T @ X)))
    names = ["intercept", "age_per_10y", "sex_male", "tier_mid", "tier_high"]
    return {"coef": {n: round(float(v), 5) for n, v in zip(names, b)}, "se": {n: round(float(v), 5) for n, v in zip(names, se)},
            "loglik": round(ll(b), 3), "expected_deaths": round(float(ds.sum()), 3)}


def _g_before_fn(times, event):
    """Censoring survival just before t (Kaplan-Meier with censoring as the event; deaths at a time are still at risk)."""
    curve = product_limit([(t, not e) for t, e in zip(times, event)])
    ts = np.array([t for t, _ in curve])
    vs = np.array([v for _, v in curve])

    def g(t):
        idx = np.searchsorted(ts, t, "left") - 1
        return np.where(idx >= 0, vs[np.maximum(idx, 0)], 1.0)
    return g


def finegray(X, time, event, cause_event, iters=60):
    """Fine-Gray subdistribution hazard for one cause: `event` is any death, `cause_event` the cause of interest. A person
    who died of another cause stays in the risk set with weight G(t-)/G(T-)."""
    X, time = np.asarray(X, float), np.asarray(time, float)
    event, cause_event = np.asarray(event, bool), np.asarray(cause_event, bool)
    g = _g_before_fn(time, event)
    comp = event & ~cause_event
    gt = g(time)
    order = np.argsort(time, kind="stable")
    ts = time[order]
    ets = np.unique(time[cause_event])
    ci = np.searchsorted(ets, time[cause_event])
    D = np.bincount(ci, minlength=len(ets)).astype(float)
    idx_ge = np.searchsorted(ts, ets, "left")
    cts = np.sort(time[comp])
    corder = np.argsort(time[comp], kind="stable")
    idx_lt = np.searchsorted(cts, ets, "left")
    gE = g(ets)

    def sums(a, arr):
        suf = np.concatenate([np.cumsum(arr[order][::-1], axis=0)[::-1], np.zeros((1,) + arr.shape[1:])])
        cc = (arr[comp] / gt[comp].reshape((-1,) + (1,) * (arr.ndim - 1)))[corder]
        pre = np.concatenate([np.zeros((1,) + arr.shape[1:]), np.cumsum(cc, axis=0)])
        return suf[idx_ge] + pre[idx_lt] * gE.reshape((-1,) + (1,) * (arr.ndim - 1))

    def moments(beta):
        e = np.exp(X @ beta)
        return sums(None, e), sums(None, X * e[:, None]), sums(None, X[:, :, None] * (X * e[:, None])[:, None, :])
    beta = np.zeros(X.shape[1])
    for _ in range(iters):
        s0, s1, s2 = moments(beta)
        grad = X[cause_event].sum(axis=0) - (D[:, None] * s1 / s0[:, None]).sum(axis=0)
        info = (D[:, None, None] * (s2 / s0[:, None, None] - s1[:, :, None] * s1[:, None, :] / s0[:, None, None] ** 2)).sum(axis=0)
        step = np.linalg.solve(info, grad)
        beta = beta + step
        if np.max(np.abs(step)) < 1e-10:
            break
    s0, s1, s2 = moments(beta)
    info = (D[:, None, None] * (s2 / s0[:, None, None] - s1[:, :, None] * s1[:, None, :] / s0[:, None, None] ** 2)).sum(axis=0)
    return beta, np.sqrt(np.diag(np.linalg.inv(info)))


FG_TERMS = ["age_per_10y", "sex_male", "log_flc_total"]


def node_k2(up, src):
    ids = list(up["c4"]["persons"])
    X = np.array([[up["c4"]["persons"][i]["age_per_10y"], up["c4"]["persons"][i]["sex_male"],
                   math.log(up["c3"]["persons"][i]["flc_sum"])] for i in ids])
    time = np.array([up["c2"]["persons"][i]["time_years"] for i in ids])
    ev = np.array([up["c2"]["persons"][i]["event"] for i in ids], bool)
    out = {}
    for cause in ("Circulatory", "Neoplasms"):
        ce = np.array([bool(up["c7"]["persons"].get(i, {}).get("cause") == cause) for i in ids])
        b, s = finegray(X, time, ev, ce)
        out[cause] = {"coef": {t: round(float(v), 5) for t, v in zip(FG_TERMS, b)},
                      "se": {t: round(float(v), 5) for t, v in zip(FG_TERMS, s)}, "n_events": int(ce.sum())}
    return {"causes": out}


def schoenfeld_tests(rows, terms):
    """Grambsch-Therneau test per term of the Cox model on `terms` (Breslow ties), g(t) = time in years:
    chisq_k = (sum_j (g_j - mean g) s*_jk)^2 / (d V_kk sum_j (g_j - mean g)^2), s* = beta + d V r, r the Schoenfeld residual."""
    X = np.array([[r[t] for t in terms] for r in rows], float)
    time = np.array([r["time"] for r in rows])
    ev = np.array([r["event"] for r in rows], bool)
    b, se, _ = cox_fit(X, np.zeros(len(rows)), time, ev)
    order = np.argsort(time, kind="stable")
    ts = time[order]
    e = np.exp(X @ b)
    suf0 = np.cumsum(e[order][::-1])[::-1]
    suf1 = np.cumsum((X * e[:, None])[order][::-1], axis=0)[::-1]
    ev_idx = np.flatnonzero(ev)
    pos = np.searchsorted(ts, time[ev_idx], "left")
    resid = X[ev_idx] - suf1[pos] / suf0[pos][:, None]
    V = np.linalg.inv(_cox_info(X, time, ev, b))
    d = len(ev_idx)
    scaled = b + d * resid @ V
    g = time[ev_idx]
    xx = g - g.mean()
    chisq = (xx @ scaled) ** 2 / (d * np.diag(V) * (xx ** 2).sum())
    return chisq, np.array([math.erfc(math.sqrt(c / 2)) for c in chisq])


def _cox_info(X, time, ev, beta):
    order = np.argsort(time, kind="stable")
    ts = time[order]
    e = np.exp(X @ beta)
    suf0 = np.cumsum(e[order][::-1])[::-1]
    suf1 = np.cumsum((X * e[:, None])[order][::-1], axis=0)[::-1]
    suf2 = np.cumsum((X[:, :, None] * (X * e[:, None])[:, None, :])[order][::-1], axis=0)[::-1]
    times = np.unique(time[ev])
    pos = np.searchsorted(ts, times, "left")
    D = np.bincount(np.searchsorted(times, time[ev]), minlength=len(times)).astype(float)
    s0, s1, s2 = suf0[pos], suf1[pos], suf2[pos]
    return (D[:, None, None] * (s2 / s0[:, None, None] - s1[:, :, None] * s1[:, None, :] / s0[:, None, None] ** 2)).sum(axis=0)


def node_m2(up, src):
    terms = MODEL_TERMS["D"]
    chisq, p = schoenfeld_tests(model_table(up), terms)
    return {"terms": {t: {"chisq": round(float(c), 4), "p": round(float(q), 5)} for t, c, q in zip(terms, chisq, p)}}


def rcs_basis(x, knots):
    """Harrell's restricted cubic spline with three knots: [x, nonlinear term]."""
    k1, k2, k3 = knots
    c = lambda u: np.maximum(u, 0) ** 3  # noqa: E731
    nl = (c(x - k1) - c(x - k2) * (k3 - k1) / (k3 - k2) + c(x - k3) * (k2 - k1) / (k3 - k2)) / (k3 - k1) ** 2
    return np.c_[x, nl]


def flc_columns(rows, form, knots=None):
    """Design columns for the FLC part of the model under a functional form: (names, matrix)."""
    s = np.array([r["flc_sum"] for r in rows])
    if form == "log":
        return ["log_flc_total"], np.log(s)[:, None]
    if form == "linear":
        return ["flc_sum"], s[:, None]
    if form == "tier":
        return ["tier_mid", "tier_high"], np.c_[[r["tier"] == "mid" for r in rows], [r["tier"] == "high" for r in rows]].astype(float)
    if form == "decile":
        return [f"decile_{k}" for k in range(2, 11)], np.array([[r["decile"] == k for k in range(2, 11)] for r in rows], float)
    if form == "spline":
        kn = knots or [quantile7(list(s), q) for q in (0.1, 0.5, 0.9)]
        return ["flc_spline_1", "flc_spline_2"], rcs_basis(s, kn)
    raise ValueError(form)


FORMS = ["log", "linear", "tier", "decile", "spline"]
BASE_TERMS = ["age_per_10y", "sex_male", "mgus", "creatinine"]


def fit_form(rows, form, tv=(), cut=5.0):
    """Cox model of the base terms plus the FLC form; terms named in `tv` get a separate coefficient before and after `cut`."""
    names, flc = flc_columns(rows, form)
    base = np.array([[r[t] for t in BASE_TERMS] for r in rows], float)
    X, cols = np.c_[base[:, :2], flc, base[:, 2:]], BASE_TERMS[:2] + names + BASE_TERMS[2:]
    time = np.array([r["time"] for r in rows])
    ev = np.array([r["event"] for r in rows], float)
    if not tv:
        b, s, ll = cox_fit(X, np.zeros(len(rows)), time, ev)
        return cols, b, s, ll
    # split every person at `cut`: rows (0, min(T, cut)] and (cut, T]
    early = time > 0
    late = time > cut
    # before the cut a tv term has one coefficient, after it another; the other terms keep a single coefficient
    tvm = np.array([c in tv for c in cols])
    keep = X[:, ~tvm]
    X1 = np.c_[keep, X[:, tvm], np.zeros((len(rows), tvm.sum()))]
    X2 = np.c_[keep, np.zeros((len(rows), tvm.sum())), X[:, tvm]]
    Xs = np.r_[X1[early], X2[late]]
    start = np.r_[np.zeros(early.sum()), np.full(late.sum(), cut)]
    stop = np.r_[np.minimum(time[early], cut), time[late]]
    evs = np.r_[np.where(time[early] <= cut, ev[early], 0.0), ev[late]]
    b, s, ll = cox_fit(Xs, start, stop, evs)
    cols_out = [c for c in cols if c not in tv] + [f"{c}@0-{int(cut)}" for c in cols if c in tv] + [f"{c}@{int(cut)}+" for c in cols if c in tv]
    return cols_out, b, s, ll


def node_m3(up, src):
    rows = model_table(up)
    forms = {}
    for f in FORMS:
        cols, b, s, ll = fit_form(rows, f)
        forms[f] = {"df": len(cols), "loglik": round(ll, 3), "aic": round(2 * len(cols) - 2 * ll, 3)}
    return {"forms": forms, "best": min(forms, key=lambda f: forms[f]["aic"])}


PH_ALPHA = 0.01
TV_CUT = 5.0


def node_m4(up, src):
    rows = model_table(up)
    form = up["m3"]["best"]
    fails = {t for t, v in up["m2"]["terms"].items() if v["p"] < PH_ALPHA}
    names, _ = flc_columns(rows, form)
    tv = set()
    for t in fails:
        tv |= set(names) if t == "log_flc_total" else {t}
    tv = [c for c in BASE_TERMS[:2] + names + BASE_TERMS[2:] if c in tv]
    cols, b, s, ll = fit_form(rows, form, tv, TV_CUT)
    return {"form": form, "tv_terms": sorted(tv), "coef": {c: round(float(x), 5) for c, x in zip(cols, b)},
            "se": {c: round(float(x), 5) for c, x in zip(cols, s)}, "loglik": round(ll, 3), "aic": round(2 * len(cols) - 2 * ll, 3)}


# ---- level 6 ----

def node_r2(up, src):
    return {"strata": {k: {"rel_5y": round(up["s1"]["strata"][k]["surv_5y"] / v["exp_5y"], 5),
                           "rel_10y": round(up["s1"]["strata"][k]["surv_10y"] / v["exp_10y"], 5)}
                       for k, v in up["r1"]["strata"].items()}}


def node_R2(up, src):
    return {"survival_10y": {k: v["surv_10y"] for k, v in up["s1"]["strata"].items() if k.startswith("flc_")},
            "std_rate": up["s3"]["rates"], "smr": {k: v["smr"] for k, v in up["s4"]["strata"].items()},
            "cif_10y": {k: v["overall_pct"] for k, v in up["k1"]["causes"].items()}}


# ---- stage 3 and 4 (levels 7 to 11) -----------------------------------------------------------------------------------

BOOT_SEED = 20261115
N_BOOT = 200
RISK_CUTS = (0.10, 0.25)
NB_THRESHOLDS = (0.10, 0.20, 0.30)
M64 = (1 << 64) - 1


def splitmix64(seed):
    """Endless stream of 64-bit integers (the public SplitMix64 generator)."""
    state = seed & M64
    while True:
        state = (state + 0x9E3779B97F4A7C15) & M64
        z = state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        yield z ^ (z >> 31)


def bootstrap_indices(n, b=None, seed=BOOT_SEED):
    """b resamples of n indices into the id-ascending model cohort: index = next SplitMix64 output mod n, one stream."""
    gen = splitmix64(seed)
    return [[next(gen) % n for _ in range(n)] for _ in range(N_BOOT if b is None else b)]


def model_rows_sorted(up):
    return sorted(model_table(up), key=lambda r: int(r["id"]))


def tv_columns(form, tv_old, form_old):
    """The time-varying columns of a model with FLC form `form`, given the time-varying columns of a model with `form_old`."""
    old = set(flc_columns([{"flc_sum": 1.0, "tier": "low", "decile": 1}, {"flc_sum": 2.0, "tier": "mid", "decile": 2},
                           {"flc_sum": 3.0, "tier": "high", "decile": 3}, {"flc_sum": 4.0, "tier": "high", "decile": 9}], form_old,
                          [1.0, 2.0, 3.0])[0])
    new_names = flc_columns([{"flc_sum": 1.0, "tier": "low", "decile": 1}, {"flc_sum": 2.0, "tier": "mid", "decile": 2},
                             {"flc_sum": 3.0, "tier": "high", "decile": 3}, {"flc_sum": 4.0, "tier": "high", "decile": 9}], form,
                            [1.0, 2.0, 3.0])[0]
    out = [c for c in BASE_TERMS if c in tv_old]
    if old & set(tv_old):
        out += new_names
    return out


def build_design(rows, form, tv, cut=TV_CUT):
    """(columns, X1, X2): the design before and after `cut`; with no time-varying column one coefficient per term (X1 = X2)."""
    names, flc = flc_columns(rows, form)
    base = np.array([[r[t] for t in BASE_TERMS] for r in rows], float)
    X, cols = np.c_[base[:, :2], flc, base[:, 2:]], BASE_TERMS[:2] + names + BASE_TERMS[2:]
    if not tv:
        return cols, X, X
    tvm = np.array([c in tv for c in cols])
    keep = X[:, ~tvm]
    z = np.zeros((len(rows), int(tvm.sum())))
    cols_out = [c for c in cols if c not in tv] + [f"{c}@0-{int(cut)}" for c in cols if c in tv] + [f"{c}@{int(cut)}+" for c in cols if c in tv]
    return cols_out, np.c_[keep, X[:, tvm], z], np.c_[keep, z, X[:, tvm]]


def stack(rows, X1, X2, tv, cut=TV_CUT, weight=None, entry=0.0, index=None):
    """Counting-process rows of a design; `index` repeats persons (bootstrap), `entry` drops time before it (left truncation)."""
    idx = np.arange(len(rows)) if index is None else np.asarray(index)
    time = np.array([r["time"] for r in rows])[idx]
    ev = np.array([r["event"] for r in rows], float)[idx]
    w = np.ones(len(idx)) if weight is None else np.asarray(weight, float)[idx]
    if not tv:
        parts = [(X1[idx], np.zeros(len(idx)), time, ev, w)]
    else:
        late = time > cut
        parts = [(X1[idx], np.zeros(len(idx)), np.minimum(time, cut), np.where(time <= cut, ev, 0.0), w),
                 (X2[idx][late], np.full(late.sum(), cut), time[late], ev[late], w[late])]
    X = np.vstack([p[0] for p in parts])
    start = np.concatenate([p[1] for p in parts])
    stop = np.concatenate([p[2] for p in parts])
    e = np.concatenate([p[3] for p in parts])
    ww = np.concatenate([p[4] for p in parts])
    keep = stop > entry
    return X[keep], np.maximum(start[keep], entry), stop[keep], e[keep], ww[keep]


def breslow(X, start, stop, ev, w, beta):
    """Breslow baseline hazard increments at the distinct event times: (times, d / S0)."""
    times = np.unique(stop[ev > 0])
    e = w * np.exp(X @ beta)
    so, sa = np.argsort(stop, kind="stable"), np.argsort(start, kind="stable")
    suf = lambda order, key: np.concatenate([np.cumsum(e[order][::-1])[::-1], [0.0]])[np.searchsorted(key[order], times, "left")]  # noqa: E731
    s0 = suf(so, stop) - suf(sa, start)
    D = np.bincount(np.searchsorted(times, stop[ev > 0]), weights=w[ev > 0], minlength=len(times))
    return times, D / s0


def fit_final(rows, form, tv, weight=None, entry=0.0, index=None, cut=TV_CUT):
    """Fit the final-model structure; returns the fit and what is needed to predict (columns, beta, se, loglik, baseline)."""
    cols, X1, X2 = build_design(rows, form, tv, cut)
    X, start, stop, ev, w = stack(rows, X1, X2, tv, cut, weight, entry, index)
    b, se, ll = cox_fit(X, start, stop, ev, w if weight is not None else None)
    times, dh = breslow(X, start, stop, ev, w if weight is not None else np.ones(len(ev)), b)
    ha = float(dh[times <= cut].sum())
    hb = float(dh[(times > cut) & (times <= 10.0)].sum())
    return {"cols": cols, "beta": b, "se": se, "loglik": ll, "H5": ha, "H5_10": hb}


def predict(fit, rows, form, tv, cut=TV_CUT):
    """(lp_early, lp_late, 10-year risk) of every row from a fit."""
    _, X1, X2 = build_design(rows, form, tv, cut)
    l1, l2 = X1 @ fit["beta"], X2 @ fit["beta"]
    return l1, l2, 1 - np.exp(-(fit["H5"] * np.exp(l1) + fit["H5_10"] * np.exp(l2)))


def final_structure(up):
    return up["m4"]["form"], list(up["m4"]["tv_terms"])


def node_v1(up, src):
    rows = model_rows_sorted(up)
    form, tv = final_structure(up)
    fit = fit_final(rows, form, tv)
    l1, l2, risk = predict(fit, rows, form, tv)
    return {"persons": {str(r["id"]): {"lp_early": round(float(a), 5), "lp_late": round(float(b), 5), "risk_10y": round(float(c), 5)}
                        for r, a, b, c in zip(rows, l1, l2, risk)},
            "summary": {"mean_risk_10y": round(float(risk.mean()), 5), "H0_5y": round(fit["H5"], 9),
                        "H0_10y": round(fit["H5"] + fit["H5_10"], 9)}}


def harrell_counts(time, event, score):
    """(concordant incl. half of the ties, comparable pairs): a pair is comparable when the earlier time is a death (equal
    times are not comparable) and concordant when the earlier death has the higher score; tied scores count one half."""
    return weighted_concordance(time, event, score, np.ones(len(time)), np.inf)


def weighted_concordance(time, event, score, wi, tau):
    """Sum over deaths i with time < tau of wi[i] * (number of j with time_j > time_i and score_j < score_i, plus half the ties in
    score), and the sum of wi[i] * (number of j with time_j > time_i). Fenwick tree over the ranks of the scores."""
    time, event, score, wi = np.asarray(time), np.asarray(event, bool), np.asarray(score), np.asarray(wi, float)
    ranks = np.unique(score)
    r = np.searchsorted(ranks, score) + 1
    m = len(ranks)
    tree = [0] * (m + 1)

    def add(i):
        while i <= m:
            tree[i] += 1
            i += i & -i

    def prefix(i):
        s = 0
        while i > 0:
            s += tree[i]
            i -= i & -i
        return s
    order = np.argsort(-time, kind="stable")
    conc = comp = 0.0
    inserted = 0
    i = 0
    n = len(time)
    while i < n:
        j = i
        while j < n and time[order[j]] == time[order[i]]:
            j += 1
        group = order[i:j]
        for g in group:
            if event[g] and time[g] < tau:
                less, upto = prefix(r[g] - 1), prefix(r[g])
                conc += wi[g] * (less + 0.5 * (upto - less))
                comp += wi[g] * inserted
        for g in group:
            add(int(r[g]))
        inserted += len(group)
        i = j
    return conc, comp


def node_v2(up, src):
    rows = model_rows_sorted(up)
    form, tv = final_structure(up)
    time = np.array([r["time"] for r in rows])
    ev = np.array([r["event"] for r in rows])
    fit = fit_final(rows, form, tv)
    _, _, risk = predict(fit, rows, form, tv)
    c = harrell_counts(time, ev, risk)
    apparent = c[0] / c[1]
    boots = []
    for idx in bootstrap_indices(len(rows)):
        sample = [rows[i] for i in idx]
        f = fit_final(sample, form, tv)
        _, _, rb = predict(f, sample, form, tv)
        cb = harrell_counts(np.array([r["time"] for r in sample]), np.array([r["event"] for r in sample]), rb)
        _, _, ro = predict(f, rows, form, tv)
        ct = harrell_counts(time, ev, ro)
        boots.append({"c_boot": round(cb[0] / cb[1], 5), "c_test": round(ct[0] / ct[1], 5)})
    optimism = float(np.mean([b["c_boot"] - b["c_test"] for b in boots]))
    return {"apparent_c": round(apparent, 5), "resamples": {str(i + 1): b for i, b in enumerate(boots)},
            "optimism": round(optimism, 5), "corrected_c": round(apparent - optimism, 5)}


def _cloglog(p):
    return np.log(-np.log1p(-np.clip(p, 1e-9, 1 - 1e-9)))


def node_v3(up, src):
    ids = sorted(up["v1"]["persons"], key=int)
    risk = np.array([up["v1"]["persons"][i]["risk_10y"] for i in ids])
    w = np.array([up["v0"]["weights"][i]["weight"] for i in ids])
    t = np.array([up["c2"]["persons"][i]["time_years"] for i in ids])
    e = np.array([up["c2"]["persons"][i]["event"] for i in ids])
    order = sorted(range(len(ids)), key=lambda k: (risk[k], int(ids[k])))
    group = np.zeros(len(ids), int)
    for rank, k in enumerate(order):
        group[k] = rank * 10 // len(ids) + 1
    died = (e == 1) & (t <= 10)
    out = {}
    pred, obs = [], []
    for g in range(1, 11):
        m = group == g
        o = float((w[m] * died[m]).sum() / m.sum())
        out[str(g)] = {"n": int(m.sum()), "mean_pred": round(float(risk[m].mean()), 5), "observed": round(o, 5)}
        pred.append(risk[m].mean())
        obs.append(o)
    x, y = _cloglog(np.array(pred)), _cloglog(np.array(obs))
    slope = float(((x - x.mean()) * (y - y.mean())).sum() / ((x - x.mean()) ** 2).sum())
    intercept = float(y.mean() - slope * x.mean())
    return {"groups": out, "slope": round(slope, 5), "intercept": round(intercept, 5),
            "mean_abs_error": round(float(np.mean(np.abs(np.array(pred) - np.array(obs)))), 5)}


def node_v4(up, src):
    ids = sorted(up["v1"]["persons"], key=int)
    risk = np.array([up["v1"]["persons"][i]["risk_10y"] for i in ids])
    t = np.array([up["c2"]["persons"][i]["time_years"] for i in ids])
    e = np.array([up["c2"]["persons"][i]["event"] for i in ids])
    w = np.array([up["v0"]["weights"][i]["weight"] for i in ids])
    hc, hp = harrell_counts(t, e, risk)
    uc, up_ = weighted_concordance(t, e, risk, w ** 2, 10.0)
    return {"harrell_c": round(hc / hp, 5), "harrell_pairs": int(hp), "uno_c": round(uc / up_, 5), "uno_weight": round(up_, 2)}


def node_v7(up, src):
    a, b = up["v3"]["intercept"], up["v3"]["slope"]
    risks = {i: p["risk_10y"] for i, p in up["v1"]["persons"].items()}
    new = {i: float(1 - np.exp(-np.exp(a + b * _cloglog(np.array(r))))) for i, r in risks.items()}
    return {"persons": {i: {"risk_10y": round(v, 5)} for i, v in new.items()},
            "recal": {"intercept": a, "slope": b}, "summary": {"mean_risk_10y": round(float(np.mean(list(new.values()))), 5)}}


# ---- z1 and the deliverables ----

def flc_hr(form, cols, beta, rows):
    """Log hazard ratio of the 90th against the 10th percentile of flc_sum, early and late, from a fit."""
    s = [r["flc_sum"] for r in rows]
    lo, hi = quantile7(s, 0.1), quantile7(s, 0.9)
    out = {}
    for label, suffix in (("early", "@0-5"), ("late", "@5+")):
        tot = 0.0
        for k, c in enumerate(cols):
            base = c[: c.index("@")] if "@" in c else c
            if "@" in c and not c.endswith(suffix):
                continue
            if form == "log" and base == "log_flc_total":
                tot += beta[k] * (math.log(hi) - math.log(lo))
            elif form == "tier" and base == "tier_high":
                tot += beta[k]
        out[label] = tot
    return out


def run_summary(name, rows, cols, beta, ll, form, n_events, n):
    hr = flc_hr(form, cols, beta, rows)
    return {"n": n, "events": n_events, "coef": {c: round(float(b), 5) for c, b in zip(cols, beta)},
            "hr_p90_p10": {k: round(math.exp(v), 4) for k, v in hr.items()}}


def node_z1(up, src):
    rows = model_rows_sorted(up)
    form, tv = final_structure(up)
    runs = {}

    def cox_run(name, rs, f, t, **kw):
        fit = fit_final(rs, f, t, **kw)
        runs[name] = run_summary(name, rs, fit["cols"], fit["beta"], fit["loglik"], f, int(sum(r["event"] for r in rs)), len(rs))
    cox_run("main", rows, form, tv)
    w = np.array([up["c6"]["weights"][r["id"]]["weight"] for r in rows])
    cox_run("weighted", rows, form, tv, weight=w)
    late = [r for r in rows if r["time"] > 2.0]
    cox_run("drop_first_2y", late, form, tv, entry=2.0)
    # the entry time is 2 years for everyone left: deaths before it are gone, the clock is not reset
    no_mgus = [dict(r) for r in rows if r["mgus"] == 0]
    cols0, X10, X20 = build_design(no_mgus, form, tv)
    keep = [i for i, c in enumerate(cols0) if not c.startswith("mgus")]
    X, start, stop, ev, ww = stack(no_mgus, X10[:, keep], X20[:, keep], tv)
    b, se, ll = cox_fit(X, start, stop, ev)
    runs["drop_mgus"] = run_summary("drop_mgus", no_mgus, [cols0[i] for i in keep], b, ll, form, int(sum(r["event"] for r in no_mgus)), len(no_mgus))
    cox_run("tiers", rows, "tier", tv_columns("tier", tv, form))
    cause = {r["id"]: up["c7"]["persons"].get(r["id"], {}).get("cause") for r in rows}
    cols1, X1, _ = build_design(rows, form, [])
    ev_all = np.array([r["event"] for r in rows], bool)
    ce = np.array([cause[r["id"]] == "Circulatory" for r in rows])
    bf, sf = finegray(X1, np.array([r["time"] for r in rows]), ev_all, ce)
    runs["competing"] = run_summary("competing", rows, cols1, bf, 0.0, form, int(ce.sum()), len(rows))
    return {"runs": runs}


def node_R3(up, src):
    return {"relative_survival_10y": {k: v["rel_10y"] for k, v in up["r2"]["strata"].items()},
            "excess_ratio": {k: round(math.exp(v), 4) for k, v in up["r3"]["coef"].items() if k != "intercept"}}


def node_R5(up, src):
    runs = up["z1"]["runs"]
    main = runs["main"]["hr_p90_p10"]
    reruns = {k: {"hr_early": v["hr_p90_p10"]["early"], "hr_late": v["hr_p90_p10"]["late"]} for k, v in runs.items() if k != "main"}
    worst = max(abs(math.log(v["hr_early"] / main["early"])) for v in reruns.values())
    worst = max(worst, max(abs(math.log(v["hr_late"] / main["late"])) for v in reruns.values()))
    return {"main": {"hr_early": main["early"], "hr_late": main["late"]}, "reruns": reruns,
            "max_abs_log_ratio": round(worst, 4)}


def _base_risk(up):
    """10-year risk from the base model (m0: age and sex) with its coefficients fixed, Breslow baseline on the model cohort."""
    rows = model_rows_sorted(up)
    X = np.array([[r["age_per_10y"], r["sex_male"]] for r in rows], float)
    beta = np.array([up["m0"]["coef"]["age_per_10y"], up["m0"]["coef"]["sex_male"]])
    time = np.array([r["time"] for r in rows])
    ev = np.array([r["event"] for r in rows], float)
    times, dh = breslow(X, np.zeros(len(rows)), time, ev, np.ones(len(rows)), beta)
    h10 = float(dh[times <= 10.0].sum())
    return rows, 1 - np.exp(-h10 * np.exp(X @ beta))


def _category(p):
    return int(sum(p >= c for c in RISK_CUTS))


def node_v5(up, src):
    rows, base = _base_risk(up)
    new = np.array([up["v7"]["persons"][str(r["id"])]["risk_10y"] for r in rows])
    w = np.array([up["v0"]["weights"][str(r["id"])]["weight"] for r in rows])
    t = np.array([r["time"] for r in rows])
    e = np.array([r["event"] for r in rows])
    cb, cn = np.array([_category(p) for p in base]), np.array([_category(p) for p in new])
    died = (e == 1) & (t <= 10)
    alive = t > 10
    out = {}
    for label, grp in (("events", died), ("nonevents", alive)):
        tot = (w * grp).sum()
        out[f"up_{label}"] = float((w * grp * (cn > cb)).sum() / tot)
        out[f"down_{label}"] = float((w * grp * (cn < cb)).sum() / tot)
    nri_e = out["up_events"] - out["down_events"]
    nri_n = out["down_nonevents"] - out["up_nonevents"]
    return {"nri": {"events": round(nri_e, 5), "nonevents": round(nri_n, 5), "total": round(nri_e + nri_n, 5)},
            "moves": {k: round(v, 5) for k, v in out.items()}}


def node_v6(up, src):
    ids = sorted(up["v7"]["persons"], key=int)
    risk = np.array([up["v7"]["persons"][i]["risk_10y"] for i in ids])
    w = np.array([up["v0"]["weights"][i]["weight"] for i in ids])
    t = np.array([up["c2"]["persons"][i]["time_years"] for i in ids])
    e = np.array([up["c2"]["persons"][i]["event"] for i in ids])
    died, alive = (e == 1) & (t <= 10), t > 10
    n = len(ids)
    prev = float((w * died).sum() / n)
    nb, nb_all = {}, {}
    for pt in NB_THRESHOLDS:
        sel = risk >= pt
        tp, fp = float((w * died * sel).sum()), float((w * alive * sel).sum())
        nb[f"{pt:.2f}"] = round(tp / n - fp / n * pt / (1 - pt), 5)
        nb_all[f"{pt:.2f}"] = round(prev - (1 - prev) * pt / (1 - pt), 5)
    return {"model": nb, "treat_all": nb_all, "prevalence_10y": round(prev, 5)}


def node_R4(up, src):
    return {"model": up["m4"]["coef"], "optimism": {"apparent_c": up["v2"]["apparent_c"], "corrected_c": up["v2"]["corrected_c"]},
            "discrimination": {"harrell_c": up["v4"]["harrell_c"], "uno_c": up["v4"]["uno_c"]},
            "reclassification": up["v5"]["nri"], "net_benefit": up["v6"]["model"]}


def main(argv):
    """python reference.py <src_dir> <out_dir> --stage S (the kit's own CLI is used inside the task)."""
    from collabbench.graphs.kit import taskgraph as tg
    g = tg.load_graph(Path(__file__).parent / "graph.json")
    tg.write_outputs(g, tg.run_reference(g, types.SimpleNamespace(**globals()), argv[1], int(argv[argv.index("--stage") + 1])), argv[2])


if __name__ == "__main__":
    main(sys.argv)
