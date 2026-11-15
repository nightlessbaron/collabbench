"""Reference for the fiscal graph ("Federal interest cost"): one pure function per node, node_<id>(up, src)
(standard library only).

    python reference.py <src_dir> <out_dir> --stage S     writes every node output of stage <= S under <out_dir>

`src` is a directory laid out like the workspace (data/..., docs/...). The window is fiscal years 2017 to 2025 (October
2016 to September 2025). The client's decisions (graph.json Q1 to Q5) are the constants below. This stage implements
level 1: the eight ingest nodes t1 to t8.
"""
import csv
import datetime as dt
import sys
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

START, END = "2016-10", "2025-09"           # the window, as months
FIRST_DAY, LAST_DAY = "2016-10-01", "2025-09-30"
MONTHS = ["October", "November", "December", "January", "February", "March", "April", "May", "June", "July", "August",
          "September"]

# Q1: the client counts by federal fiscal year, labelled by the year it ends in
# Q2: only interest on public issues counts; the Government Account Series is left out
# Q4: the inflation compensation on TIPS counts as interest cost (it goes in the TIPS row and in the total)
# Q5: a security's interest is its accrued interest + amortized discount + amortized premium (signed as published)
PUBLIC = "INTEREST EXPENSE ON PUBLIC ISSUES"
CLASS_OF = {"Treasury Bills": "bills", "Treasury Notes": "notes", "Treasury Bonds": "bonds",
            "Inflation Protected Securities (TIPS)": "tips", "Treasury Inflation Protected Securities (TIPS)": "tips",
            "Int. Expense Inflation Compensation (TIPS)": "tips", "Treasury Floating Rate Notes (FRN)": "frn"}
SECURITIES = ["bills", "notes", "bonds", "tips", "frn", "other_public", "total"]
COMP_LINE = "Int. Expense Inflation Compensation (TIPS)"
GROUP_COLUMN = {"ACCRUED INTEREST EXPENSE": "accrued", "AMORTIZED DISCOUNT": "discount",
                "AMORTIZED PREMIUM": "premium", "SAVINGS BONDS": "other_lines",
                "MISCELLANEOUS INTEREST EXPENSE": "other_lines"}


def _read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def _month_index(ym: str) -> int:
    return int(ym[:4]) * 12 + int(ym[5:7]) - 1


def _ym(index: int) -> str:
    return f"{index // 12}-{index % 12 + 1:02d}"


def window_months() -> list[str]:
    return [_ym(i) for i in range(_month_index(START), _month_index(END) + 1)]


def fiscal_year(ym: str) -> int:
    return int(ym[:4]) + (1 if int(ym[5:7]) >= 10 else 0)


def fiscal_quarter(ym: str) -> int:
    return (int(ym[5:7]) - 10) % 12 // 3 + 1


# ---- the Monthly Treasury Statement: every report lists the months of its own fiscal year and the previous one -------

def mts_listings(src: Path) -> dict[str, list[dict]]:
    """month (YYYY-MM) -> the listings of that month, one per report that lists it, in report order:
    {"report": record_date, "receipts": str, "outlays": str, "deficit": str}."""
    reports = defaultdict(list)
    for r in _read(src / "data" / "mts_table_1.csv"):
        reports[r["record_date"]].append(r)
    out = defaultdict(list)
    for date in sorted(reports):
        fy = None
        for r in sorted(reports[date], key=lambda r: int(r["src_line_nbr"])):
            name = r["classification_desc"]
            if r["record_type_cd"] == "SL" and name.startswith("FY "):
                fy = int(name[3:])
            elif r["record_type_cd"] == "MTH" and fy is not None:
                m = MONTHS.index(name)
                ym = f"{fy - 1 if m < 3 else fy}-{(m + 9) % 12 + 1:02d}"
                out[ym].append({"report": date, "receipts": r["current_month_gross_rcpt_amt"],
                                "outlays": r["current_month_gross_outly_amt"], "deficit": r["current_month_dfct_sur_amt"]})
    return out


def node_t1(up, src):
    """One row per window month: its fiscal year and quarter (Q1) and how the Monthly Treasury Statement lists it."""
    listings = mts_listings(Path(src))
    return [{"month": ym, "year": fiscal_year(ym), "quarter": fiscal_quarter(ym), "n_reports": len(listings[ym]),
             "latest_report": listings[ym][-1]["report"]} for ym in window_months()]


# ---- t2: interest expense lines ----------------------------------------------------------------------------------------

def _cents(x: Decimal) -> float:
    return float(x.quantize(Decimal("0.01")))


def node_t2(up, src):
    """Per month and security class: accrued, discount, premium, inflation compensation and the interest (Q2, Q4, Q5)."""
    cells = defaultdict(lambda: defaultdict(Decimal))
    for r in _read(Path(src) / "data" / "interest_expense.csv"):
        ym = r["record_date"][:7]
        if r["expense_catg_desc"] != PUBLIC or not START <= ym <= END:
            continue
        sec = CLASS_OF.get(r["expense_type_desc"], "other_public")
        col = "inflation_comp" if r["expense_type_desc"] == COMP_LINE else GROUP_COLUMN[r["expense_group_desc"]]
        cells[(ym, sec)][col] += Decimal(r["month_expense_amt"])
    rows = []
    for ym in window_months():
        total = defaultdict(Decimal)
        for sec in SECURITIES[:-1]:
            c = cells[(ym, sec)]
            for k, v in c.items():
                total[k] += v
            rows.append(_row(ym, sec, c))
        rows.append(_row(ym, "total", total))
    return rows


