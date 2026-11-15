"""Reference for the aldol graph: one pure function per node, node_<id>(up, src) (standard library only).

    python reference.py <src_dir> <out_dir> --stage S     writes every node output of stage <= S under <out_dir>

`src` is a directory laid out like the workspace (data/injections.csv, data/experiments.csv, docs/...). The constants
are the lab's own practice (graph.json facts a1..b12); the full set is reproduced here so later stages reuse them. This
stage 1 implements levels 1-3 (the shared trunk): k1, k2, k3, k4, f1, k5, k6. The authors' published concentrations are reproduced
with the same constants and the dilution map of k3 (see tests/graphs/test_aldol.py and the review file).
"""

import csv
import math
import sys
from pathlib import Path

# fact a1: the calibration PA = 1731.36 c + 172.70 (c in mmol/L as injected)
CAL_SLOPE, CAL_OFFSET = 1731.36, 172.70
# fact a5: experiment 1 was evaluated with the earlier calibration PA = 1755.1 c, through the origin
OLD_CAL_EXP, OLD_CAL_SLOPE = 1, 1755.1
# fact a12: only L-anti standards were run; syn is quantified with the same calibration
SYN_SHARES_CAL = True
# fact a9: the flow and recycle experiments ran on 0.45 mol/L glycine
GLY_FLOW = 0.45
# facts a2-a4, a6-a8 (the dilution map; node k3 builds on them in a later stage, tests/graphs/test_aldol.py checks them now)
DILUTION = 5.0
TENFOLD_EXPS = {23, 24}
TENFOLD_SAMPLES = {(21, 24.0), (22, 24.0)}
MIXED_2_EXPS, MIXED_2_LATER = {59, 60, 61}, 2.0
NEAT_EXPS = {62, 63, 64, 67}
SWITCH_EXPS, SWITCH_AFTER = {65, 66}, 2
# fact a10: the one-phase batch series was sampled on a 10 min grid below 2 h; its hours column is rounded
GRID_SERIES, GRID_STEP_H, GRID_BELOW_H = "batch1p", 1 / 6, 2
# fact a11: the membrane module's channel volume is 243 microlitres; residence time = volume / flow rate
CHANNEL_UL = 243.0
# fact b1: the sample at time 0 is a blank: both concentrations are set to zero
BLANK_IS_ZERO = True
# fact b6: a sample at or before 6 h whose total peak area is below 95 % of the highest earlier valid total is an outlier
OUTLIER_FRACTION, OUTLIER_UNTIL_H = 0.95, 6.0
# decision Q4: the screen is for the batch, membrane and recycle time courses; flow runs are not screened
SCREENED_EXCLUDES = ("flow",)
MODES = ("batch2p", "membrane", "batch1p", "flow", "recycle")


def _num(x):
    return float(x) if x != "" else None


def _read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def node_k1(up, src):
    """One row per experiment: mode, the conditions (glycine recovered for flow and recycle) and the sampling plan."""
    src = Path(src)
    times = {}
    for r in _read(src / "data" / "injections.csv"):
        times.setdefault(int(r["exp"]), []).append(float(r["t_h"]))
    rows = []
    for r in sorted(_read(src / "data" / "experiments.csv"), key=lambda r: int(r["exp"])):
        exp, mode = int(r["exp"]), r["series"]
        gly = _num(r["gly_m"])
        if gly is None and mode in ("flow", "recycle"):
            gly = GLY_FLOW
        rows.append({"exp": exp, "mode": mode, "temp_c": _num(r["temp_c"]), "gly_m": gly,
                     "dmso_pct": _num(r["dmso_pct"]), "flow_ul_min": _num(r["flow_ul_min"]),
                     "n_samples": len(times[exp]), "final_t_h": max(times[exp])})
    return rows


def calibration(exp: int, peak: int = 0) -> tuple[float, float]:
    """(slope, offset) of the line PA = slope * c + offset that converts experiment `exp`'s peak (0 anti, 1 syn)."""
    if exp == OLD_CAL_EXP:
        return OLD_CAL_SLOPE, 0.0
    if peak == 1 and not SYN_SHARES_CAL:
        return CAL_SLOPE, 0.0
    return CAL_SLOPE, CAL_OFFSET


def dilution(exp: int, sample: int, t_h: float) -> float:
    """The dilution factor of an injection (facts a2-a4, a6-a8)."""
    if exp in TENFOLD_EXPS or (exp, t_h) in TENFOLD_SAMPLES:
        return 10.0
    if exp in MIXED_2_EXPS:
        return DILUTION if sample == 1 else MIXED_2_LATER
    if exp in NEAT_EXPS:
        return 1.0
    if exp in SWITCH_EXPS:
        return 1.0 if sample <= SWITCH_AFTER else DILUTION
    return DILUTION


def node_k2(up, src):
    """One row per injection: the calibration line each of its two peaks is converted with."""
    rows = []
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        exp = int(r["exp"])
        (am, ao), (sm, so) = calibration(exp, 0), calibration(exp, 1)
        rows.append({"exp": exp, "sample": int(r["sample"]), "anti_slope": am, "anti_offset": ao,
                     "syn_slope": sm, "syn_offset": so})
    return rows


def _by_key(rows):
    return {(int(r["exp"]), int(r["sample"])): r for r in rows}


def node_k3(up, src):
    """One row per injection: its dilution factor (empty for sample 0, the blank, which has no dilution to report)."""
    rows = []
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        exp, n = int(r["exp"]), int(r["sample"])
        rows.append({"exp": exp, "sample": n, "dilution": None if n == 0 else dilution(exp, n, float(r["t_h"]))})
    return rows


def sample_time(series: str, t_h: float) -> float:
    if series == GRID_SERIES and t_h < GRID_BELOW_H:
        return round(t_h / GRID_STEP_H) * GRID_STEP_H
    return t_h