def _row(ym, sec, c):
    parts = {k: c.get(k, Decimal(0)) for k in ("accrued", "discount", "premium", "inflation_comp", "other_lines")}
    return {"month": ym, "security": sec, **{k: _cents(v) for k, v in parts.items()}, "interest": _cents(sum(parts.values()))}


# ---- t3: statement vintages ---------------------------------------------------------------------------------------------

def node_t3(up, src):
    """One row per window month: receipts, outlays and deficit as last revised (Q6), the deficit as first published."""
    listings = mts_listings(Path(src))
    rows = []
    for ym in window_months():
        first, last = listings[ym][0], listings[ym][-1]
        rows.append({"month": ym, "receipts": _cents(Decimal(last["receipts"])), "outlays": _cents(Decimal(last["outlays"])),
                     "deficit": _cents(Decimal(last["deficit"])), "source_report": last["report"],
                     "deficit_first": _cents(Decimal(first["deficit"])),
                     "revision": _cents(Decimal(last["deficit"]) - Decimal(first["deficit"]))})
    return rows


# ---- t6: the daily par yield curve ---------------------------------------------------------------------------------------

TENORS = {"1 Mo": "m1", "1.5 Month": "m1_5", "2 Mo": "m2", "3 Mo": "m3", "4 Mo": "m4", "6 Mo": "m6", "1 Yr": "y1",
          "2 Yr": "y2", "3 Yr": "y3", "5 Yr": "y5", "7 Yr": "y7", "10 Yr": "y10", "20 Yr": "y20", "30 Yr": "y30"}
CURVE_COLUMNS = ["date"] + list(TENORS.values())


def node_t6(up, src):
    """One row per trading day of the window, yields in percent per tenor; a tenor Treasury did not yet publish is empty."""
    rows = {}
    for f in sorted((Path(src) / "data" / "par_yield_curve").glob("*.csv")):
        for r in _read(f):
            m, d, y = r["Date"].split("/")
            iso = f"{y}-{m}-{d}"
            if FIRST_DAY <= iso <= LAST_DAY:
                rows[iso] = {"date": iso, **{TENORS[k]: (float(v) if v.strip() else None)
                                             for k, v in r.items() if k != "Date"}}
    return [{c: rows[d].get(c) for c in CURVE_COLUMNS} for d in sorted(rows)]


# ---- t7: CPI and the TIPS reference CPI ------------------------------------------------------------------------------------