def node_k4(up, src):
    """One row per injection: the true hours since the start (the one-phase batch grid undone)."""
    src = Path(src)
    series = {int(r["exp"]): r["series"] for r in _read(src / "data" / "experiments.csv")}
    return [{"exp": int(r["exp"]), "sample": int(r["sample"]), "t_true_h": sample_time(series[int(r["exp"])], float(r["t_h"]))}
            for r in sorted(_read(src / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"])))]


def node_f1(up, src):
    """One row per flow experiment: the residence time in hours."""
    return [{"exp": int(r["exp"]), "residence_h": CHANNEL_UL / float(r["flow_ul_min"]) / 60}
            for r in sorted(_read(Path(src) / "data" / "experiments.csv"), key=lambda r: int(r["exp"])) if r["series"] == "flow"]


def node_k5(up, src):
    """One row per injection: anti and syn concentration in mmol/L in the reaction mixture."""
    cal, dil, tim = _by_key(up["k2"]), _by_key(up["k3"]), _by_key(up["k4"])
    rows = []
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        key = (int(r["exp"]), int(r["sample"]))
        if BLANK_IS_ZERO and tim[key]["t_true_h"] == 0:
            ca = cs = 0.0
        else:
            k, d = cal[key], dil[key]["dilution"]
            ca = d * (float(r["pa_anti"]) - k["anti_offset"]) / k["anti_slope"]
            cs = d * (float(r["pa_syn"]) - k["syn_offset"]) / k["syn_slope"]
        rows.append({"exp": key[0], "sample": key[1], "c_anti": ca, "c_syn": cs})
    return rows


def node_k6(up, src):
    """One row per injection: accepted (1) or rejected (0) by the lab's outlier rule."""
    src = Path(src)
    series = {int(r["exp"]): r["series"] for r in _read(src / "data" / "experiments.csv")}
    tim = _by_key(up["k4"])
    by_exp = {}
    for r in sorted(_read(src / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        by_exp.setdefault(int(r["exp"]), []).append(r)
    rows = []
    for exp, inj in by_exp.items():
        best = 0.0
        for r in inj:
            n = int(r["sample"])
            total = float(r["pa_anti"]) + float(r["pa_syn"])
            screened = series[exp] not in SCREENED_EXCLUDES and n > 0 and tim[(exp, n)]["t_true_h"] <= OUTLIER_UNTIL_H
            bad = screened and best and total < OUTLIER_FRACTION * best
            if screened and not bad:
                best = max(best, total)
            rows.append({"exp": exp, "sample": n, "accepted": 0 if bad else 1})
    return rows


# ---- stage 2: levels 4-5 ------------------------------------------------------------------------------------------------
# fact b4: the end point of a batch or membrane experiment is its last valid sample at or before 6 h
END_H = 6.0
# fact b11: the end point of a recycle experiment is its last sample
# fact b5: the steady state of a flow experiment is the mean of its samples 4 to 6
STEADY_FROM = 4
# fact b2: yield = 100 (c_anti + c_syn) / (1000 c_glycine); fact b3: the ratio is syn / anti of the peak areas
YIELD_SCALE = 100.0
# fact b7: initial rate = least-squares slope of the total concentration over valid samples at or before 2 h, blank included
RATE_WINDOW_H = 2.0
# fact b8: k from c = c_inf (1 - exp(-k t)) over valid samples at or before 6 h, blank included
FIT_WINDOW_H = 6.0
# fact b12: an experiment whose end-point yield is below 1 % gets no rate and no fit
MIN_FIT_YIELD = 1.0
# fact b9: Ea = -R slope(ln k, 1/T), T = degC + 273.15, R = 8.314 J/(mol K), in kJ/mol; fact b10: the reference group
KELVIN, GAS_R = 273.15, 8.314
GROUP_GLY, GROUP_DMSO = 1.0, 25.0


def slope(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)


def fit_first_order(ts, ys):
    """(c_inf, k) minimising the squared error of c_inf (1 - exp(-k t)): the best c_inf is linear for each k; k is found
    by golden-section search on a bracket refined from a coarse scan."""
    def sse(k):
        g = [1 - math.exp(-k * t) for t in ts]
        den = sum(x * x for x in g)
        cinf = sum(x * y for x, y in zip(g, ys)) / den if den else 0.0
        return sum((cinf * x - y) ** 2 for x, y in zip(g, ys)), cinf
    grid = [10 ** (e / 40) for e in range(-120, 81)]
    best = min(range(len(grid)), key=lambda i: sse(grid[i])[0])
    a, b = grid[max(best - 1, 0)], grid[min(best + 1, len(grid) - 1)]
    phi = (math.sqrt(5) - 1) / 2
    for _ in range(100):
        c, d = b - phi * (b - a), a + phi * (b - a)
        if sse(c)[0] < sse(d)[0]:
            b = d
        else:
            a = c
    k = (a + b) / 2
    return sse(k)[1], k


def arrhenius(k_by_temp):
    temps = sorted(k_by_temp)
    if min(k_by_temp.values()) <= 0:
        return 0.0
    return -GAS_R * slope([1 / (t + KELVIN) for t in temps], [math.log(k_by_temp[t]) for t in temps]) / 1000


def _mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def _study(up, src):
    """{exp: [row]} with each injection's true time, peak areas, concentrations and validity, plus mode and glycine."""
    c5, t4 = _by_key(up["k5"]), _by_key(up["k4"])
    k6 = _by_key(up["k6"]) if "k6" in up else None  # p1 does not read the screen (no one-phase batch sample is flagged)
    reg = {r["exp"]: r for r in up["k1"]}
    rows = {}
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        key = (int(r["exp"]), int(r["sample"]))
        rows.setdefault(key[0], []).append({
            "n": key[1], "t": t4[key]["t_true_h"], "pa": (float(r["pa_anti"]), float(r["pa_syn"])),
            "c": (c5[key]["c_anti"], c5[key]["c_syn"]), "valid": k6 is None or k6[key]["accepted"] == 1})
    return rows, reg


def _end(rows, mode):
    valid = [r for r in rows if r["valid"]]
    if mode == "recycle":
        return valid[-1]
    return [r for r in valid if r["t"] <= END_H][-1]


def _yield(c, gly):
    return YIELD_SCALE * (c[0] + c[1]) / (1000 * gly)


def _endpoints(up, src, mode):
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != mode:
            continue
        e = _end(rows[exp], mode)
        out.append({"exp": exp, "end_sample": e["n"], "end_t_h": e["t"], "yield_pct": _yield(e["c"], reg[exp]["gly_m"]),
                    "ratio": e["pa"][1] / e["pa"][0]})
    return out


def _rates(up, src, mode):
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != mode:
            continue
        valid = [r for r in rows[exp] if r["valid"]]
        fitted = _yield(_end(rows[exp], mode)["c"], reg[exp]["gly_m"]) >= MIN_FIT_YIELD
        row = {"exp": exp, "fitted": int(fitted), "initial_rate": None, "c_inf": None, "k": None}
        if fitted:
            win = [r for r in valid if r["t"] <= RATE_WINDOW_H]
            row["initial_rate"] = slope([r["t"] for r in win], [sum(r["c"]) for r in win])
            fit = [r for r in valid if r["t"] <= FIT_WINDOW_H]
            row["c_inf"], row["k"] = fit_first_order([r["t"] for r in fit], [sum(r["c"]) for r in fit])
        out.append(row)
    return out


def node_b1(up, src):
    """End point of each two-phase batch experiment."""
    return _endpoints(up, src, "batch2p")


def node_m1(up, src):
    """End point of each membrane experiment."""
    return _endpoints(up, src, "membrane")


def node_b2(up, src):
    """Initial rate and first-order fit of each two-phase batch experiment."""
    return _rates(up, src, "batch2p")


def node_m2(up, src):
    """Initial rate and first-order fit of each membrane experiment."""
    return _rates(up, src, "membrane")


def node_p1(up, src):
    """Yield against the corrected time of each one-phase batch run, and its initial rate."""
    rows, reg = _study(up, src)
    curve, rate = {}, {}
    for exp in sorted(rows):
        if reg[exp]["mode"] != "batch1p":
            continue
        valid = [r for r in rows[exp] if r["valid"]]
        for r in valid:
            if r["n"] > 0:
                curve[f"{exp}|{r['n']}"] = {"t_h": r["t"], "yield_pct": _yield(r["c"], reg[exp]["gly_m"])}
        win = [r for r in valid if r["t"] <= RATE_WINDOW_H]
        rate[str(exp)] = slope([r["t"] for r in win], [sum(r["c"]) for r in win])
    return {"curve": curve, "initial_rate": rate}


def node_f2(up, src):
    """Steady state of each flow run: the mean of samples 4 to 6."""
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != "flow":
            continue
        ss = [r for r in rows[exp] if r["n"] >= STEADY_FROM]
        c = tuple(_mean(r["c"][p] for r in ss) for p in (0, 1))
        pa = tuple(_mean(r["pa"][p] for r in ss) for p in (0, 1))
        out.append({"exp": exp, "c_anti": c[0], "c_syn": c[1], "yield_pct": _yield(c, reg[exp]["gly_m"]), "ratio": pa[1] / pa[0]})
    return out


def node_r1(up, src):
    """Per-pass and cumulative yield of each recycle run, and its end point."""
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != "recycle":
            continue
        end = _end(rows[exp], "recycle")["n"]
        prev = 0.0
        for r in rows[exp]:
            if r["n"] == 0:
                continue
            y = _yield(r["c"], reg[exp]["gly_m"])
            out.append({"exp": exp, "sample": r["n"], "t_true_h": r["t"], "cumulative_yield_pct": y,
                        "pass_yield_pct": y - prev, "end_point": int(r["n"] == end)})
            prev = y
    return out


def node_f3(up, src):
    """Conversion of the flow runs against residence time, and a first-order fit across them."""
    tau = {r["exp"]: r["residence_h"] for r in up["f1"]}
    pts = sorted((tau[r["exp"]], r["yield_pct"] / 100) for r in up["f2"])
    by = {}
    for t, x in pts:
        by.setdefault(f"{t:.4f}", []).append(x)
    x_inf, k = fit_first_order([t for t, _ in pts], [x for _, x in pts])
    rmse = math.sqrt(_mean((x_inf * (1 - math.exp(-k * t)) - x) ** 2 for t, x in pts))
    return {"mean_conversion": {t: _mean(v) for t, v in by.items()}, "fit": {"x_inf": x_inf, "k_per_h": k, "rmse": rmse},
            "n_runs": len(pts)}


def _conditions(src):
    return {int(r["exp"]): {"mode": r["series"], **{k: (float(r[k]) if r[k] != "" else None) for k in ("temp_c", "gly_m", "dmso_pct")}}
            for r in _read(Path(src) / "data" / "experiments.csv")}


def _cond_key(c):
    return f"{c['temp_c']:g}|{c['gly_m']:g}|{c['dmso_pct']:g}"


def node_x1(up, src):
    """Batch and membrane runs paired on temperature, glycine and DMSO (Q1: replicate runs are pooled by their mean yield)."""
    cond = _conditions(src)
    pools = {"batch2p": {}, "membrane": {}}
    for mode, rows in (("batch2p", up["b1"]), ("membrane", up["m1"])):
        for r in rows:
            pools[mode].setdefault(_cond_key(cond[r["exp"]]), []).append(r["yield_pct"])
    pairs = {}
    for key in sorted(set(pools["batch2p"]) & set(pools["membrane"])):
        b, m = pools["batch2p"][key], pools["membrane"][key]
        pairs[key] = {"batch_yield_pct": _mean(b), "membrane_yield_pct": _mean(m), "difference_pct": _mean(m) - _mean(b),
                      "n_batch": len(b), "n_membrane": len(m)}
    return {"pairs": pairs, "n_pairs": len(pairs)}


def _in_group(c):
    return c["gly_m"] == GROUP_GLY and c["dmso_pct"] == GROUP_DMSO


def node_x2(up, src):
    """Activation energy from the rate constants at 20, 30 and 40 degC: the membrane reference group, and batch runs at the
    same glycine and DMSO."""
    cond = _conditions(src)
    k_group = {}
    for r in up["m2"]:
        c = cond[r["exp"]]
        if r["fitted"] and _in_group(c):
            k_group.setdefault(c["temp_c"], []).append(r["k"])
    group_size = {}
    for r in up["m2"]:
        if _in_group(cond[r["exp"]]):
            group_size[f"{cond[r['exp']]['temp_c']:g}"] = group_size.get(f"{cond[r['exp']]['temp_c']:g}", 0) + 1
    kmean = {t: _mean(v) for t, v in k_group.items()}
    kb = {}
    for r in up["b2"]:
        c = cond[r["exp"]]
        if r["fitted"] and _in_group(c):
            kb.setdefault(c["temp_c"], []).append(r["k"])
    kbm = {t: _mean(v) for t, v in kb.items()}
    return {"membrane": {"k_mean_by_temp": {f"{t:g}": v for t, v in sorted(kmean.items())}, "ea_kj_mol": arrhenius(kmean),
                         "group_size": dict(sorted(group_size.items()))},
            "batch": {"k_by_temp": {f"{t:g}": v for t, v in sorted(kbm.items())}, "ea_kj_mol": arrhenius(kbm)}}


SURFACE_TERMS = ["intercept", "temp_c", "dmso_pct", "gly_m", "temp_c2", "dmso_pct2", "gly_m2", "membrane"]


def _ols(rows, ys):
    import numpy as np
    X = np.array(rows, float)
    y = np.array(ys, float)
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    resid = y - X @ beta
    r2 = 1 - float(resid @ resid) / float(((y - y.mean()) ** 2).sum())
    return {"coef": {n: float(b) for n, b in zip(SURFACE_TERMS, beta)}, "r2": r2, "n": len(ys)}


def node_x3(up, src):
    """Yield and initial rate as quadratic functions of temperature, DMSO and glycine, batch and membrane pooled with a mode term."""
    cond = _conditions(src)
    def row(e, membrane):
        c = cond[e]
        return [1.0, c["temp_c"], c["dmso_pct"], c["gly_m"], c["temp_c"] ** 2, c["dmso_pct"] ** 2, c["gly_m"] ** 2, float(membrane)]
    yx, yy, rx, ry = [], [], [], []
    for membrane, ends, rates in ((0, up["b1"], up["b2"]), (1, up["m1"], up["m2"])):
        for r in ends:
            yx.append(row(r["exp"], membrane))
            yy.append(r["yield_pct"])
        for r in rates:
            if r["fitted"]:
                rx.append(row(r["exp"], membrane))
                ry.append(r["initial_rate"])
    return {"yield": _ols(yx, yy), "rate": _ols(rx, ry)}


def node_y2(up, src):
    """Space-time yield (mmol/L/h) of each process mode: the end-point (or steady-state) total concentration over the time
    it took (the residence time for flow)."""
    reg = {r["exp"]: r for r in up["k1"]}
    sty = {"batch2p": [], "membrane": [], "batch1p": [], "flow": [], "recycle": []}
    for rows in (up["b1"], up["m1"]):
        for r in rows:
            sty[reg[r["exp"]]["mode"]].append(10 * reg[r["exp"]]["gly_m"] * r["yield_pct"] / r["end_t_h"])
    tau = {r["exp"]: r["residence_h"] for r in up["f1"]}
    for r in up["f2"]:
        sty["flow"].append(10 * reg[r["exp"]]["gly_m"] * r["yield_pct"] / tau[r["exp"]])
    ends = {}
    for r in up["r1"]:
        if r["end_point"]:
            sty["recycle"].append(10 * reg[r["exp"]]["gly_m"] * r["cumulative_yield_pct"] / r["t_true_h"])
    for key, v in up["p1"]["curve"].items():
        exp = int(key.split("|")[0])
        if v["t_h"] <= END_H and (exp not in ends or v["t_h"] > ends[exp][0]):
            ends[exp] = (v["t_h"], v["yield_pct"])
    for exp, (t, y) in ends.items():
        sty["batch1p"].append(10 * reg[exp]["gly_m"] * y / t)
    return {"sty": {m: {"mean": _mean(v), "max": max(v)} for m, v in sty.items()}}


# ---- stage 3: levels 6-9 ------------------------------------------------------------------------------------------------
# decision Q2: the mechanism is reversible aldol (best joint SSE of irreversible, reversible and with enzyme decay)
# model: p(t) = kf G0 / (kf + k2) (1 - exp(-(kf + k2) t)), G0 = 1000 c_glycine (mmol/L), p the total phenylserine;
# kf = kf30 exp(-Ea/R (1/T - 1/303.15)) exp(bD (DMSO - 25)/25), one (kf30, k2, bD) per mode; Ea is x2's membrane value, fixed
MODEL_MODES = ("batch2p", "membrane")
PARAMS = ("kf30", "k2", "dmso_exp")
T_REF = 303.15
# x5: a run is systematic when |mean residual| > 0.5 rmse; a correction is accepted when it cuts the run's SSE by >= 75 % and
# leaves the run non-systematic; candidates are restoring a rejected sample or changing one sample's dilution to 1, 2, 5 or 10
SYSTEMATIC_RMSE_FRACTION, ACCEPT_CUT = 0.5, 0.75
# x7: a 95 % profile interval is the set of values whose re-optimised SSE is below SSE* (1 + 3.84 / (n - 3)), per mode
CHI2_95 = 3.84
LOG_LIMIT = 6.0
# Q3: the flow runs have no temperature or DMSO on file: they are taken at the lab's standard 20 degC and 25 vol.% DMSO
FLOW_TEMP_C, FLOW_DMSO_PCT = 20.0, 25.0


def _np():
    import numpy as np
    return np


def _model(mode_p, t, T, G0, D, ea_kj):
    np = _np()
    kf30, k2, bd = mode_p
    kf = kf30 * np.exp(-ea_kj * 1000 / GAS_R * (1 / T - 1 / T_REF)) * np.exp(bd * (D - 25) / 25)
    return kf * G0 / (kf + k2) * (1 - np.exp(-(kf + k2) * t))


def _nelder_mead(f, x0, step, tol=1e-13, maxit=6000):
    np = _np()
    n = len(x0)
    pts = [np.array(x0, float)] + [np.array(x0, float) + step * np.eye(n)[i] for i in range(n)]
    vals = [f(p) for p in pts]
    for _ in range(maxit):
        idx = sorted(range(n + 1), key=lambda i: vals[i])
        pts, vals = [pts[i] for i in idx], [vals[i] for i in idx]
        if abs(vals[-1] - vals[0]) <= tol * (abs(vals[0]) + tol):
            break
        c = sum(pts[:-1]) / n
        xr = c + (c - pts[-1])
        fr = f(xr)
        if fr < vals[0]:
            xe = c + 2 * (c - pts[-1])
            fe = f(xe)
            pts[-1], vals[-1] = (xe, fe) if fe < fr else (xr, fr)
        elif fr < vals[-2]:
            pts[-1], vals[-1] = xr, fr
        else:
            xc = c + 0.5 * (pts[-1] - c)
            fc = f(xc)
            if fc < vals[-1]:
                pts[-1], vals[-1] = xc, fc
            else:
                pts = [pts[0]] + [pts[0] + 0.5 * (q - pts[0]) for q in pts[1:]]
                vals = [vals[0]] + [f(q) for q in pts[1:]]
    i = min(range(n + 1), key=lambda j: vals[j])
    return pts[i], vals[i]


def _joint_data(up, src, mode_of, valid_of=None, scale=None):
    """Per modelled mode the arrays of valid, non-blank samples: exp, sample, t, T (K), G0, DMSO, total concentration."""
    np = _np()
    cond = _conditions(src)
    k5, k4 = _by_key(up["k5"]), _by_key(up["k4"])
    k6 = _by_key(up["k6"])
    cols = {m: [] for m in MODEL_MODES}
    for (exp, n), r in sorted(k5.items()):
        mode = mode_of[exp]
        if mode not in cols or n == 0:
            continue
        valid = k6[(exp, n)]["accepted"] == 1
        y = r["c_anti"] + r["c_syn"]
        if valid_of is not None and (exp, n) in valid_of:
            valid = True
        if scale and (exp, n) in scale:
            y *= scale[(exp, n)]
        if not valid:
            continue
        c = cond[exp]
        cols[mode].append((exp, n, k4[(exp, n)]["t_true_h"], c["temp_c"] + KELVIN, 1000 * c["gly_m"], c["dmso_pct"], y))
    return {m: np.array(v, float) for m, v in cols.items()}


def _sse_fn(arr, ea_kj):
    t, T, G0, D, y = arr[:, 2], arr[:, 3], arr[:, 4], arr[:, 5], arr[:, 6]
    def sse(p):
        q = (math.exp(min(max(p[0], -30), 5)), math.exp(min(max(p[1], -30), 5)), p[2])
        return float(((_model(q, t, T, G0, D, ea_kj) - y) ** 2).sum())
    return sse


def _fit_mode(arr, ea_kj):
    f = _sse_fn(arr, ea_kj)
    best = None
    for x0 in ([-3.5, -1.0, 0.5], [-3.0, -2.0, 0.0], [-4.5, -1.0, 1.0]):
        x, v = _nelder_mead(f, x0, 0.4)
        x, v = _nelder_mead(f, x, 0.05)
        if best is None or v < best[1]:
            best = (x, v)
    x, v = best
    return (math.exp(x[0]), math.exp(x[1]), float(x[2])), v


def _fit_result(up, src, mode_of, ea_kj, **kw):
    data = _joint_data(up, src, mode_of, **kw)
    params, sse, n = {}, {}, {}
    for m in MODEL_MODES:
        p, v = _fit_mode(data[m], ea_kj)
        params[m], sse[m], n[m] = dict(zip(PARAMS, p)), v, len(data[m])
    sse["total"] = sse["batch2p"] + sse["membrane"]
    return {"params": params, "sse": sse, "rmse": math.sqrt(sse["total"] / (n["batch2p"] + n["membrane"])), "n_points": n}


def node_x4(up, src):
    """The kinetic model (Q2: reversible aldol) fitted jointly to every two-phase batch and membrane time course."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    ea = up["x2"]["membrane"]["ea_kj_mol"]
    return {"mechanism": "reversible", "ea_fixed_kj_mol": ea, **_fit_result(up, src, mode_of, ea)}


def _run_residuals(arr_rows, p, ea):
    np = _np()
    return arr_rows[:, 6] - _model(p, arr_rows[:, 2], arr_rows[:, 3], arr_rows[:, 4], arr_rows[:, 5], ea)


def _run_stats(up, src, fit):
    """{exp: dict} residual statistics of every modelled run under the fit."""
    np = _np()
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    ea, rmse = fit["ea_fixed_kj_mol"], fit["rmse"]
    data = _joint_data(up, src, mode_of)
    out = {}
    for m in MODEL_MODES:
        p = tuple(fit["params"][m][k] for k in PARAMS)
        arr = data[m]
        res = _run_residuals(arr, p, ea)
        for exp in sorted({int(e) for e in arr[:, 0]}):
            sel = arr[:, 0] == exp
            mean = float(res[sel].mean())
            out[exp] = {"mode": m, "mean": mean, "systematic": int(abs(mean) > SYSTEMATIC_RMSE_FRACTION * rmse),
                        "sse": float((res[sel] ** 2).sum()), "p": p}
    return out, data


def _best_correction(up, src, fit, exp, stat, mode_of):
    """The single-sample upstream correction that most reduces the run's SSE: (cut, kind, sample, value, mean_after)."""
    np = _np()
    ea, rmse = fit["ea_fixed_kj_mol"], fit["rmse"]
    cond = _conditions(src)[exp]
    k5, k4, k6, k3 = _by_key(up["k5"]), _by_key(up["k4"]), _by_key(up["k6"]), _by_key(up["k3"])
    samples = sorted(n for (e, n) in k5 if e == exp and n > 0)
    def run_sse(change):
        res = []
        for n in samples:
            valid = k6[(exp, n)]["accepted"] == 1
            y = k5[(exp, n)]["c_anti"] + k5[(exp, n)]["c_syn"]
            if change and change[0] == n:
                if change[1] == "restore":
                    valid = True
                else:
                    y *= change[2] / k3[(exp, n)]["dilution"]
            if valid:
                res.append(y - float(_model(stat["p"], k4[(exp, n)]["t_true_h"], cond["temp_c"] + KELVIN, 1000 * cond["gly_m"],
                                            cond["dmso_pct"], ea)))
        return sum(v * v for v in res), sum(res) / len(res)
    best = None
    for n in samples:
        if k6[(exp, n)]["accepted"] == 0:
            trials = [(n, "restore", None)]
        else:
            trials = [(n, "dilution", d) for d in (1.0, 2.0, 5.0, 10.0) if d != k3[(exp, n)]["dilution"]]
        for tr in trials:
            sse, mean = run_sse(tr)
            cut = 1 - sse / stat["sse"]
            if best is None or cut > best[0]:
                best = (cut, tr[1], n, tr[2], mean)
    return best


def node_x5(up, src):
    """Residual review of the joint fit: which runs are systematic, and whether any single upstream correction explains them."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    fit = up["x4"]
    stats, _ = _run_stats(up, src, fit)
    rows = []
    for exp in sorted(stats):
        st = stats[exp]
        row = {"exp": exp, "systematic": st["systematic"], "mean_residual": None, "best_cut": None, "accepted": 0}
        if st["systematic"]:
            cut, kind, n, value, mean_after = _best_correction(up, src, fit, exp, st, mode_of)
            row["mean_residual"], row["best_cut"] = st["mean"], max(cut, 0.0)
            row["accepted"] = int(cut >= ACCEPT_CUT and abs(mean_after) <= SYSTEMATIC_RMSE_FRACTION * fit["rmse"])
        rows.append(row)
    return rows


def _accepted_corrections(up, src, fit, review):
    """The (restore set, dilution scale) of the review's accepted corrections."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    stats, _ = _run_stats(up, src, fit)
    restore, scale = set(), {}
    k3 = _by_key(up["k3"])
    for r in review:
        if r["accepted"]:
            cut, kind, n, value, _m = _best_correction(up, src, fit, r["exp"], stats[r["exp"]], mode_of)
            if kind == "restore":
                restore.add((r["exp"], n))
            else:
                scale[(r["exp"], n)] = value / k3[(r["exp"], n)]["dilution"]
    return restore, scale


def node_x6(up, src):
    """x4 refitted after the corrections x5 accepted (they flow back through the concentrations); none are accepted on this data."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    fit4 = up["x4"]
    restore, scale = _accepted_corrections(up, src, fit4, up["x5"])
    res = _fit_result(up, src, mode_of, fit4["ea_fixed_kj_mol"], valid_of=restore, scale=scale)
    return {"mechanism": "reversible", "ea_fixed_kj_mol": fit4["ea_fixed_kj_mol"], "corrections_applied": len(restore) + len(scale), **res}


def node_x7(up, src):
    """Which parameters the data pin down: 95 % profile intervals per mode."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    fit = up["x6"]
    ea = fit["ea_fixed_kj_mol"]
    data = _joint_data(up, src, mode_of)
    out = {}
    for m in MODEL_MODES:
        arr = data[m]
        f = _sse_fn(arr, ea)
        base = [math.log(fit["params"][m]["kf30"]), math.log(fit["params"][m]["k2"]), fit["params"][m]["dmso_exp"]]
        sse0 = f(base)
        thr = sse0 * (1 + CHI2_95 / (len(arr) - 3))
        out[m] = {}
        for j, name in enumerate(PARAMS):
            def prof(v):
                free = [i for i in range(3) if i != j]
                def g(q):
                    x = list(base)
                    x[j] = v
                    x[free[0]], x[free[1]] = q[0], q[1]
                    return f(x)
                return _nelder_mead(g, [base[i] for i in free], 0.2, tol=1e-12, maxit=800)
            bounds = []
            for sign in (-1, 1):
                lo, hi, step, found = 0.0, None, 0.05, False
                while step <= LOG_LIMIT * (1 if j < 2 else 4):
                    x, v = prof(base[j] + sign * step)
                    if v > thr:
                        hi, found = step, True
                        break
                    lo = step
                    step *= 1.6
                if not found:
                    bounds.append(None)
                    continue
                for _ in range(30):
                    mid = (lo + hi) / 2
                    x, v = prof(base[j] + sign * mid)
                    lo, hi = (mid, hi) if v <= thr else (lo, mid)
                bounds.append(base[j] + sign * (lo + hi) / 2)
            conv = (lambda v: None if v is None else math.exp(v)) if j < 2 else (lambda v: v)
            out[m][name] = {"lo": conv(bounds[0]), "hi": conv(bounds[1]), "identifiable": int(None not in bounds)}
    return out


def node_y1(up, src):
    """Flow conversion predicted by the membrane batch model at each residence time, against the measurements (Q3)."""
    gly = next(r["gly_m"] for r in up["k1"] if r["mode"] == "flow")
    p = tuple(up["x6"]["params"]["membrane"][k] for k in PARAMS)
    ea = up["x6"]["ea_fixed_kj_mol"]
    np = _np()
    by, errs = {}, []
    for tau, measured in sorted(up["f3"]["mean_conversion"].items()):
        pred = float(_model(p, float(tau), FLOW_TEMP_C + KELVIN, 1000 * gly, FLOW_DMSO_PCT, ea)) / (1000 * gly)
        by[tau] = {"predicted": pred, "measured": measured, "ratio": pred / measured}
        errs.append((pred - measured) ** 2)
    return {"assumed": {"temp_c": FLOW_TEMP_C, "dmso_pct": FLOW_DMSO_PCT}, "by_tau": by, "rmse": math.sqrt(_mean(errs))}


def node_R2(up, src):
    """The QC certificate: every sample the lab excludes and every dilution that departs from the usual 1:5, each with its
    justification number (the exclusion ratio or the dilution factor)."""
    k6, k3 = _by_key(up["k6"]), _by_key(up["k3"])
    rows = [_read(Path(src) / "data" / "injections.csv")][0]
    total = {(int(r["exp"]), int(r["sample"])): float(r["pa_anti"]) + float(r["pa_syn"]) for r in rows}
    out = []
    best = {}
    for (exp, n) in sorted(k6):
        if n == 0:
            continue
        if k6[(exp, n)]["accepted"] == 1:
            best[exp] = max(best.get(exp, 0.0), total[(exp, n)])
        else:
            out.append({"kind": "exclusion", "exp": exp, "sample": n, "value": total[(exp, n)] / best[exp]})
    for (exp, n), r in sorted(k3.items()):
        if n > 0 and r["dilution"] != DILUTION:
            out.append({"kind": "dilution", "exp": exp, "sample": n, "value": r["dilution"]})
    return out


# ---- stage 4: levels 10-13 ----------------------------------------------------------------------------------------------
# z1: the operating window is the tested range of x3's factors (the lowest and highest level of S2) and the 6 h end point
# z2: B = 200 bootstrap resamples of the 51 experiments, numpy.random.RandomState(20261115).randint(0, 51, 51) each, in
#     experiment order; degenerate (rank < 8) resamples are counted and skipped
BOOT_N, BOOT_SEED = 200, 20261115
WINDOW_FRACTION = 0.9
T_975_DF1 = 12.706204736432095  # Student t, 97.5 %, one degree of freedom (three temperatures, two fitted terms)


def _surface_optimum(coef, ranges):
    """The maximiser of the separable quadratic surface over the box (membrane runs): per factor, the best of its two
    ends and, for a concave term, its vertex when inside the range; and the unconstrained vertex of each factor."""
    best, vertex = {}, {}
    for var, sq in (("temp_c", "temp_c2"), ("dmso_pct", "dmso_pct2"), ("gly_m", "gly_m2")):
        lo, hi = ranges[var]
        b1, b2 = coef[var], coef[sq]
        f = lambda x: b1 * x + b2 * x * x  # noqa: E731
        cands = [lo, hi]
        vertex[var] = -b1 / (2 * b2) if b2 else None
        if b2 < 0 and lo < vertex[var] < hi:
            cands.append(vertex[var])
        best[var] = max(cands, key=f)
    return best, vertex


def _surface_value(coef, x, membrane=1.0):
    return (coef["intercept"] + coef["temp_c"] * x["temp_c"] + coef["dmso_pct"] * x["dmso_pct"] + coef["gly_m"] * x["gly_m"]
            + coef["temp_c2"] * x["temp_c"] ** 2 + coef["dmso_pct2"] * x["dmso_pct"] ** 2 + coef["gly_m2"] * x["gly_m"] ** 2
            + coef["membrane"] * membrane)


def _ranges(src):
    cond = [c for c in _conditions(src).values() if c["mode"] in MODEL_MODES]
    return {v: (min(c[v] for c in cond), max(c[v] for c in cond)) for v in ("temp_c", "dmso_pct", "gly_m")}


def node_z1(up, src):
    """The operating window: the conditions of the highest predicted yield inside the tested range and the 6 h end point."""
    ranges = _ranges(src)
    cy, cr = up["x3"]["yield"]["coef"], up["x3"]["rate"]["coef"]
    opt, vertex = _surface_optimum(cy, ranges)
    levels = {v: sorted({c[v] for c in _conditions(src).values() if c["mode"] in MODEL_MODES}) for v in ranges}
    best = _surface_value(cy, opt)
    window = sum(1 for t in levels["temp_c"] for d in levels["dmso_pct"] for g in levels["gly_m"]
                 if _surface_value(cy, {"temp_c": t, "dmso_pct": d, "gly_m": g}) >= WINDOW_FRACTION * best)
    p = tuple(up["x6"]["params"]["membrane"][k] for k in PARAMS)
    model6 = float(_model(p, 6.0, opt["temp_c"] + KELVIN, 1000 * opt["gly_m"], opt["dmso_pct"], up["x6"]["ea_fixed_kj_mol"])) / (10 * opt["gly_m"])
    return {"optimum": opt, "yield_pct": best, "rate_at_optimum": _surface_value(cr, opt),
            "model_yield_6h_pct": model6, "window_points": window,
            "kinetic_parameters_identifiable": sum(q["identifiable"] for m in up["x7"].values() for q in m.values()),
            "unconstrained": {"dmso_pct_vertex": vertex["dmso_pct"], "inside_range": int(all(
                ranges[v][0] <= vertex[v] <= ranges[v][1] and cy[sq] < 0 for v, sq in (("temp_c", "temp_c2"), ("dmso_pct", "dmso_pct2"),
                                                                                        ("gly_m", "gly_m2"))))}}


def node_z2(up, src):
    """The optimum of z1 re-solved over a fixed bootstrap of the experiments."""
    np = _np()
    cond = _conditions(src)
    rows = []
    for mode, ends in (("batch2p", up["b1"]), ("membrane", up["m1"])):
        for r in ends:
            c = cond[r["exp"]]
            rows.append((r["exp"], [1.0, c["temp_c"], c["dmso_pct"], c["gly_m"], c["temp_c"] ** 2, c["dmso_pct"] ** 2, c["gly_m"] ** 2,
                                    float(mode == "membrane")], r["yield_pct"]))
    rows.sort()
    X = np.array([r[1] for r in rows])
    y = np.array([r[2] for r in rows])
    ranges = _ranges(src)
    rs = np.random.RandomState(BOOT_SEED)
    choice = {v: {"lo": 0, "hi": 0, "interior": 0} for v in ranges}
    yields, picks, degenerate = [], [], 0
    for _ in range(BOOT_N):
        idx = rs.randint(0, len(rows), len(rows))
        if np.linalg.matrix_rank(X[idx]) < 8:
            degenerate += 1
            continue
        beta, *_ = np.linalg.lstsq(X[idx], y[idx], rcond=None)
        coef = dict(zip(SURFACE_TERMS, (float(b) for b in beta)))
        opt, _v = _surface_optimum(coef, ranges)
        pick = {}
        for v in ranges:
            lo, hi = ranges[v]
            pick[v] = "lo" if abs(opt[v] - lo) < 1e-9 else "hi" if abs(opt[v] - hi) < 1e-9 else "interior"
            choice[v][pick[v]] += 1
        picks.append(tuple(pick[v] for v in ranges))
        yields.append(_surface_value(coef, opt))
    n = len(yields)
    lo, hi = np.percentile(yields, [2.5, 97.5])
    ref_pick = []
    for v in ranges:
        o = up["z1"]["optimum"][v]
        ref_pick.append("lo" if abs(o - ranges[v][0]) < 1e-9 else "hi" if abs(o - ranges[v][1]) < 1e-9 else "interior")
    return {"n_boot": BOOT_N, "n_degenerate": degenerate,
            "factor_choice": {v: {k: c / n for k, c in cnt.items()} for v, cnt in choice.items()},
            "same_corner_share": sum(1 for p in picks if p == tuple(ref_pick)) / n,
            "yield_ci": {"lo": float(lo), "hi": float(hi)}}


def node_z3(up, src):
    """The recommended process mode: the highest mean space-time yield, with the evidence behind it."""
    sty = {m: v["mean"] for m, v in up["y2"]["sty"].items()}
    ranked = sorted(sty, key=lambda m: -sty[m])
    ratios = [v["ratio"] for v in up["y1"]["by_tau"].values()]
    return {"recommended_mode": ranked[0], "runner_up": ranked[1], "mean_sty": sty, "sty_margin": sty[ranked[0]] / sty[ranked[1]],
            "membrane_wins": sum(1 for p in up["x1"]["pairs"].values() if p["difference_pct"] > 0),
            "flow_transfer_ratio": _mean(ratios), "optimum_share": up["z2"]["same_corner_share"]}


def _ea_interval(k_by_temp, ea):
    xs = [1 / (float(t) + KELVIN) for t in k_by_temp]
    ys = [math.log(v) for v in k_by_temp.values()]
    n = len(xs)
    b = slope(xs, ys)
    mx, my = _mean(xs), _mean(ys)
    resid = [y - (my + b * (x - mx)) for x, y in zip(xs, ys)]
    se = math.sqrt(sum(r * r for r in resid) / (n - 2) / sum((x - mx) ** 2 for x in xs))
    half = T_975_DF1 * se * GAS_R / 1000
    return ea - half, ea + half


def node_R1(up, src):
    """Every headline number with its interval: the six kinetic parameters (profile intervals), the optimum yield (bootstrap
    interval) and the two activation energies (95 % t-interval of the Arrhenius slope over the three temperatures)."""
    rows = []
    for m in MODEL_MODES:
        for name in PARAMS:
            b = up["x7"][m][name]
            rows.append({"key": f"{m}.{name}", "value": up["x6"]["params"][m][name], "lo": b["lo"], "hi": b["hi"]})
    rows.append({"key": "optimum_yield_pct", "value": up["z1"]["yield_pct"], "lo": up["z2"]["yield_ci"]["lo"], "hi": up["z2"]["yield_ci"]["hi"]})
    for key, blk, kk in (("membrane_ea_kj_mol", up["x2"]["membrane"], "k_mean_by_temp"), ("batch_ea_kj_mol", up["x2"]["batch"], "k_by_temp")):
        lo, hi = _ea_interval(blk[kk], blk["ea_kj_mol"])
        rows.append({"key": key, "value": blk["ea_kj_mol"], "lo": lo, "hi": hi})
    return rows


def node_R3(up, src):
    """The model card: the mechanism, the parameters, what the data pin down and how the model transfers to flow."""
    ident = sum(p["identifiable"] for m in up["x7"].values() for p in m.values())
    return {"mechanism": up["x6"]["mechanism"], "parameters": up["x6"]["params"], "rmse": up["x6"]["rmse"],
            "identifiable_parameters": ident, "flow_transfer_ratio": _mean(v["ratio"] for v in up["y1"]["by_tau"].values()),
            "flow_assumed": up["y1"]["assumed"]}


def main(argv=None):
    here = Path(__file__).resolve().parent
    for p in (here, here.parent / "kit"):  # shipped next to taskgraph.py; in the repo it is under ../kit
        sys.path.insert(0, str(p))
    import taskgraph
    taskgraph.reference_cli(sys.modules[__name__], here / "graph.json", argv)


if __name__ == "__main__":
    main()