def node_t7(up, src):
    """One row per calendar day of the window: the CPI-U (NSA) of the day's month and the TIPS reference CPI, which is the
    CPI of the third month before the day's month, moved toward that of the second month before it by the elapsed share of
    the month ((day - 1) / days in month), rounded to five decimals."""
    cpi = {r["observation_date"][:7]: float(r["CPIAUCNS"]) for r in _read(Path(src) / "data" / "cpi_u_nsa.csv")
           if r["CPIAUCNS"].strip() not in ("", ".")}
    rows = []
    day = dt.date.fromisoformat(FIRST_DAY)
    while day <= dt.date.fromisoformat(LAST_DAY):
        ym = f"{day.year}-{day.month:02d}"
        i = _month_index(ym)
        n = (dt.date(day.year + day.month // 12, day.month % 12 + 1, 1) - dt.date(day.year, day.month, 1)).days
        c3, c2 = cpi[_ym(i - 3)], cpi[_ym(i - 2)]
        rows.append({"date": day.isoformat(), "cpi": cpi[ym], "ref_cpi": round(c3 + (day.day - 1) / n * (c2 - c3), 5)})
        day += dt.timedelta(days=1)
    return rows


# ---- shared helpers for the later nodes ----------------------------------------------------------------------------------

CLASSES = ["bills", "notes", "bonds", "tips", "frn"]
AUCTION_CLASS = {"Bill": "bills", "CMB": "bills", "Note": "notes", "Bond": "bonds", "TIPS": "tips", "FRN": "frn"}
MSPD_CLASS = {"Bills": "bills", "Notes": "notes", "Bonds": "bonds", "Treasury Inflation-Protected Securities": "tips",
              "Floating Rate Notes": "frn", "Federal Financing Bank": "ffb"}


def _fy_months(year: int) -> list[str]:
    return [_ym(_month_index(f"{year - 1}-10") + k) for k in range(12)]


def _month_end(ym: str) -> str:
    y, m = int(ym[:4]), int(ym[5:7])
    return (dt.date(y + m // 12, m % 12 + 1, 1) - dt.timedelta(days=1)).isoformat()


def cpi_series(src: Path) -> dict[str, float]:
    return {r["observation_date"][:7]: float(r["CPIAUCNS"]) for r in _read(Path(src) / "data" / "cpi_u_nsa.csv")
            if r["CPIAUCNS"].strip() not in ("", ".")}


def ref_cpi(cpi: dict[str, float], day: str) -> float:
    """The TIPS reference CPI of a day: see node_t7."""
    y, m, d = int(day[:4]), int(day[5:7]), int(day[8:10])
    n = (dt.date(y + m // 12, m % 12 + 1, 1) - dt.date(y, m, 1)).days
    i = _month_index(day[:7])
    c3, c2 = cpi[_ym(i - 3)], cpi[_ym(i - 2)]
    return c3 + (d - 1) / n * (c2 - c3)


# ---- t4: the security panel (class level: the per-CUSIP MSPD was not obtainable, see graph.json) -----------------------

def node_t4(up, src):
    """Per month and marketable class: outstanding and the part held by the public, in millions of dollars."""
    cells = {}
    for r in _read(Path(src) / "data" / "mspd_table_1.csv"):
        ym = r["record_date"][:7]
        if r["security_type_desc"] == "Marketable":
            cells[(ym, MSPD_CLASS[r["security_class_desc"]])] = r
        elif r["security_type_desc"] == "Total Marketable":
            cells[(ym, "total_marketable")] = r
    rows = []
    for ym in window_months():
        for c in CLASSES + ["ffb", "total_marketable"]:
            r = cells[(ym, c)]
            rows.append({"month": ym, "class": c, "total_mil": round(float(r["total_mil_amt"]), 4),
                         "public_mil": round(float(r["debt_held_public_mil_amt"]), 4)})
    return rows


# ---- t5: the auction ledger ---------------------------------------------------------------------------------------------

def auction_rows(src: Path) -> list[dict]:
    return _read(Path(src) / "data" / "auctions.csv")


def node_t5(up, src):
    """Per CUSIP, over every auction of it in the file: the class, maturity, first issue date, the number of auctions, the
    total awarded (a reopening is a further auction of the same CUSIP, so issuance is the sum) and the auctions."""
    by = defaultdict(list)
    for r in auction_rows(src):
        by[r["cusip"]].append(r)
    out = {}
    for cusip, rs in sorted(by.items()):
        rs.sort(key=lambda r: (r["issue_date"], r["auction_date"]))
        first = rs[0]
        out[cusip] = {
            "class": AUCTION_CLASS[first["type"]], "maturity": first["maturity_date"], "first_issue": first["issue_date"],
            "n_auctions": len(rs), "issuance": sum(int(r["awarded_amt"]) for r in rs),
            "coupon": float(first["coupon"]) if first["coupon"] else None,
            "dated": first["original_dated_date"] or first["dated_date"] or None,
            "auctions": [{"issue": r["issue_date"], "awarded": int(r["awarded_amt"]),
                          "yield": float(r["high_yield"] or r["investment_rate"] or 0) or None,
                          "spread": float(r["spread"]) if r["spread"] else None} for r in rs]}
    return out


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> dt.date:
    d = dt.date(year, month, 1)
    d += dt.timedelta(days=(weekday - d.weekday()) % 7)
    if n > 0:
        return d + dt.timedelta(weeks=n - 1)
    d += dt.timedelta(weeks=4)
    return d if d.month == month else d - dt.timedelta(weeks=1)


def holidays(year: int) -> set[dt.date]:
    """Federal Reserve holidays of a year: a holiday on a Sunday is kept on the Monday, one on a Saturday is not moved."""
    fixed = [dt.date(year, 1, 1), dt.date(year, 7, 4), dt.date(year, 12, 25), dt.date(year, 11, 11)]
    if year >= 2021:
        fixed.append(dt.date(year, 6, 19))
    out = {d + dt.timedelta(days=1) if d.weekday() == 6 else d for d in fixed}
    out |= {_nth_weekday(year, 1, 0, 3), _nth_weekday(year, 2, 0, 3), _nth_weekday(year, 5, 0, -1),
            _nth_weekday(year, 9, 0, 1), _nth_weekday(year, 10, 0, 2), _nth_weekday(year, 11, 3, 4)}
    return out


def payment_day(day: str) -> str:
    """The day a security maturing on `day` is redeemed: the next business day on or after it."""
    d = dt.date.fromisoformat(day)
    while d.weekday() >= 5 or d in holidays(d.year):
        d += dt.timedelta(days=1)
    return d.isoformat()


# ---- r1: the stock rebuild ------------------------------------------------------------------------------------------------

def node_r1(up, src):
    """Par outstanding at each month-end by class: every auction's awarded amount from its issue date up to (not including)
    the day its CUSIP is redeemed (a maturity on a weekend or holiday is paid on the next business day, so the security
    is still outstanding at a month-end that falls on that day). TIPS are carried at inflation-adjusted principal: par times the reference CPI of the month-end
    over the reference CPI of the TIPS's original dated date. Buybacks are not in the data and are not deducted."""
    cpi = cpi_series(src)
    ref_end = {r["date"]: r["ref_cpi"] for r in up["t7"]}
    ledger = up["t5"]
    rows = []
    for ym in window_months():
        end = _month_end(ym)
        stock = dict.fromkeys(CLASSES, 0.0)
        for cusip, c in ledger.items():
            if not c["first_issue"] <= end < payment_day(c["maturity"]):
                continue
            par = sum(a["awarded"] for a in c["auctions"] if a["issue"] <= end)
            if c["class"] == "tips":
                par = par * ref_end[end] / ref_cpi(cpi, c["dated"])
            stock[c["class"]] += par
        rows += [{"month": ym, "class": k, "outstanding": round(stock[k], 2)} for k in CLASSES]
    return rows


# ---- a1: interest by class and fiscal year ---------------------------------------------------------------------------------

def node_a1(up, src):
    """Interest in billions of dollars per fiscal year (Q1) and security class: the sum of t2's monthly interest."""
    year = {r["month"]: r["year"] for r in up["t1"]}
    cells = defaultdict(Decimal)
    for r in up["t2"]:
        cells[(year[r["month"]], r["security"])] += Decimal(repr(r["interest"]))
    years = sorted({y for y, _ in cells})
    return [{"year": y, "class": k, "interest_bn": round(float(cells[(y, k)] / Decimal(10) ** 9), 2)}
            for y in years for k in SECURITIES[:-1] + ["total"]]


# ---- a10: the issuance mix --------------------------------------------------------------------------------------------------

def node_a10(up, src):
    """Gross issuance per fiscal year (by issue date, Q1): billions of dollars awarded by class (reopenings and SOMA add-ons
    included) and the shares of bills, coupons (notes and bonds together), TIPS and floating rate notes in percent."""
    month_year = {r["month"]: r["year"] for r in up["t1"]}
    amt = defaultdict(lambda: defaultdict(int))
    for c in up["t5"].values():
        for a in c["auctions"]:
            y = month_year.get(a["issue"][:7])
            if y is not None:
                amt[y][c["class"]] += a["awarded"]
    rows = []
    for y in sorted(amt):
        a = amt[y]
        total = sum(a.values())
        bn = lambda v: round(v / 1e9, 2)  # noqa: E731
        share = lambda v: round(100.0 * v / total, 3)  # noqa: E731
        rows.append({"year": y, "bills_bn": bn(a["bills"]), "notes_bn": bn(a["notes"]), "bonds_bn": bn(a["bonds"]),
                     "tips_bn": bn(a["tips"]), "frn_bn": bn(a["frn"]), "total_bn": bn(total),
                     "bills_pct": share(a["bills"]), "coupons_pct": share(a["notes"] + a["bonds"]),
                     "tips_pct": share(a["tips"]), "frn_pct": share(a["frn"])})
    return rows


# ---- p3: the inflation paths ------------------------------------------------------------------------------------------------

INFLATION_SPREAD = {"low": -1.5, "base": 0.0, "high": 1.5}  # percentage points around the trailing 12-month rate
PATH_MONTHS = 60                                            # October 2025 to September 2030 (fiscal years 2026 to 2030)


def node_p3(up, src):
    """Three CPI-U paths from the last CPI of the window: monthly compounding of the trailing twelve-month inflation rate
    (September 2025 over September 2024) shifted by -1.5, 0 and +1.5 points."""
    cpi = {}
    for r in up["t7"]:
        cpi[r["date"][:7]] = r["cpi"]
    base_rate = cpi[END] / cpi[_ym(_month_index(END) - 12)] - 1.0
    rows = []
    for name, shift in INFLATION_SPREAD.items():
        rate = base_rate + shift / 100.0
        for k in range(1, PATH_MONTHS + 1):
            rows.append({"path": name, "month": _ym(_month_index(END) + k), "annual_rate_pct": round(rate * 100, 4),
                         "cpi": round(cpi[END] * (1.0 + rate) ** (k / 12.0), 5)})
    return rows


# ---- stage 2 (levels 3 to 5): r2, a6, r3, a2, a4, a8 --------------------------------------------------------------------

FLAG_PCT = 0.25   # R1: a class-month whose rebuild is more than 0.25 percent from the reported stock is flagged


def node_r2(up, src):
    """Rebuilt (r1) against reported (t4) outstanding by class and month, in dollars; the residual is rebuilt minus reported,
    in dollars and in percent of the reported amount; flagged is 1 where its absolute value exceeds 0.25 percent (R1)."""
    rep = {(r["month"], r["class"]): r["total_mil"] * 1e6 for r in up["t4"]}
    rows = []
    for r in up["r1"]:
        k = (r["month"], r["class"])
        pct = (r["outstanding"] - rep[k]) / rep[k] * 100.0
        rows.append({"month": r["month"], "class": r["class"], "rebuilt": r["outstanding"], "reported": round(rep[k], 2),
                     "residual": round(r["outstanding"] - rep[k], 2), "residual_pct": round(pct, 4),
                     "flagged": 1 if abs(pct) > FLAG_PCT else 0})
    return rows


def node_r3(up, src):
    """The corrected stock: the rebuild where it reconciles (r2 not flagged), the reported stock where it does not."""
    old = {(r["month"], r["class"]): r["outstanding"] for r in up["r1"]}
    rows = []
    for r in up["r2"]:
        k = (r["month"], r["class"])
        rows.append({"month": r["month"], "class": r["class"], "stock": r["reported"] if r["flagged"] else old[k],
                     "rebuilt": old[k], "source": "reported" if r["flagged"] else "rebuilt"})
    return rows


def node_a6(up, src):
    """Interest and the deficit in constant dollars (Q3): each fiscal year's amount times the CPI-U average of fiscal 2023 over
    the average of its own fiscal year (twelve monthly values, October to September), in billions rounded to two decimals."""
    year = {r["month"]: r["year"] for r in up["t1"]}
    month_cpi = {}
    for r in up["t7"]:
        month_cpi[r["date"][:7]] = r["cpi"]
    by = defaultdict(list)
    for ym, c in month_cpi.items():
        by[year[ym]].append(c)
    avg = {y: sum(v) / len(v) for y, v in by.items()}
    interest = {r["year"]: r["interest_bn"] for r in up["a1"] if r["class"] == "total"}
    deficit = defaultdict(Decimal)
    for r in up["t3"]:
        deficit[year[r["month"]]] += Decimal(repr(r["deficit"]))
    rows = []
    for y in sorted(interest):
        d = float(deficit[y] / Decimal(10) ** 9)
        rows.append({"year": y, "cpi_avg": round(avg[y], 3), "interest_nom_bn": interest[y], "deficit_nom_bn": round(d, 2),
                     "interest_real_bn": round(interest[y] * avg[2023] / avg[y], 2),
                     "deficit_real_bn": round(d * avg[2023] / avg[y], 2)})
    return rows


def node_a2(up, src):
    """Per fiscal year and class (the five and their total): the average of the twelve month-end stocks of r3 (Q7), and the
    closing stock, in billions of dollars rounded to two decimals."""
    year = {r["month"]: r["year"] for r in up["t1"]}
    by = defaultdict(list)
    for r in up["r3"]:
        by[(year[r["month"]], r["class"])].append((r["month"], r["stock"]))
    out, tot_avg, tot_end = [], defaultdict(float), defaultdict(float)
    for (y, c), v in sorted(by.items()):
        v.sort()
        avg, end = sum(x for _, x in v) / len(v), v[-1][1]
        tot_avg[y] += avg
        tot_end[y] += end
        out.append({"year": y, "class": c, "avg_bn": round(avg / 1e9, 2), "end_bn": round(end / 1e9, 2)})
    out += [{"year": y, "class": "total", "avg_bn": round(tot_avg[y] / 1e9, 2), "end_bn": round(tot_end[y] / 1e9, 2)} for y in sorted(tot_avg)]
    return sorted(out, key=lambda r: (r["year"], r["class"] == "total", CLASSES.index(r["class"]) if r["class"] in CLASSES else 9))


def node_a4(up, src):
    """The TIPS accrual check, October 2016 excluded (no opening stock): the inflation compensation of each month that r3's
    TIPS stock at the previous month-end implies, stock x (reference CPI at the month-end over that of the previous month-end
    minus 1), against Treasury's reported inflation compensation line (t2); billions rounded to two decimals."""
    stock = {r["month"]: r["stock"] for r in up["r3"] if r["class"] == "tips"}
    ref = {r["date"]: r["ref_cpi"] for r in up["t7"]}
    comp = {r["month"]: r["inflation_comp"] for r in up["t2"] if r["security"] == "tips"}
    rows = []
    months = window_months()
    for prev, ym in zip(months, months[1:]):
        computed = stock[prev] * (ref[_month_end(ym)] / ref[_month_end(prev)] - 1.0)
        rows.append({"month": ym, "computed_bn": round(computed / 1e9, 2), "reported_bn": round(comp[ym] / 1e9, 2),
                     "gap_bn": round((comp[ym] - computed) / 1e9, 2)})
    return rows


def node_a8(up, src):
    """Principal maturing by month from October 2025 to December 2030 from the securities outstanding at 2025-09-30: each
    CUSIP's par from the ledger (TIPS at the inflation-adjusted principal of 2025-09-30), counted in the month of the day it is
    redeemed; billions rounded to two decimals. The wall is the ledger's: it is not scaled to the corrected stock, so its class
    sums exceed the corrected stock by what buybacks retired (notes 144bn, bonds 50.5bn, TIPS 11.5bn at 2025-09)."""
    cpi = cpi_series(src)
    ref_end = ref_cpi(cpi, LAST_DAY)
    cell = defaultdict(float)
    for c in up["t5"].values():
        par = sum(a["awarded"] for a in c["auctions"] if a["issue"] <= LAST_DAY)
        if par == 0 or c["maturity"] <= LAST_DAY:
            continue
        if c["class"] == "tips":
            par *= ref_end / ref_cpi(cpi, c["dated"])
        cell[(payment_day(c["maturity"])[:7], c["class"])] += par
    months = [_ym(_month_index("2025-10") + k) for k in range(63)]
    rows = []
    for ym in months:
        row = {"month": ym, **{f"{k}_bn": round(cell[(ym, k)] / 1e9, 2) for k in CLASSES}}
        row["total_bn"] = round(sum(cell[(ym, k)] for k in CLASSES) / 1e9, 2)
        rows.append(row)
    return rows


# ---- stage 3 (levels 6 to 8): a3, p1, R3, a5, a7, a9, p2, R1 ----------------------------------------------------------------

AVG_RATE_NAME = {"bills": "Treasury Bills", "notes": "Treasury Notes", "bonds": "Treasury Bonds",
                 "tips": "Treasury Inflation-Protected Securities (TIPS)", "frn": "Treasury Floating Rate Notes (FRN)",
                 "total": "Total Marketable"}
RATE_CLASSES = CLASSES + ["total"]


def _interest_marketable(up) -> dict:
    """{(year, class): billions}: a1's five classes and the total of the five (the marketable securities)."""
    cell = {(r["year"], r["class"]): r["interest_bn"] for r in up["a1"]}
    for y in {k[0] for k in cell}:
        cell[(y, "total")] = round(sum(cell[(y, c)] for c in CLASSES), 2)
    return cell


def node_a3(up, src):
    """The implied rate of each class and of the five together, in percent to three decimals: the year's interest (a1; for the
    total the five classes' interest, TIPS inflation compensation included) over the average stock of the year (a2)."""
    cell = _interest_marketable(up)
    rows = []
    for r in up["a2"]:
        rows.append({"year": r["year"], "class": r["class"], "rate_pct": round(cell[(r["year"], r["class"])] / r["avg_bn"] * 100, 3)})
    return rows


def node_a5(up, src):
    """Per class and for the total, from the second year on (Q8): the change in interest split into the rate effect, the change
    in the implied rate (interest over average stock, unrounded) times the new average stock, and the volume effect, the
    change in the average stock times the old rate; billions rounded to two decimals; delta is their sum."""
    cell = _interest_marketable(up)
    avg = {(r["year"], r["class"]): r["avg_bn"] for r in up["a2"]}
    years = sorted({k[0] for k in avg})
    rows = []
    for y in years[1:]:
        for c in RATE_CLASSES:
            r0, r1 = cell[(y - 1, c)] / avg[(y - 1, c)], cell[(y, c)] / avg[(y, c)]
            rate, vol = (r1 - r0) * avg[(y, c)], (avg[(y, c)] - avg[(y - 1, c)]) * r0
            rows.append({"year": y, "class": c, "delta_bn": round(rate + vol, 2), "rate_bn": round(rate, 2), "volume_bn": round(vol, 2)})
    return rows


def node_a7(up, src):
    """The implied rate (a3) against the rate Treasury reports at the year's last month-end (September) for the same security
    type (the total against Total Marketable), in percent; gap is implied minus reported."""
    reported = {}
    for r in _read(Path(src) / "data" / "avg_interest_rates.csv"):
        reported[(r["record_date"][:7], r["security_desc"])] = float(r["avg_interest_rate_amt"])
    rows = []
    for r in up["a3"]:
        rep = reported[(f"{r['year']}-09", AVG_RATE_NAME[r["class"]])]
        rows.append({"year": r["year"], "class": r["class"], "implied_pct": r["rate_pct"], "reported_pct": rep,
                     "gap_pct": round(r["rate_pct"] - rep, 3)})
    return rows


def node_a9(up, src):
    """New-issue rates by class and year (by issue date): the awarded-weighted average of the auction yields (investment rate for
    bills, real yield for TIPS); floating rate notes: the year's mean 3-month par yield plus the awarded-weighted spread. Next
    to the outstanding rate (a3); percent, three decimals; spread is marginal minus outstanding."""
    num, den, spr = defaultdict(float), defaultdict(float), defaultdict(float)
    for c in up["t5"].values():
        for a in c["auctions"]:
            ym = a["issue"][:7]
            if not START <= ym <= END:
                continue
            k = (fiscal_year(ym), c["class"])
            den[k] += a["awarded"]
            if c["class"] == "frn":
                spr[k] += a["awarded"] * (a["spread"] or 0.0)
            else:
                num[k] += a["awarded"] * (a["yield"] or 0.0)
    m3 = defaultdict(list)
    for r in up["t6"]:
        if r["m3"] is not None:
            m3[fiscal_year(r["date"][:7])].append(r["m3"])
    out_rate = {(r["year"], r["class"]): r["rate_pct"] for r in up["a3"]}
    rows = []
    for y in range(2017, 2026):
        for c in CLASSES:
            k = (y, c)
            marginal = (sum(m3[y]) / len(m3[y]) + spr[k] / den[k]) if c == "frn" else num[k] / den[k]
            rows.append({"year": y, "class": c, "marginal_pct": round(marginal, 3), "outstanding_pct": out_rate[k],
                         "spread_pct": round(round(marginal, 3) - out_rate[k], 3)})
    return rows


SHIFTS = [0, 50, 100]
HORIZON = [2026, 2027, 2028, 2029, 2030]


def node_p2(up, src):
    """Three curve paths (+0, +50, +100 basis points a year, added cumulatively: Q13) from the rates of fiscal 2025: for every
    path, year 2026 to 2030 and class, the new-issue rate (a9, 2025) plus the shift times the years since 2025, and the 10-year
    par yield of 2025-09-30 (t6) moved the same way; percent, three decimals."""
    base = {r["class"]: r["marginal_pct"] for r in up["a9"] if r["year"] == 2025}
    base["curve_10y"] = [r for r in up["t6"] if r["date"] == LAST_DAY][0]["y10"]
    rows = []
    for bp in SHIFTS:
        for y in HORIZON:
            for c in CLASSES + ["curve_10y"]:
                rows.append({"path": bp, "year": y, "class": c, "rate_pct": round(base[c] + bp * (y - 2025) / 100.0, 3)})
    return rows


MIX_YEAR = 2025


def node_p1(up, src):
    """The rollover engine, fiscal years 2026 to 2030, by class, from the corrected stock of 2025-09 (r3): the maturities of a8
    by fiscal year; bills roll into bills, and the principal of the other classes that matures is reissued across notes, bonds,
    TIPS and floaters in the proportions of fiscal 2025's issuance (a10 amounts; the bill share is left out, P2). New issuance
    other than bills is assumed to mature after 2030. Billions rounded to two decimals."""
    mix = [r for r in up["a10"] if r["year"] == MIX_YEAR][0]
    nonbill = sum(mix[f"{c}_bn"] for c in CLASSES if c != "bills")
    share = {c: mix[f"{c}_bn"] / nonbill for c in CLASSES if c != "bills"}
    mature = defaultdict(float)
    for r in up["a8"]:
        y = fiscal_year(r["month"])
        for c in CLASSES:
            mature[(y, c)] += r[f"{c}_bn"]
    stock = {r["class"]: r["stock"] / 1e9 for r in up["r3"] if r["month"] == END}
    rows = []
    for y in HORIZON:
        due = sum(mature[(y, c)] for c in CLASSES if c != "bills")
        new = {c: due * share[c] if c != "bills" else mature[(y, c)] for c in CLASSES}
        for c in CLASSES:
            stock[c] = stock[c] - mature[(y, c)] + new[c]
            rows.append({"year": y, "class": c, "maturing_bn": round(mature[(y, c)], 2), "reissued_bn": round(new[c], 2),
                         "stock_bn": round(stock[c], 2)})
    return rows


def node_R3(up, src):
    """The reconciliation memo: per class how many months are flagged, the largest absolute residual in percent and its month,
    the correction at 2025-09 (corrected minus rebuilt stock, billions); and the TIPS accrual totals of a4 in billions."""
    classes = {}
    for c in CLASSES:
        rs = [r for r in up["r2"] if r["class"] == c]
        worst = max(rs, key=lambda r: abs(r["residual_pct"]))
        last = [r for r in up["r3"] if r["class"] == c and r["month"] == END][0]
        classes[c] = {"n_flagged": sum(r["flagged"] for r in rs), "max_abs_pct": round(abs(worst["residual_pct"]), 4),
                      "worst_month": worst["month"], "correction_bn": round((last["stock"] - last["rebuilt"]) / 1e9, 2)}
    a4 = up["a4"]
    worst = max(a4, key=lambda r: abs(r["gap_bn"]))
    return {"classes": classes,
            "tips_accrual": {"computed_bn": round(sum(r["computed_bn"] for r in a4), 2), "reported_bn": round(sum(r["reported_bn"] for r in a4), 2),
                             "gap_bn": round(sum(r["gap_bn"] for r in a4), 2), "max_abs_gap_bn": abs(worst["gap_bn"])}}


def node_R1(up, src):
    """The history table, one row per year 2017 to 2025: total interest (a1), the implied and reported rates of the marketable
    total (a3, a7), the rate and volume effects (a5, empty in 2017), and interest and the deficit in constant dollars (a6)."""
    tot = {r["year"]: r for r in up["a1"] if r["class"] == "total"}
    rate = {r["year"]: r for r in up["a7"] if r["class"] == "total"}
    eff = {r["year"]: r for r in up["a5"] if r["class"] == "total"}
    real = {r["year"]: r for r in up["a6"]}
    return [{"year": y, "interest_bn": tot[y]["interest_bn"], "implied_pct": rate[y]["implied_pct"], "reported_pct": rate[y]["reported_pct"],
             "gap_pct": rate[y]["gap_pct"], "rate_effect_bn": eff[y]["rate_bn"] if y in eff else None,
             "volume_effect_bn": eff[y]["volume_bn"] if y in eff else None, "real_interest_bn": real[y]["interest_real_bn"],
             "real_deficit_bn": real[y]["deficit_real_bn"]} for y in sorted(tot)]


# ---- stage 4 (levels 9 to 11): p4, R4, p5, p6, R2 ----------------------------------------------------------------------------

INFL_PATHS = ["low", "base", "high"]
PRIMARY_YEARS = [2023, 2024, 2025]      # Q9: the primary deficit is the mean of these years', held every year


def node_p4(up, src):
    """The nine scenario runs (rate path x inflation path), fiscal years 2026 to 2030: interest on the marketable debt in
    billions of dollars (TIPS inflation compensation included) and the marketable debt at the year's end, rule P4:
    S = p1 stock + earlier borrowing of the class; bills and floaters pay the year's path rate; notes, bonds and TIPS blend their
    average rate E with the path rate on the fresh amount (p1's reissue plus the previous year's borrowing): E = ((S - fresh)
    E_prev + fresh rate) / S, starting from Treasury's reported September-2025 rate (a7; TIPS the reported coupon rate);
    inflation compensation is S(TIPS) x the path's inflation x the accrual calibration of a4 (reported over computed, fiscal
    2025); borrowing is the primary deficit (Q9) plus the year's interest, split over notes, bonds, TIPS and floaters like p1's
    reissue of 2026."""
    p1 = {(r["year"], r["class"]): r for r in up["p1"]}
    path = {(r["path"], r["year"], r["class"]): r["rate_pct"] for r in up["p2"]}
    infl = {(r["path"]): r["annual_rate_pct"] for r in up["p3"] if r["month"] == "2025-10"}
    a4 = [r for r in up["a4"] if "2024-10" <= r["month"] <= END]
    calib = sum(r["reported_bn"] for r in a4) / sum(r["computed_bn"] for r in a4)
    a6 = {r["year"]: r for r in up["a6"]}
    primary = sum(a6[y]["deficit_nom_bn"] - a6[y]["interest_nom_bn"] for y in PRIMARY_YEARS) / len(PRIMARY_YEARS)
    start = {r["class"]: r["reported_pct"] for r in up["a7"] if r["year"] == 2025}
    nonbill = [c for c in CLASSES if c != "bills"]
    tot_new = sum(p1[(2026, c)]["reissued_bn"] for c in nonbill)
    share = {c: p1[(2026, c)]["reissued_bn"] / tot_new for c in nonbill}
    rows = []
    for bp in SHIFTS:
        for name in INFL_PATHS:
            E = {c: start[c] for c in CLASSES}
            extra = dict.fromkeys(CLASSES, 0.0)      # cumulative borrowing by class
            fresh_b = dict.fromkeys(CLASSES, 0.0)    # last year's borrowing, priced this year
            for y in HORIZON:
                S, interest = {}, 0.0
                for c in CLASSES:
                    S[c] = p1[(y, c)]["stock_bn"] + extra[c]
                    rate = path[(bp, y, c)]
                    if c in ("bills", "frn"):
                        E[c] = rate
                    else:
                        fresh = p1[(y, c)]["reissued_bn"] + fresh_b[c]
                        E[c] = ((S[c] - fresh) * E[c] + fresh * rate) / S[c]
                    interest += E[c] * S[c] / 100.0
                comp = S["tips"] * infl[name] / 100.0 * calib
                interest += comp
                borrow = primary + interest
                new = {c: borrow * share[c] if c != "bills" else 0.0 for c in CLASSES}
                for c in CLASSES:
                    extra[c] += new[c]
                fresh_b = new
                rows.append({"rate_path": bp, "infl_path": name, "year": y, "interest_bn": round(interest, 2),
                             "debt_bn": round(sum(S.values()) + borrow, 2), "tips_comp_bn": round(comp, 2)})
    return rows


def node_p5(up, src):
    """The cost of a basis point by horizon: for each inflation path and year, the extra interest of the +100 path over the +0
    path divided by the cumulative shift of the year (100 basis points x years since 2025), billions per basis point, four
    decimals."""
    cell = {(r["rate_path"], r["infl_path"], r["year"]): r["interest_bn"] for r in up["p4"]}
    return [{"infl_path": n, "year": y, "bn_per_bp": round((cell[(100, n, y)] - cell[(0, n, y)]) / (100.0 * (y - 2025)), 4)}
            for n in INFL_PATHS for y in HORIZON]


def node_p6(up, src):
    """The break-even shift: receipts of fiscal 2025 (t3) grown at the mean annual growth of fiscal 2023 to 2025; the target
    interest of a year is the ratio of interest to receipts of fiscal 2026 on the +0, base-inflation path times that year's
    receipts; breakeven_bp is the cumulative shift of the year, between the +0 and +100 base-inflation paths, that reaches it."""
    year_of = {}
    rec = defaultdict(Decimal)
    for r in up["t3"]:
        rec[fiscal_year(r["month"])] += Decimal(repr(r["receipts"]))
    receipts = {y: float(v) / 1e9 for y, v in rec.items()}
    g = (receipts[2025] / receipts[2023]) ** 0.5 - 1.0
    cell = {(r["rate_path"], r["infl_path"], r["year"]): r["interest_bn"] for r in up["p4"]}
    ratio = cell[(0, "base", 2026)] / (receipts[2025] * (1 + g))
    rows = []
    for y in HORIZON:
        rcpt = receipts[2025] * (1 + g) ** (y - 2025)
        target = ratio * rcpt
        i0, i100 = cell[(0, "base", y)], cell[(100, "base", y)]
        rows.append({"year": y, "receipts_bn": round(rcpt, 2), "target_bn": round(target, 2),
                     "breakeven_bp": round(100.0 * (y - 2025) * (target - i0) / (i100 - i0), 1)})
    return rows


def node_R4(up, src):
    """The assumptions register: for each decision the value the work applied, read from the tables that apply it, and the node
    it appears in."""
    t1 = {r["month"]: r for r in up["t1"]}
    year = "fiscal" if t1["2016-10"]["year"] == 2017 else "calendar"
    vintage = "first_published" if all(r["deficit"] == r["deficit_first"] for r in up["t3"]) else "last_revised"
    a2 = [r for r in up["a2"] if r["class"] == "total"]
    den = "closing" if all(r["avg_bn"] == r["end_bn"] for r in a2) else "average"
    p2 = {(r["path"], r["year"], r["class"]): r["rate_pct"] for r in up["p2"]}
    step = round(p2[(100, 2027, "bills")] - p2[(100, 2026, "bills")], 3)
    bp = "cumulative" if step == 1.0 else "one_time" if step == 0.0 else "other"
    tot = {r["year"]: r for r in up["a5"] if r["class"] == "total"}
    avg = {r["year"]: r["avg_bn"] for r in a2}

    def r_old(y):  # the old rate a volume effect implies when the cross term sits in the rate effect
        return tot[y]["volume_bn"] / (avg[y] - avg[y - 1])
    err_rate = err_vol = 0.0
    for y in range(2019, 2025):
        err_rate += abs(tot[y]["delta_bn"] - (r_old(y + 1) * avg[y] - r_old(y) * avg[y - 1]))
        err_vol += abs(tot[y]["delta_bn"] - (r_old(y) * avg[y] - r_old(y - 1) * avg[y - 1]))
    cross = "rate_effect" if err_rate < err_vol else "volume_effect"
    return {"Q1": {"value": year, "node": "t1"}, "Q6": {"value": vintage, "node": "t3"}, "Q7": {"value": den, "node": "a2"},
            "Q8": {"value": cross, "node": "a5"}, "Q13": {"value": bp, "node": "p2"}}


def node_R2(up, src):
    """The scenario table: every p4 run with the cost per basis point (p5) of its inflation path and year, and the break-even
    shift (p6) of the year."""
    bpc = {(r["infl_path"], r["year"]): r["bn_per_bp"] for r in up["p5"]}
    be = {r["year"]: r["breakeven_bp"] for r in up["p6"]}
    return [{"rate_path": r["rate_path"], "infl_path": r["infl_path"], "year": r["year"], "interest_bn": r["interest_bn"],
             "debt_bn": r["debt_bn"], "bn_per_bp": bpc[(r["infl_path"], r["year"])], "breakeven_bp": be[r["year"]]} for r in up["p4"]]


def main(argv=None):
    here = Path(__file__).resolve().parent
    for p in (here, here.parent / "kit"):  # shipped next to taskgraph.py; in the repo it is under ../kit
        sys.path.insert(0, str(p))
    import taskgraph
    taskgraph.reference_cli(sys.modules[__name__], here / "graph.json", argv)


if __name__ == "__main__":
    main()
