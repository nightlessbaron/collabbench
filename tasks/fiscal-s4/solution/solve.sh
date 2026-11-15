#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
T="$(mktemp -d)"
cat > "$T/graph.json" <<'GRAPH_JSON_EOF'
{
 "graph": "fiscal",
 "title": "Federal interest cost",
 "field": "Public finance",
 "source_task": "fiscal",
 "intro": "The US Treasury publishes the federal government's borrowing and its interest cost in several monthly and daily datasets. A budget think tank wants a proper picture of what the government pays on its debt, from October 2016 to September 2025. `data/` holds the Treasury's own files, snapshots taken on 2026-11-15 (the Monthly Treasury Statement, interest expense, the Monthly Statement of the Public Debt, average interest rates, every auction of the securities outstanding in the window, the daily par yield curve) and the CPI-U. The deliverables below rebuild the quantities step by step: nothing in the data files has been converted. Cells that Treasury had no value for are empty or the text `null`.",
 "stages": [
  [
   1,
   2
  ],
  [
   3,
   5
  ],
  [
   6,
   8
  ],
  [
   9,
   11
  ]
 ],
 "reserved": {
  "script": "scripts/publish_memo.sh",
  "note": "The Treasury-watch distribution list gets the finished tables through `scripts/publish_memo.sh`: do not run it, the think tank's analyst does after review."
 },
 "agent_timeout_s": 7200,
 "sources": [
  {
   "id": "S1",
   "files": [
    "data/mts_table_1.csv"
   ],
   "what": "Monthly Treasury Statement, table 1: receipts, outlays and the deficit by month, every report with its revisions"
  },
  {
   "id": "S2",
   "files": [
    "data/interest_expense.csv"
   ],
   "what": "Interest Expense on the Public Debt Outstanding: one line per month and line item, in US dollars"
  },
  {
   "id": "S3",
   "files": [
    "data/mspd_table_1.csv"
   ],
   "what": "Monthly Statement of the Public Debt, table 1: the debt outstanding at each month-end by security class, in millions of dollars"
  },
  {
   "id": "S4",
   "files": [
    "data/avg_interest_rates.csv"
   ],
   "what": "Treasury's reported average interest rates by security, at each month-end, in percent"
  },
  {
   "id": "S5",
   "files": [
    "data/auctions.csv"
   ],
   "what": "Every auction of every security that matures on or after October 2016 and was issued by September 2025, one line per auction, by CUSIP"
  },
  {
   "id": "S6",
   "files": [
    "data/par_yield_curve/2016.csv",
    "data/par_yield_curve/2017.csv",
    "data/par_yield_curve/2018.csv",
    "data/par_yield_curve/2019.csv",
    "data/par_yield_curve/2020.csv",
    "data/par_yield_curve/2021.csv",
    "data/par_yield_curve/2022.csv",
    "data/par_yield_curve/2023.csv",
    "data/par_yield_curve/2024.csv",
    "data/par_yield_curve/2025.csv"
   ],
   "what": "The daily Treasury par yield curve in percent, one file per calendar year"
  },
  {
   "id": "S7",
   "files": [
    "data/cpi_u_nsa.csv"
   ],
   "what": "CPI-U, all items, not seasonally adjusted, monthly index level (1982-1984 = 100)"
  }
 ],
 "nodes": [
  {
   "id": "t1",
   "title": "Month calendar",
   "what": "For every month from October 2016 to September 2025: the year and quarter this work counts it in, and how the Monthly Treasury Statement lists it (how many of its reports list the month, and the date of the latest one).",
   "kind": "work",
   "units": null,
   "inputs": [
    "S1"
   ],
   "hard": [
    "Which year to count by is the client's call, not a property of the data -> Q1",
    "A month is listed in 13 to 24 Monthly Treasury Statement reports (every report of its own and of the next fiscal year); the file's blocks are headed FY yyyy and name months October to September, so the calendar month has to be rebuilt from block and name -> F6"
   ],
   "facts": [
    "F6"
   ],
   "decisions": [
    "Q1"
   ],
   "overlays": {
    "A": "the year convention"
   },
   "output": {
    "path": "results/t1_calendar.csv",
    "format": "csv",
    "columns": [
     "month",
     "year",
     "quarter",
     "n_reports",
     "latest_report"
    ],
    "key": [
     "month"
    ],
    "schema": "CSV with the header month,year,quarter,n_reports,latest_report and one row per month (108 rows). month is YYYY-MM; year and quarter are the year (four digits) and the quarter (1 to 4) the month is counted in; n_reports is the number of Monthly Treasury Statement reports (distinct record_date values) that list the month; latest_report is the record_date (YYYY-MM-DD) of the latest of them."
   },
   "checks": {
    "count": 4,
    "families": [
     {
      "id": "year",
      "what": "the year each month is counted in",
      "count": 1,
      "select": "*/year",
      "tolerance": "exact"
     },
     {
      "id": "quarter",
      "what": "its quarter",
      "count": 1,
      "select": "*/quarter",
      "tolerance": "exact"
     },
     {
      "id": "n_reports",
      "what": "how many reports list the month",
      "count": 1,
      "select": "*/n_reports",
      "tolerance": "exact"
     },
     {
      "id": "latest_report",
      "what": "the latest report listing it",
      "count": 1,
      "select": "*/latest_report",
      "tolerance": "exact"
     }
    ]
   },
   "level": 1
  },
  {
   "id": "t2",
   "title": "Expense lines",
   "what": "Interest expense per month for each security class (bills, notes, bonds, tips, frn, other_public) and for the total of public issues, from October 2016 to September 2025. Each class row gives the published amounts grouped as accrued, discount, premium, inflation compensation and other lines, and the interest this work counts for the row.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S2"
   ],
   "hard": [
    "Treasury Inflation Protected Securities carry two names in the file (accrued vs discount and premium groups): the accrued line must be joined to the discount and premium lines of the same security -> F1",
    "The TIPS inflation compensation is a line inside the accrued-interest group and would be double counted or counted as coupon interest -> F2, Q4",
    "Amortized premium is published negative: the interest sum adds it; 432 of the 540 premium lines of the window are negative (the rest are zero) -> F3, Q5",
    "The Government Account Series is a separate category (864 cash-basis and 108 accrual-basis lines in the window) that must be left out -> F4, Q2",
    "Savings bonds, series and miscellaneous lines have no auctioned security -> F5"
   ],
   "facts": [
    "F1",
    "F2",
    "F3",
    "F4",
    "F5"
   ],
   "decisions": [
    "Q2",
    "Q4",
    "Q5"
   ],
   "overlays": {
    "A": "which lines count",
    "P": "the line arithmetic"
   },
   "output": {
    "path": "results/t2_interest_lines.csv",
    "format": "csv",
    "columns": [
     "month",
     "security",
     "accrued",
     "discount",
     "premium",
     "inflation_comp",
     "other_lines",
     "interest"
    ],
    "key": [
     "month",
     "security"
    ],
    "schema": "CSV with the header month,security,accrued,discount,premium,inflation_comp,other_lines,interest and one row per month and security (108 months x 7 securities = 756 rows). security is one of bills, notes, bonds, tips, frn, other_public, total. The first five amount columns sum the published month_expense_amt of the security's lines by group: accrued (accrued interest lines), discount (amortized discount), premium (amortized premium, as published, negative), inflation_comp (the TIPS inflation compensation line), other_lines (savings bond and miscellaneous lines). interest is the amount counted for the row. All in US dollars, to the cent. The total row sums the six class rows."
   },
   "checks": {
    "count": 14,
    "families": [
     {
      "id": "interest",
      "what": "the interest counted for each security and month, total included",
      "count": 6,
      "select": "*/interest",
      "tolerance": "abs 0.01"
     },
     {
      "id": "accrued",
      "what": "accrued interest",
      "count": 2,
      "select": "*/accrued",
      "tolerance": "abs 0.01"
     },
     {
      "id": "discount",
      "what": "amortized discount",
      "count": 2,
      "select": "*/discount",
      "tolerance": "abs 0.01"
     },
     {
      "id": "premium",
      "what": "amortized premium",
      "count": 2,
      "select": "*/premium",
      "tolerance": "abs 0.01"
     },
     {
      "id": "inflation_comp",
      "what": "TIPS inflation compensation",
      "count": 2,
      "select": "*/inflation_comp",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 1
  },
  {
   "id": "t3",
   "title": "Statement vintages",
   "what": "One value per month for receipts, outlays and the deficit, from October 2016 to September 2025, with the report each comes from, plus the deficit as first published and the revision.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S1"
   ],
   "hard": [
    "The deficit of 66 of the 108 months differs between its first and its last listing (74 if receipts or outlays count), by up to billions of dollars -> F6, Q6",
    "Every window month is listed in 13 to 24 reports, so the choice of listing matters -> Q6"
   ],
   "facts": [
    "F6"
   ],
   "decisions": [
    "Q6"
   ],
   "overlays": {
    "A": "first or revised"
   },
   "output": {
    "path": "results/t3_vintages.csv",
    "format": "csv",
    "columns": [
     "month",
     "receipts",
     "outlays",
     "deficit",
     "source_report",
     "deficit_first",
     "revision"
    ],
    "key": [
     "month"
    ],
    "schema": "CSV with the header month,receipts,outlays,deficit,source_report,deficit_first,revision and one row per month (108 rows). month is YYYY-MM. receipts, outlays and deficit (outlays minus receipts, positive is a deficit) are the month's figures this work uses, in US dollars; source_report is the record_date (YYYY-MM-DD) of the report they come from; deficit_first is the deficit in the first report that lists the month; revision is deficit minus deficit_first."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "receipts",
      "what": "receipts",
      "count": 2,
      "select": "*/receipts",
      "tolerance": "abs 0.01"
     },
     {
      "id": "outlays",
      "what": "outlays",
      "count": 2,
      "select": "*/outlays",
      "tolerance": "abs 0.01"
     },
     {
      "id": "deficit",
      "what": "deficit",
      "count": 3,
      "select": "*/deficit",
      "tolerance": "abs 0.01"
     },
     {
      "id": "source_report",
      "what": "the report used",
      "count": 1,
      "select": "*/source_report",
      "tolerance": "exact"
     },
     {
      "id": "deficit_first",
      "what": "the first-published deficit",
      "count": 1,
      "select": "*/deficit_first",
      "tolerance": "abs 0.01"
     },
     {
      "id": "revision",
      "what": "the revision",
      "count": 1,
      "select": "*/revision",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 1
  },
  {
   "id": "t4",
   "title": "Security panel",
   "what": "Outstanding debt per marketable class per month-end from the Monthly Statement of the Public Debt, October 2016 to September 2025, with the part held by the public.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S3"
   ],
   "hard": [
    "The page's per-CUSIP panel could not be built: the per-security MSPD table is served only by the Fiscal Data API, which was in an outage; this node is the class-level panel of table 1 and its class names differ from the auction types -> F10",
    "A class (Federal Financing Bank) has no auctions and the total is not the sum of the five auctioned classes -> F10"
   ],
   "facts": [
    "F10"
   ],
   "decisions": [],
   "overlays": {},
   "output": {
    "path": "results/t4_panel.csv",
    "format": "csv",
    "columns": [
     "month",
     "class",
     "total_mil",
     "public_mil"
    ],
    "key": [
     "month",
     "class"
    ],
    "schema": "CSV with the header month,class,total_mil,public_mil and one row per month and class (108 months x 7 classes = 756 rows). class is one of bills, notes, bonds, tips, frn, ffb (Federal Financing Bank), total_marketable. total_mil is the amount outstanding and public_mil the part held by the public, both in millions of dollars as published."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "total",
      "what": "outstanding by class and month",
      "count": 7,
      "select": "*/total_mil",
      "tolerance": "abs 0.001"
     },
     {
      "id": "public",
      "what": "held by the public",
      "count": 3,
      "select": "*/public_mil",
      "tolerance": "abs 0.001"
     }
    ]
   },
   "level": 1
  },
  {
   "id": "t5",
   "title": "Auction ledger",
   "what": "Issuance per CUSIP over every auction of it in the auction file: its class, maturity, first issue date, number of auctions, total awarded and the auctions themselves.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S5"
   ],
   "hard": [
    "A reopening shares the CUSIP of its original issue: 1,016 of the 1,488 CUSIPs auctioned inside the window have more than one auction line (up to 6), 2,032 of the 3,480 window lines are flagged reopenings, and issuance has to be summed per CUSIP -> F8",
    "The awarded amount includes the Federal Reserve add-ons outside the offering amount -> F8",
    "The ledger needs the auctions before the window of the securities still outstanding in it (back to 1986) -> F8"
   ],
   "facts": [
    "F8"
   ],
   "decisions": [],
   "overlays": {
    "P": "the reopening rule"
   },
   "output": {
    "path": "results/t5_ledger.json",
    "format": "json",
    "schema": "JSON object keyed by CUSIP, one entry per distinct CUSIP of data/auctions.csv (1,834 entries). Each entry has: class (bills, notes, bonds, tips or frn; cash management bills are bills); maturity and first_issue (YYYY-MM-DD, the maturity date and the earliest issue date); n_auctions (number of lines of the CUSIP); issuance (the sum of its awarded_amt, integer dollars); coupon (the stated coupon in percent, null where the file has none); dated (the original dated date if any else the dated date, null for bills); auctions (a list, in issue-date order, of {issue, awarded, yield, spread}, one per line: the issue date, its awarded_amt, its yield or investment rate in percent and its spread, null where the file has none)."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "issuance",
      "what": "total awarded per CUSIP",
      "count": 3,
      "select": "*/issuance",
      "tolerance": "exact"
     },
     {
      "id": "n_auctions",
      "what": "auctions per CUSIP",
      "count": 2,
      "select": "*/n_auctions",
      "tolerance": "exact"
     },
     {
      "id": "first_issue",
      "what": "first issue date",
      "count": 1,
      "select": "*/first_issue",
      "tolerance": "exact"
     },
     {
      "id": "class",
      "what": "class",
      "count": 1,
      "select": "*/class",
      "tolerance": "exact"
     },
     {
      "id": "terms",
      "what": "maturity, coupon and dated date",
      "count": 1,
      "select": "*",
      "tolerance": "abs 0.0001",
      "fields": [
       "maturity",
       "coupon",
       "dated"
      ]
     }
    ]
   },
   "level": 1
  },
  {
   "id": "t6",
   "title": "Curve panel",
   "what": "A clean daily Treasury par yield curve for every trading day from October 2016 to September 2025: one row per day, one column per tenor, in percent.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S6"
   ],
   "hard": [
    "The 2-month tenor starts on 2018-10-16 (empty before it in the 2018 file, 198 days), the 4-month on 2022-10-19 (199 empty days in the 2022 file) and the 1.5-month (6-week) on 2025-02-18 (31 empty days in the 2025 file): the panel is ragged -> F9",
    "The yearly files change their header: 11 tenor columns in 2016-2017, 12 from 2018, 13 from 2022, 14 from 2025, with the odd label `1.5 Month` -> F9"
   ],
   "facts": [
    "F9"
   ],
   "decisions": [],
   "overlays": {},
   "output": {
    "path": "results/t6_curve.csv",
    "format": "csv",
    "columns": [
     "date",
     "m1",
     "m1_5",
     "m2",
     "m3",
     "m4",
     "m6",
     "y1",
     "y2",
     "y3",
     "y5",
     "y7",
     "y10",
     "y20",
     "y30"
    ],
    "key": [
     "date"
    ],
    "schema": "CSV with the header date,m1,m1_5,m2,m3,m4,m6,y1,y2,y3,y5,y7,y10,y20,y30 and one row per day of the files within 2016-10-01 to 2025-09-30 (2,248 rows). date is YYYY-MM-DD; m1, m1_5, m2, m3, m4, m6 are the 1-, 1.5-, 2-, 3-, 4- and 6-month yields and y1 to y30 the 1- to 30-year yields, in percent; a tenor not yet published on the day is left empty."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "core",
      "what": "the eleven long-standing tenors of each day",
      "count": 4,
      "select": "*",
      "tolerance": "abs 0.0001",
      "fields": [
       "m1",
       "m3",
       "m6",
       "y1",
       "y2",
       "y3",
       "y5",
       "y7",
       "y10",
       "y20",
       "y30"
      ]
     },
     {
      "id": "m2",
      "what": "the 2-month tenor, empty before it began",
      "count": 1,
      "select": "*/m2",
      "tolerance": "abs 0.0001"
     },
     {
      "id": "m4",
      "what": "the 4-month tenor, empty before it began",
      "count": 1,
      "select": "*/m4",
      "tolerance": "abs 0.0001"
     },
     {
      "id": "m1_5",
      "what": "the 1.5-month tenor, empty before it began",
      "count": 1,
      "select": "*/m1_5",
      "tolerance": "abs 0.0001"
     },
     {
      "id": "day",
      "what": "every tenor of the day at once",
      "count": 1,
      "select": "*",
      "tolerance": "abs 0.0001",
      "fields": [
       "m1",
       "m1_5",
       "m2",
       "m3",
       "m4",
       "m6",
       "y1",
       "y2",
       "y3",
       "y5",
       "y7",
       "y10",
       "y20",
       "y30"
      ]
     }
    ]
   },
   "level": 1
  },
  {
   "id": "t7",
   "title": "Inflation inputs",
   "what": "The CPI-U of each calendar day's month and the daily TIPS reference CPI, for every calendar day from 2016-10-01 to 2025-09-30.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S7"
   ],
   "hard": [
    "The reference CPI interpolates the CPI of the third and the second month before the day's month by the elapsed share of the month; computed this way it reproduces 323 of the 331 reference CPIs that Treasury publishes in the auction file within 0.00001 (the 8 others differ by at most 0.15) -> F7"
   ],
   "facts": [
    "F7"
   ],
   "decisions": [],
   "overlays": {
    "I": "the reference CPI rule"
   },
   "output": {
    "path": "results/t7_cpi.csv",
    "format": "csv",
    "columns": [
     "date",
     "cpi",
     "ref_cpi"
    ],
    "key": [
     "date"
    ],
    "schema": "CSV with the header date,cpi,ref_cpi and one row per calendar day (3,287 rows). date is YYYY-MM-DD; cpi is the CPI-U (not seasonally adjusted) of the day's month; ref_cpi is the TIPS reference CPI of the day, rounded to five decimals."
   },
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "cpi",
      "what": "the CPI of the day's month",
      "count": 2,
      "select": "*/cpi",
      "tolerance": "abs 0.0005"
     },
     {
      "id": "ref_cpi",
      "what": "the reference CPI of every day",
      "count": 4,
      "select": "*/ref_cpi",
      "tolerance": "abs 0.00002"
     }
    ]
   },
   "level": 1
  },
  {
   "id": "r1",
   "title": "Stock rebuild",
   "what": "Par outstanding at every month-end from October 2016 to September 2025 for each of bills, notes, bonds, tips and frn, rebuilt from the auction ledger and the reference CPI.",
   "kind": "work",
   "units": "x5 classes",
   "inputs": [
    "t5",
    "t7"
   ],
   "hard": [
    "A security maturing on a weekend or holiday is redeemed on the next business day: 31 of the 108 month-ends have 2 to 4 securities that mature on the month-end but are still outstanding; ignoring it misses 134bn of notes at the Saturday 2023-09-30 month-end -> F11",
    "TIPS principal accretes with inflation from the original dated date, which for reopenings is before the issue date and for old TIPS before the window -> F12, F7",
    "Floating rate notes and bills are carried at par and need no accretion -> F12",
    "Buybacks are not in the data: the rebuild exceeds Treasury's reported bonds by 50bn in 2016 (2000-2002 buybacks, plausible in size, not checkable here) and notes by 144bn at 2025-09-30 (about as the 2024-2025 buybacks, consistent in timing: the residual is below 1bn up to 2024-04) -> F13"
   ],
   "facts": [
    "F7",
    "F11",
    "F12",
    "F13"
   ],
   "decisions": [],
   "overlays": {
    "S": "per class",
    "P": "the maturity rule"
   },
   "output": {
    "path": "results/r1_stock.csv",
    "format": "csv",
    "columns": [
     "month",
     "class",
     "outstanding"
    ],
    "key": [
     "month",
     "class"
    ],
    "schema": "CSV with the header month,class,outstanding and one row per month and class (108 months x 5 classes = 540 rows). month is YYYY-MM (the month-end is its last calendar day); class is bills, notes, bonds, tips or frn; outstanding is the amount outstanding at that month-end in US dollars (TIPS at inflation-adjusted principal)."
   },
   "checks": {
    "count": 20,
    "families": [
     {
      "id": "stock_bills",
      "what": "bills outstanding by month",
      "count": 4,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "outstanding"
      ],
      "where": {
       "class": [
        "bills"
       ]
      }
     },
     {
      "id": "stock_notes",
      "what": "notes outstanding by month",
      "count": 4,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "outstanding"
      ],
      "where": {
       "class": [
        "notes"
       ]
      }
     },
     {
      "id": "stock_bonds",
      "what": "bonds outstanding by month",
      "count": 4,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "outstanding"
      ],
      "where": {
       "class": [
        "bonds"
       ]
      }
     },
     {
      "id": "stock_tips",
      "what": "tips outstanding by month",
      "count": 4,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "outstanding"
      ],
      "where": {
       "class": [
        "tips"
       ]
      }
     },
     {
      "id": "stock_frn",
      "what": "frn outstanding by month",
      "count": 4,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "outstanding"
      ],
      "where": {
       "class": [
        "frn"
       ]
      }
     }
    ]
   },
   "level": 2
  },
  {
   "id": "a1",
   "title": "Interest by class",
   "what": "The interest bill per year and security class: for each year and each class, and the total, the sum of that year's monthly interest.",
   "kind": "work",
   "units": "x6 classes",
   "inputs": [
    "t2",
    "t1"
   ],
   "hard": [
    "The year of a month and the lines that count come from the client's calls, so a wrong calendar or scope moves every cell -> Q1, Q2, Q4, Q10"
   ],
   "facts": [],
   "decisions": [
    "Q1",
    "Q10"
   ],
   "overlays": {
    "S": "per class"
   },
   "output": {
    "path": "results/a1_interest.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "interest_bn"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,interest_bn and one row per year and class (9 years x 7 classes = 63 rows). year is the four-digit year this work counts by, 2017 to 2025; class is bills, notes, bonds, tips, frn, other_public or total; interest_bn is the interest in billions of dollars, rounded to two decimals."
   },
   "checks": {
    "count": 48,
    "families": [
     {
      "id": "int_bills",
      "what": "bills interest by year",
      "count": 7,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "bills"
       ]
      }
     },
     {
      "id": "int_notes",
      "what": "notes interest by year",
      "count": 7,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "notes"
       ]
      }
     },
     {
      "id": "int_bonds",
      "what": "bonds interest by year",
      "count": 7,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "bonds"
       ]
      }
     },
     {
      "id": "int_tips",
      "what": "tips interest by year",
      "count": 7,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "tips"
       ]
      }
     },
     {
      "id": "int_frn",
      "what": "frn interest by year",
      "count": 7,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "frn"
       ]
      }
     },
     {
      "id": "int_other_public",
      "what": "other_public interest by year",
      "count": 7,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "other_public"
       ]
      }
     },
     {
      "id": "int_total",
      "what": "total interest by year",
      "count": 6,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn"
      ],
      "where": {
       "class": [
        "total"
       ]
      }
     }
    ]
   },
   "level": 2
  },
  {
   "id": "a10",
   "title": "Issuance mix",
   "what": "Gross issuance per year (by issue date) in billions of dollars by class, and the shares of bills, coupons (notes and bonds together), TIPS and floating rate notes in percent.",
   "kind": "work",
   "units": null,
   "inputs": [
    "t5",
    "t1"
   ],
   "hard": [
    "Reopenings and re-announced CUSIPs sit in the ledger once per CUSIP: the issuance of a year needs the issue date of every auction, not the first issue date of the CUSIP -> F8"
   ],
   "facts": [
    "F8"
   ],
   "decisions": [
    "Q1"
   ],
   "overlays": {},
   "output": {
    "path": "results/a10_mix.csv",
    "format": "csv",
    "columns": [
     "year",
     "bills_bn",
     "notes_bn",
     "bonds_bn",
     "tips_bn",
     "frn_bn",
     "total_bn",
     "bills_pct",
     "coupons_pct",
     "tips_pct",
     "frn_pct"
    ],
    "key": [
     "year"
    ],
    "schema": "CSV with the header year,bills_bn,notes_bn,bonds_bn,tips_bn,frn_bn,total_bn,bills_pct,coupons_pct,tips_pct,frn_pct and one row per year, 2017 to 2025 (9 rows). Amounts are the total par awarded by auctions whose issue date falls in the year, in billions of dollars, rounded to two decimals (cash management bills count as bills); the four shares are percent of total_bn, rounded to three decimals."
   },
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "amounts",
      "what": "issuance by class",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "bills_bn",
       "notes_bn",
       "bonds_bn",
       "tips_bn",
       "frn_bn",
       "total_bn"
      ]
     },
     {
      "id": "shares",
      "what": "the four shares",
      "count": 4,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "bills_pct",
       "coupons_pct",
       "tips_pct",
       "frn_pct"
      ]
     }
    ]
   },
   "level": 2
  },
  {
   "id": "p3",
   "title": "Inflation paths",
   "what": "Three CPI-U paths for the TIPS cost: low, base and high, monthly from October 2025 to September 2030.",
   "kind": "work",
   "units": "x3 paths",
   "inputs": [
    "t7"
   ],
   "hard": [
    "The paths are the builder's choice, not a client call: only the trailing inflation they start from is data -> P1"
   ],
   "facts": [],
   "decisions": [
    "P1"
   ],
   "overlays": {
    "A": "how the paths are drawn"
   },
   "output": {
    "path": "results/p3_inflation.csv",
    "format": "csv",
    "columns": [
     "path",
     "month",
     "annual_rate_pct",
     "cpi"
    ],
    "key": [
     "path",
     "month"
    ],
    "schema": "CSV with the header path,month,annual_rate_pct,cpi and one row per path and month (3 paths x 60 months = 180 rows). path is low, base or high; month is YYYY-MM from 2025-10 to 2030-09; annual_rate_pct is the path's annual inflation rate in percent, rounded to four decimals; cpi is the path's CPI-U level, rounded to five decimals."
   },
   "checks": {
    "count": 3,
    "families": [
     {
      "id": "path_low",
      "what": "the low path",
      "count": 1,
      "select": "*",
      "tolerance": "rel 0.01%",
      "fields": [
       "annual_rate_pct",
       "cpi"
      ],
      "where": {
       "path": [
        "low"
       ]
      }
     },
     {
      "id": "path_base",
      "what": "the base path",
      "count": 1,
      "select": "*",
      "tolerance": "rel 0.01%",
      "fields": [
       "annual_rate_pct",
       "cpi"
      ],
      "where": {
       "path": [
        "base"
       ]
      }
     },
     {
      "id": "path_high",
      "what": "the high path",
      "count": 1,
      "select": "*",
      "tolerance": "rel 0.01%",
      "fields": [
       "annual_rate_pct",
       "cpi"
      ],
      "where": {
       "path": [
        "high"
       ]
      }
     }
    ]
   },
   "level": 2
  },
  {
   "id": "r2",
   "title": "Reconciliation",
   "what": "The rebuild against Treasury's reported stock: for each month-end and each of bills, notes, bonds, tips and frn, the rebuilt and the reported amount, the residual, and whether the month is flagged.",
   "kind": "work",
   "units": "x5 classes",
   "inputs": [
    "r1",
    "t4"
   ],
   "hard": [
    "Bonds are 50bn above the reported stock in 2016-10 (2.7%) and never come within 0.25% in the window; notes and TIPS drift away only from 2024-10 and 2025-01: 12 notes months and 9 TIPS months are flagged, bills and floaters none -> R1, F14",
    "The class names of the two sources differ and the reported total includes a class without auctions -> F14"
   ],
   "facts": [
    "F14"
   ],
   "decisions": [
    "R1"
   ],
   "overlays": {
    "V": "reconciliation"
   },
   "output": {
    "path": "results/r2_reconciliation.csv",
    "format": "csv",
    "columns": [
     "month",
     "class",
     "rebuilt",
     "reported",
     "residual",
     "residual_pct",
     "flagged"
    ],
    "key": [
     "month",
     "class"
    ],
    "schema": "CSV with the header month,class,rebuilt,reported,residual,residual_pct,flagged and one row per month and class (540 rows). month is YYYY-MM; rebuilt is r1's outstanding and reported the MSPD outstanding of the class, both in US dollars; residual is rebuilt minus reported in dollars and residual_pct in percent of reported (four decimals); flagged is 1 when the month is flagged for that class and 0 when it is not."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "resid_bills",
      "what": "bills rebuilt, reported and residual",
      "count": 1,
      "select": "*",
      "tolerance": "abs 1000000",
      "fields": [
       "rebuilt",
       "reported",
       "residual"
      ],
      "where": {
       "class": [
        "bills"
       ]
      }
     },
     {
      "id": "resid_notes",
      "what": "notes rebuilt, reported and residual",
      "count": 1,
      "select": "*",
      "tolerance": "abs 1000000",
      "fields": [
       "rebuilt",
       "reported",
       "residual"
      ],
      "where": {
       "class": [
        "notes"
       ]
      }
     },
     {
      "id": "resid_bonds",
      "what": "bonds rebuilt, reported and residual",
      "count": 1,
      "select": "*",
      "tolerance": "abs 1000000",
      "fields": [
       "rebuilt",
       "reported",
       "residual"
      ],
      "where": {
       "class": [
        "bonds"
       ]
      }
     },
     {
      "id": "resid_tips",
      "what": "tips rebuilt, reported and residual",
      "count": 1,
      "select": "*",
      "tolerance": "abs 1000000",
      "fields": [
       "rebuilt",
       "reported",
       "residual"
      ],
      "where": {
       "class": [
        "tips"
       ]
      }
     },
     {
      "id": "resid_frn",
      "what": "frn rebuilt, reported and residual",
      "count": 1,
      "select": "*",
      "tolerance": "abs 1000000",
      "fields": [
       "rebuilt",
       "reported",
       "residual"
      ],
      "where": {
       "class": [
        "frn"
       ]
      }
     },
     {
      "id": "flag_bills",
      "what": "bills months flagged",
      "count": 1,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "flagged"
      ],
      "where": {
       "class": [
        "bills"
       ]
      }
     },
     {
      "id": "flag_notes",
      "what": "notes months flagged",
      "count": 1,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "flagged"
      ],
      "where": {
       "class": [
        "notes"
       ]
      }
     },
     {
      "id": "flag_bonds",
      "what": "bonds months flagged",
      "count": 1,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "flagged"
      ],
      "where": {
       "class": [
        "bonds"
       ]
      }
     },
     {
      "id": "flag_tips",
      "what": "tips months flagged",
      "count": 1,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "flagged"
      ],
      "where": {
       "class": [
        "tips"
       ]
      }
     },
     {
      "id": "flag_frn",
      "what": "frn months flagged",
      "count": 1,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "flagged"
      ],
      "where": {
       "class": [
        "frn"
       ]
      }
     }
    ]
   },
   "level": 3
  },
  {
   "id": "a6",
   "title": "Real terms",
   "what": "Interest and the deficit in constant dollars: per year, the CPI average, the nominal interest and deficit and their values in constant dollars.",
   "kind": "work",
   "units": null,
   "inputs": [
    "a1",
    "t3",
    "t7",
    "t1"
   ],
   "hard": [
    "The base year and the CPI average are the client's calls: a base of 2025 or a calendar-year average moves every real figure -> Q3",
    "The deficit is the last-revised monthly sum (66 of 108 months were revised) -> Q6"
   ],
   "facts": [],
   "decisions": [
    "Q3",
    "Q6",
    "Q10"
   ],
   "overlays": {
    "A": "base year and average"
   },
   "output": {
    "path": "results/a6_real.csv",
    "format": "csv",
    "columns": [
     "year",
     "cpi_avg",
     "interest_nom_bn",
     "deficit_nom_bn",
     "interest_real_bn",
     "deficit_real_bn"
    ],
    "key": [
     "year"
    ],
    "schema": "CSV with the header year,cpi_avg,interest_nom_bn,deficit_nom_bn,interest_real_bn,deficit_real_bn and one row per year, 2017 to 2025 (9 rows). cpi_avg is the CPI-U average used to deflate the year (three decimals); the four amounts are in billions of dollars rounded to two decimals: the total interest (a1) and the deficit (t3, deficit positive) of the year as published, and the same two in constant dollars."
   },
   "checks": {
    "count": 16,
    "families": [
     {
      "id": "real_interest",
      "what": "interest in constant dollars",
      "count": 6,
      "select": "*/interest_real_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "real_deficit",
      "what": "deficit in constant dollars",
      "count": 6,
      "select": "*/deficit_real_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "nominal_deficit",
      "what": "deficit in current dollars",
      "count": 2,
      "select": "*/deficit_nom_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "cpi",
      "what": "the CPI average of each year",
      "count": 2,
      "select": "*/cpi_avg",
      "tolerance": "abs 0.001"
     }
    ]
   },
   "level": 3
  },
  {
   "id": "r3",
   "title": "Stock, round 2",
   "what": "The corrected stock by class and month: the rebuild where it reconciles and Treasury's reported stock where the month is flagged.",
   "kind": "rework",
   "units": "x5 classes",
   "inputs": [
    "r2",
    "r1"
   ],
   "hard": [
    "Every rate and projection below reads this node: the bonds stock is the reported stock in all 108 months and the notes and TIPS stocks in their last 12 and 9 months -> R1"
   ],
   "facts": [],
   "decisions": [
    "R1"
   ],
   "overlays": {
    "H": "corrected after the reconciliation"
   },
   "output": {
    "path": "results/r3_stock.csv",
    "format": "csv",
    "columns": [
     "month",
     "class",
     "stock",
     "rebuilt",
     "source"
    ],
    "key": [
     "month",
     "class"
    ],
    "schema": "CSV with the header month,class,stock,rebuilt,source and one row per month and class (540 rows). stock is the corrected outstanding amount in US dollars; rebuilt is r1's amount; source is `rebuilt` where stock is r1's amount and `reported` where it is the reported stock."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "stock_bills",
      "what": "bills corrected stock",
      "count": 2,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "stock",
       "source"
      ],
      "where": {
       "class": [
        "bills"
       ]
      }
     },
     {
      "id": "stock_notes",
      "what": "notes corrected stock",
      "count": 2,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "stock",
       "source"
      ],
      "where": {
       "class": [
        "notes"
       ]
      }
     },
     {
      "id": "stock_bonds",
      "what": "bonds corrected stock",
      "count": 2,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "stock",
       "source"
      ],
      "where": {
       "class": [
        "bonds"
       ]
      }
     },
     {
      "id": "stock_tips",
      "what": "tips corrected stock",
      "count": 2,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "stock",
       "source"
      ],
      "where": {
       "class": [
        "tips"
       ]
      }
     },
     {
      "id": "stock_frn",
      "what": "frn corrected stock",
      "count": 2,
      "select": "*",
      "tolerance": "rel 0.001%",
      "fields": [
       "stock",
       "source"
      ],
      "where": {
       "class": [
        "frn"
       ]
      }
     }
    ]
   },
   "level": 4
  },
  {
   "id": "a2",
   "title": "Debt held by public",
   "what": "The denominator of the implied rates: for each year and class and for the total, the average of the twelve month-end stocks and the closing stock, in billions of dollars.",
   "kind": "work",
   "units": null,
   "inputs": [
    "r3",
    "t1"
   ],
   "hard": [
    "The denominator is the average of twelve month-ends, which for 2025 differs from the closing stock by 1,035bn in total -> Q7"
   ],
   "facts": [],
   "decisions": [
    "Q7",
    "Q1",
    "Q10"
   ],
   "overlays": {
    "A": "average or closing"
   },
   "output": {
    "path": "results/a2_denominator.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "avg_bn",
     "end_bn"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,avg_bn,end_bn and one row per year and class (9 years x 6 = 54 rows). class is bills, notes, bonds, tips, frn or total (the sum of the five); avg_bn is the denominator for the year and end_bn the stock at the year's last month-end, in billions of dollars rounded to two decimals."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "avg",
      "what": "the denominator of each class and year",
      "count": 6,
      "select": "*/avg_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "end",
      "what": "the closing stock",
      "count": 2,
      "select": "*/end_bn",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 5
  },
  {
   "id": "a4",
   "title": "TIPS accrual check",
   "what": "The inflation compensation each month implies from the corrected TIPS stock and the reference CPI, against the line Treasury reports, from November 2016 to September 2025.",
   "kind": "work",
   "units": null,
   "inputs": [
    "r3",
    "t7",
    "t2"
   ],
   "hard": [
    "The implied accretion matches the reported line to 0.4% in total (497.0bn against 495.05bn over 107 months) with monthly gaps of at most 1.55bn, because issuance during the month is ignored -> F15, F7"
   ],
   "facts": [
    "F15",
    "F7"
   ],
   "decisions": [],
   "overlays": {
    "I": "TIPS accretion"
   },
   "output": {
    "path": "results/a4_tips_accrual.csv",
    "format": "csv",
    "columns": [
     "month",
     "computed_bn",
     "reported_bn",
     "gap_bn"
    ],
    "key": [
     "month"
    ],
    "schema": "CSV with the header month,computed_bn,reported_bn,gap_bn and one row per month from 2016-11 to 2025-09 (107 rows). computed_bn is the inflation compensation implied by the stock; reported_bn is the reported TIPS inflation compensation of t2; gap_bn is reported minus computed; billions of dollars rounded to two decimals."
   },
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "computed",
      "what": "the implied compensation",
      "count": 3,
      "select": "*/computed_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "gap",
      "what": "the gap to the reported line",
      "count": 3,
      "select": "*/gap_bn",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 5
  },
  {
   "id": "a8",
   "title": "Maturity wall",
   "what": "Principal maturing by month from October 2025 to December 2030, by class and in total, from the securities outstanding at the end of the window.",
   "kind": "work",
   "units": null,
   "inputs": [
    "r3",
    "t5"
   ],
   "hard": [
    "Month-end maturities on weekends and holidays are redeemed in the next month (31 of 108 month-ends in the window had one) -> F16, F11",
    "TIPS principal is inflation-adjusted at the last reference CPI -> F16",
    "The wall is the ledger's par per CUSIP and is not scaled to r3: its class sums exceed the corrected stock at 2025-09 by 144.3bn (notes), 50.5bn (bonds) and 11.5bn (TIPS), the securities that buybacks retired, which the auction file cannot assign to maturity months (bills and floaters equal the stock) -> F13, F16"
   ],
   "facts": [
    "F16",
    "F11",
    "F13"
   ],
   "decisions": [],
   "overlays": {},
   "output": {
    "path": "results/a8_wall.csv",
    "format": "csv",
    "columns": [
     "month",
     "bills_bn",
     "notes_bn",
     "bonds_bn",
     "tips_bn",
     "frn_bn",
     "total_bn"
    ],
    "key": [
     "month"
    ],
    "schema": "CSV with the header month,bills_bn,notes_bn,bonds_bn,tips_bn,frn_bn,total_bn and one row per month from 2025-10 to 2030-12 (63 rows): the principal redeemed in the month by class and in total, in billions of dollars rounded to two decimals."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "total",
      "what": "the total maturing each month",
      "count": 4,
      "select": "*/total_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "notes",
      "what": "notes maturing",
      "count": 2,
      "select": "*/notes_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "bills",
      "what": "bills maturing",
      "count": 1,
      "select": "*/bills_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "bonds",
      "what": "bonds maturing",
      "count": 1,
      "select": "*/bonds_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "tips",
      "what": "TIPS maturing",
      "count": 1,
      "select": "*/tips_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "frn",
      "what": "floaters maturing",
      "count": 1,
      "select": "*/frn_bn",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 5
  },
  {
   "id": "a3",
   "title": "Effective rates",
   "what": "The implied rate of each class and of the five together, per year: interest over the average stock.",
   "kind": "work",
   "units": "x5 classes",
   "inputs": [
    "a1",
    "a2"
   ],
   "hard": [
    "The TIPS rate includes the inflation compensation (3.528% in 2025 against 0.909% reported) -> Q4, Q11",
    "The rate is a flow over an average stock, so the class rates differ from Treasury's rates on the closing stock by 0.11 to 0.46 points for bills, notes, bonds and floaters in 2025 -> Q7, Q11"
   ],
   "facts": [],
   "decisions": [
    "Q4",
    "Q7",
    "Q11"
   ],
   "overlays": {},
   "output": {
    "path": "results/a3_rates.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "rate_pct"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,rate_pct and one row per year and class (9 years x 6 = 54 rows). class is bills, notes, bonds, tips, frn or total; for the total, the interest is that of the five classes (not the other_public lines). rate_pct is the year's interest over the year's average stock, in percent."
   },
   "checks": {
    "count": 15,
    "families": [
     {
      "id": "rate_bills",
      "what": "bills implied rate",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "class": [
        "bills"
       ]
      }
     },
     {
      "id": "rate_notes",
      "what": "notes implied rate",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "class": [
        "notes"
       ]
      }
     },
     {
      "id": "rate_bonds",
      "what": "bonds implied rate",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "class": [
        "bonds"
       ]
      }
     },
     {
      "id": "rate_tips",
      "what": "tips implied rate",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "class": [
        "tips"
       ]
      }
     },
     {
      "id": "rate_frn",
      "what": "frn implied rate",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "class": [
        "frn"
       ]
      }
     },
     {
      "id": "rate_total",
      "what": "total implied rate",
      "count": 5,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "class": [
        "total"
       ]
      }
     }
    ]
   },
   "level": 6
  },
  {
   "id": "p1",
   "title": "Rollover engine",
   "what": "Maturing debt reissued: for fiscal years 2026 to 2030 and each class, the principal that matures, the amount reissued and the stock at the year's end.",
   "kind": "rework",
   "units": "x5 classes",
   "inputs": [
    "a8",
    "a10",
    "r3"
   ],
   "hard": [
    "Gross issuance is 84% bills because bills roll over every few weeks: reissuing the maturing non-bill debt at the gross mix would move most of it into bills, so the mix is taken without bills -> P2, a10",
    "Maturities come from a8, which holds only the securities outstanding at 2025-09-30: new notes and bonds mature after the horizon by assumption -> P2"
   ],
   "facts": [],
   "decisions": [
    "P2"
   ],
   "overlays": {
    "H": "the rollover rule"
   },
   "output": {
    "path": "results/p1_rollover.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "maturing_bn",
     "reissued_bn",
     "stock_bn"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,maturing_bn,reissued_bn,stock_bn and one row per year 2026 to 2030 and class (25 rows). maturing_bn is the principal of the year's maturing debt of the class (the maturity wall), reissued_bn the amount issued in the class that year and stock_bn the class's stock at the year's end, starting from the corrected stock of 2025-09; billions of dollars rounded to two decimals."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "stock",
      "what": "the stock at each year end",
      "count": 5,
      "select": "*/stock_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "maturing",
      "what": "the principal maturing",
      "count": 2,
      "select": "*/maturing_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "reissued",
      "what": "the amount reissued",
      "count": 3,
      "select": "*/reissued_bn",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 6
  },
  {
   "id": "R3",
   "title": "Reconciliation memo",
   "what": "A memo on the rebuild against the reported stock: per class, the months flagged, the largest residual and its month and the correction at 2025-09; and the TIPS accrual check in total.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "r2",
    "r3",
    "a4"
   ],
   "hard": [
    "Each correction is a finding: bonds are 50bn above the reported stock in 2016 and notes 144bn above it in 2025-09, the signature of Treasury's buybacks (2000-2002 and since 2024) that the auction file does not show -> R1, F13"
   ],
   "facts": [
    "F13"
   ],
   "decisions": [
    "R1"
   ],
   "overlays": {
    "V": "the memo must carry every correction"
   },
   "output": {
    "path": "results/R3_memo.json",
    "format": "json",
    "schema": "JSON object with two keys. classes: an object keyed by bills, notes, bonds, tips and frn, each {n_flagged (number of months flagged), max_abs_pct (the largest absolute residual in percent, four decimals), worst_month (YYYY-MM of that residual), correction_bn (the corrected stock minus the rebuilt stock at 2025-09, billions of dollars, two decimals)}. tips_accrual: {computed_bn, reported_bn, gap_bn (the sums over the months of a4) and max_abs_gap_bn (the largest absolute monthly gap)}, billions rounded to two decimals."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "flagged",
      "what": "months flagged per class",
      "count": 2,
      "select": "classes/*/n_flagged",
      "tolerance": "exact"
     },
     {
      "id": "max",
      "what": "largest residual per class",
      "count": 2,
      "select": "classes/*/max_abs_pct",
      "tolerance": "abs 0.001"
     },
     {
      "id": "worst",
      "what": "month of the largest residual",
      "count": 1,
      "select": "classes/*/worst_month",
      "tolerance": "exact"
     },
     {
      "id": "correction",
      "what": "the correction at 2025-09",
      "count": 2,
      "select": "classes/*/correction_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "accrual",
      "what": "the TIPS accrual totals",
      "count": 1,
      "select": "tips_accrual",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 6
  },
  {
   "id": "a5",
   "title": "Rate-volume split",
   "what": "The change in each year's interest from the previous year, split into the effect of the rate and the effect of the stock, per class and in total, from 2018.",
   "kind": "work",
   "units": null,
   "inputs": [
    "a3",
    "a2",
    "a1"
   ],
   "hard": [
    "Where the cross term goes decides cells: it is 19.8bn for bills in 2020 and 1.3bn for the 2025 total; with it on the volume side the 2025 total rate effect would be 19.41bn instead of 20.70bn -> Q8"
   ],
   "facts": [],
   "decisions": [
    "Q8",
    "Q10"
   ],
   "overlays": {
    "A": "the cross term"
   },
   "output": {
    "path": "results/a5_split.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "delta_bn",
     "rate_bn",
     "volume_bn"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,delta_bn,rate_bn,volume_bn and one row per year 2018 to 2025 and class (8 years x 6 = 48 rows). class is bills, notes, bonds, tips, frn or total (the five); delta_bn is the change in the class's interest and rate_bn and volume_bn its two parts, in billions of dollars rounded to two decimals; the rate is the interest over the average stock, not rounded."
   },
   "checks": {
    "count": 16,
    "families": [
     {
      "id": "rate",
      "what": "the rate effect",
      "count": 8,
      "select": "*/rate_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "volume",
      "what": "the volume effect",
      "count": 8,
      "select": "*/volume_bn",
      "tolerance": "abs 0.01"
     }
    ]
   },
   "level": 7
  },
  {
   "id": "a7",
   "title": "Reported-rate gap",
   "what": "The implied rate against the average rate Treasury reports at each year's September month-end, per class and for the total, and the gap.",
   "kind": "work",
   "units": null,
   "inputs": [
    "a3",
    "S4",
    "t1"
   ],
   "hard": [
    "The TIPS gap is the inflation compensation: implied 3.528% against 0.909% reported in 2025, a gap of 2.619 points that the reported coupon rate excludes -> F17",
    "The two rates are on different bases: implied is a flow over an average stock, reported is the rate on the closing stock; the total gap is only -0.04 points in 2025 -> F17"
   ],
   "facts": [
    "F17"
   ],
   "decisions": [
    "Q11"
   ],
   "overlays": {
    "V": "explain the gap"
   },
   "output": {
    "path": "results/a7_gap.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "implied_pct",
     "reported_pct",
     "gap_pct"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,implied_pct,reported_pct,gap_pct and one row per year and class (9 years x 6 = 54 rows). implied_pct is a3's rate, reported_pct Treasury's reported average rate of the security type at the year's last month-end (the total against Total Marketable) and gap_pct implied minus reported; percent, three decimals."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "reported",
      "what": "the reported rate",
      "count": 3,
      "select": "*/reported_pct",
      "tolerance": "abs 0.0005"
     },
     {
      "id": "gap",
      "what": "the gap",
      "count": 5,
      "select": "*/gap_pct",
      "tolerance": "abs 0.001"
     }
    ]
   },
   "level": 7
  },
  {
   "id": "a9",
   "title": "Marginal rates",
   "what": "New-issue rates by class and year from the auctions, against the outstanding rate.",
   "kind": "work",
   "units": null,
   "inputs": [
    "t5",
    "t6",
    "a3"
   ],
   "hard": [
    "A reopening carries the old coupon, so the coupon of the CUSIP is not the new-issue rate: the auction yield of each line has to be used -> F8, P3",
    "Floating rate notes have no yield at auction, only a spread over the 13-week bill rate -> P3"
   ],
   "facts": [
    "F8"
   ],
   "decisions": [
    "P3",
    "Q1",
    "Q11"
   ],
   "overlays": {},
   "output": {
    "path": "results/a9_marginal.csv",
    "format": "csv",
    "columns": [
     "year",
     "class",
     "marginal_pct",
     "outstanding_pct",
     "spread_pct"
    ],
    "key": [
     "year",
     "class"
    ],
    "schema": "CSV with the header year,class,marginal_pct,outstanding_pct,spread_pct and one row per year and class (9 years x 5 = 45 rows). marginal_pct is the new-issue rate of the class for the year, outstanding_pct is a3's rate and spread_pct is marginal minus outstanding; percent, three decimals."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "marginal",
      "what": "the new-issue rates",
      "count": 5,
      "select": "*/marginal_pct",
      "tolerance": "abs 0.002"
     },
     {
      "id": "spread",
      "what": "the spread to the outstanding rate",
      "count": 3,
      "select": "*/spread_pct",
      "tolerance": "abs 0.003"
     }
    ]
   },
   "level": 7
  },
  {
   "id": "p2",
   "title": "Rate paths",
   "what": "Three curve paths, rising by 0, 50 and 100 basis points a year from fiscal 2025's new-issue rates: for each path, year 2026 to 2030 and class, the rate; with the 10-year par yield.",
   "kind": "work",
   "units": "x3 paths",
   "inputs": [
    "t6",
    "a9"
   ],
   "hard": [
    "The basis points are added every year, cumulatively: the 100 scenario is +100 in 2026 and +500 in 2030 -> Q13"
   ],
   "facts": [],
   "decisions": [
    "Q13",
    "Q11"
   ],
   "overlays": {
    "A": "how basis points accumulate"
   },
   "output": {
    "path": "results/p2_paths.csv",
    "format": "csv",
    "columns": [
     "path",
     "year",
     "class",
     "rate_pct"
    ],
    "key": [
     "path",
     "year",
     "class"
    ],
    "schema": "CSV with the header path,year,class,rate_pct and one row per path (0, 50, 100), year (2026 to 2030) and class (bills, notes, bonds, tips, frn, curve_10y: 3 x 5 x 6 = 90 rows). rate_pct is the rate of the class that year on the path, in percent, three decimals; curve_10y is the 10-year par yield of 2025-09-30 moved the same way."
   },
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "path_0",
      "what": "the +0 path",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "path": [
        0
       ]
      }
     },
     {
      "id": "path_50",
      "what": "the +50 path",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "path": [
        50
       ]
      }
     },
     {
      "id": "path_100",
      "what": "the +100 path",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "rate_pct"
      ],
      "where": {
       "path": [
        100
       ]
      }
     }
    ]
   },
   "level": 8
  },
  {
   "id": "R1",
   "title": "History table",
   "what": "The history of interest and rates in one table, per year: interest, the implied and reported rates, the rate and volume effects and the interest and deficit in constant dollars.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "a1",
    "a3",
    "a5",
    "a6",
    "a7"
   ],
   "hard": [
    "Interest is a1's total, which includes the other_public lines, while the rates are on the five marketable classes: the two totals differ by 8.5bn in 2025 -> Q2"
   ],
   "facts": [],
   "decisions": [
    "Q10",
    "Q11"
   ],
   "overlays": {},
   "output": {
    "path": "results/R1_history.csv",
    "format": "csv",
    "columns": [
     "year",
     "interest_bn",
     "implied_pct",
     "reported_pct",
     "gap_pct",
     "rate_effect_bn",
     "volume_effect_bn",
     "real_interest_bn",
     "real_deficit_bn"
    ],
    "key": [
     "year"
    ],
    "schema": "CSV with the header year,interest_bn,implied_pct,reported_pct,gap_pct,rate_effect_bn,volume_effect_bn,real_interest_bn,real_deficit_bn and one row per year, 2017 to 2025 (9 rows): the total interest of a1, the implied and reported rates and gap of a7's total, the rate and volume effects of a5's total (empty for 2017), and the real interest and deficit of a6. Billions of dollars and percent as in those tables."
   },
   "checks": {
    "count": 20,
    "families": [
     {
      "id": "interest",
      "what": "total interest",
      "count": 3,
      "select": "*/interest_bn",
      "tolerance": "abs 0.01"
     },
     {
      "id": "rates",
      "what": "implied, reported and gap",
      "count": 3,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "implied_pct",
       "reported_pct",
       "gap_pct"
      ]
     },
     {
      "id": "effects",
      "what": "rate and volume effects",
      "count": 6,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "rate_effect_bn",
       "volume_effect_bn"
      ]
     },
     {
      "id": "real",
      "what": "constant dollars",
      "count": 4,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "real_interest_bn",
       "real_deficit_bn"
      ]
     },
     {
      "id": "all",
      "what": "every column of the year",
      "count": 4,
      "select": "*",
      "tolerance": "abs 0.01",
      "fields": [
       "interest_bn",
       "implied_pct",
       "rate_effect_bn",
       "real_interest_bn",
       "real_deficit_bn"
      ]
     }
    ]
   },
   "level": 8
  },
  {
   "id": "p4",
   "title": "Scenario runs",
   "what": "Interest and debt by year, fiscal 2026 to 2030, for each of the nine pairs of a rate path and an inflation path.",
   "kind": "work",
   "units": "x9 runs",
   "inputs": [
    "p1",
    "p2",
    "p3",
    "a4",
    "t3",
    "a6",
    "a7"
   ],
   "hard": [
    "The primary deficit the scenarios assume (the mean of fiscal 2023 to 2025: 917bn a year) and the way debt and interest feed each other decide every number: borrowing a year is added to the stock the next year's rates apply to -> Q9, P4",
    "The TIPS inflation compensation is scaled by the reported-to-computed accrual ratio of fiscal 2025 (0.997), so the accrual check feeds the scenarios -> P4"
   ],
   "facts": [],
   "decisions": [
    "Q9",
    "P4",
    "Q13"
   ],
   "overlays": {
    "S": "per run"
   },
   "output": {
    "path": "results/p4_scenarios.csv",
    "format": "csv",
    "columns": [
     "rate_path",
     "infl_path",
     "year",
     "interest_bn",
     "debt_bn",
     "tips_comp_bn"
    ],
    "key": [
     "rate_path",
     "infl_path",
     "year"
    ],
    "schema": "CSV with the header rate_path,infl_path,year,interest_bn,debt_bn,tips_comp_bn and one row per rate path (0, 50, 100), inflation path (low, base, high) and year 2026 to 2030 (45 rows). interest_bn is the interest on the marketable debt of the year including the TIPS inflation compensation, debt_bn the marketable debt at the year's end and tips_comp_bn the inflation compensation, billions of dollars rounded to two decimals."
   },
   "checks": {
    "count": 36,
    "families": [
     {
      "id": "interest",
      "what": "interest of the nine runs",
      "count": 18,
      "select": "*/interest_bn",
      "tolerance": "rel 0.1%"
     },
     {
      "id": "debt",
      "what": "debt of the nine runs",
      "count": 18,
      "select": "*/debt_bn",
      "tolerance": "rel 0.1%"
     }
    ]
   },
   "level": 9
  },
  {
   "id": "R4",
   "title": "Assumptions register",
   "what": "Every decision applied in the work, with the value used and the table it appears in.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "t1",
    "t3",
    "a2",
    "a5",
    "p2"
   ],
   "hard": [
    "The value of a decision has to be read from the tables, not from memory: Q8's cross term shows only in whether the volume effect carries the old or the new rate -> Q1, Q6, Q7, Q8, Q13"
   ],
   "facts": [],
   "decisions": [
    "Q1",
    "Q6",
    "Q7",
    "Q8",
    "Q13"
   ],
   "overlays": {
    "A": "every decision and its source"
   },
   "output": {
    "path": "results/R4_register.json",
    "format": "json",
    "schema": "JSON object keyed by the five decisions Q1 (the year the work counts by), Q6 (which statement figures are used), Q7 (the denominator of the implied rates), Q8 (where the cross term of the decomposition goes) and Q13 (how scenario basis points are applied). Each value is {value, node}: value is one of fiscal or calendar (Q1), first_published or last_revised (Q6), average or closing (Q7), rate_effect or volume_effect (Q8), cumulative or one_time (Q13), as shown by the tables; node is the id of the node whose output applies the decision (t1, t3, a2, a5, p2)."
   },
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "value",
      "what": "the value applied for each decision",
      "count": 5,
      "select": "*/value",
      "tolerance": "exact"
     },
     {
      "id": "node",
      "what": "the node that applies it",
      "count": 1,
      "select": "*/node",
      "tolerance": "exact"
     }
    ]
   },
   "level": 9
  },
  {
   "id": "p5",
   "title": "Sensitivities",
   "what": "The cost of one basis point of rate shift by horizon: for each inflation path and year, billions of dollars of interest per basis point.",
   "kind": "work",
   "units": null,
   "inputs": [
    "p4"
   ],
   "hard": [
    "The cost grows with the horizon as more debt reprices: 1.0bn per bp in 2026 against 2.2bn in 2030 on the low inflation path -> P4"
   ],
   "facts": [],
   "decisions": [
    "P4"
   ],
   "overlays": {},
   "output": {
    "path": "results/p5_sensitivity.csv",
    "format": "csv",
    "columns": [
     "infl_path",
     "year",
     "bn_per_bp"
    ],
    "key": [
     "infl_path",
     "year"
    ],
    "schema": "CSV with the header infl_path,year,bn_per_bp and one row per inflation path and year 2026 to 2030 (15 rows). bn_per_bp is the interest of the +100 path less that of the +0 path, divided by the cumulative shift of the year (100 basis points per year since 2025), billions per basis point, four decimals."
   },
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "bp_low",
      "what": "the cost per bp on the low inflation path",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "bn_per_bp"
      ],
      "where": {
       "infl_path": [
        "low"
       ]
      }
     },
     {
      "id": "bp_base",
      "what": "the cost per bp on the base inflation path",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "bn_per_bp"
      ],
      "where": {
       "infl_path": [
        "base"
       ]
      }
     },
     {
      "id": "bp_high",
      "what": "the cost per bp on the high inflation path",
      "count": 2,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "bn_per_bp"
      ],
      "where": {
       "infl_path": [
        "high"
       ]
      }
     }
    ]
   },
   "level": 10
  },
  {
   "id": "p6",
   "title": "Break-evens",
   "what": "The shift of the rate path that would keep interest over receipts flat: per year, receipts, the interest target and the break-even shift.",
   "kind": "work",
   "units": null,
   "inputs": [
    "p4",
    "t3"
   ],
   "hard": [
    "Receipts grew 8.6% a year over fiscal 2023 to 2025, faster than interest, so keeping the ratio flat allows rates to fall (-14.5 to -5.5 bp) -> P5"
   ],
   "facts": [],
   "decisions": [
    "P5",
    "Q6"
   ],
   "overlays": {
    "A": "what flat means"
   },
   "output": {
    "path": "results/p6_breakeven.csv",
    "format": "csv",
    "columns": [
     "year",
     "receipts_bn",
     "target_bn",
     "breakeven_bp"
    ],
    "key": [
     "year"
    ],
    "schema": "CSV with the header year,receipts_bn,target_bn,breakeven_bp and one row per year 2026 to 2030 (5 rows). receipts_bn and target_bn are in billions of dollars rounded to two decimals; breakeven_bp is the cumulative shift of the year in basis points, rounded to one decimal (negative: rates could fall)."
   },
   "checks": {
    "count": 5,
    "families": [
     {
      "id": "breakeven",
      "what": "the break-even shift",
      "count": 3,
      "select": "*/breakeven_bp",
      "tolerance": "abs 0.2"
     },
     {
      "id": "target",
      "what": "the interest target",
      "count": 2,
      "select": "*/target_bn",
      "tolerance": "abs 0.05"
     }
    ]
   },
   "level": 10
  },
  {
   "id": "R2",
   "title": "Scenario table",
   "what": "Every scenario number in one table: interest and debt of each run with the cost per basis point and the break-even shift of its year.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "p4",
    "p5",
    "p6"
   ],
   "hard": [
    "Every figure is carried from p4, p5 or p6: the table is wrong in exactly the cells its sources are -> P4"
   ],
   "facts": [],
   "decisions": [
    "P4"
   ],
   "overlays": {
    "H": "the scenario numbers"
   },
   "output": {
    "path": "results/R2_scenarios.csv",
    "format": "csv",
    "columns": [
     "rate_path",
     "infl_path",
     "year",
     "interest_bn",
     "debt_bn",
     "bn_per_bp",
     "breakeven_bp"
    ],
    "key": [
     "rate_path",
     "infl_path",
     "year"
    ],
    "schema": "CSV with the header rate_path,infl_path,year,interest_bn,debt_bn,bn_per_bp,breakeven_bp and one row per run and year (45 rows): interest_bn and debt_bn of p4, bn_per_bp of p5 for the run's inflation path and year, and breakeven_bp of p6 for the year."
   },
   "checks": {
    "count": 20,
    "families": [
     {
      "id": "interest",
      "what": "interest of every run",
      "count": 8,
      "select": "*/interest_bn",
      "tolerance": "rel 0.1%"
     },
     {
      "id": "debt",
      "what": "debt of every run",
      "count": 8,
      "select": "*/debt_bn",
      "tolerance": "rel 0.1%"
     },
     {
      "id": "bp",
      "what": "the cost per basis point",
      "count": 2,
      "select": "*/bn_per_bp",
      "tolerance": "abs 0.001"
     },
     {
      "id": "breakeven",
      "what": "the break-even shift",
      "count": 2,
      "select": "*/breakeven_bp",
      "tolerance": "abs 0.2"
     }
    ]
   },
   "level": 11
  }
 ],
 "facts": [
  {
   "id": "F1",
   "source": "S2",
   "section": "Interest expense lines",
   "text": "The interest file lists one security under different names in different line groups: Treasury Inflation Protected Securities appear as \"Inflation Protected Securities (TIPS)\" under accrued interest and as \"Treasury Inflation Protected Securities (TIPS)\" under amortized discount and amortized premium. They are the same security."
  },
  {
   "id": "F2",
   "source": "S2",
   "section": "Interest expense lines",
   "text": "\"Int. Expense Inflation Compensation (TIPS)\" is listed in the accrued-interest group, but it is the inflation compensation on TIPS principal, not coupon interest, and Treasury reports it as its own line."
  },
  {
   "id": "F3",
   "source": "S2",
   "section": "Interest expense lines",
   "text": "Amounts are published with their signs: amortized premium is published as a negative amount, so adding the published amounts of a security's lines is the same as subtracting the premium amortization. Treasury bills have no coupon: their interest is amortized discount."
  },
  {
   "id": "F4",
   "source": "S2",
   "section": "Interest expense lines",
   "text": "Interest on the Government Account Series is interest the government pays to its own trust funds and accounts (intragovernmental). The file lists it as a separate expense category from the interest on public issues."
  },
  {
   "id": "F5",
   "source": "S2",
   "section": "Interest expense lines",
   "text": "Lines that belong to none of bills, notes, bonds, TIPS and floating rate notes (savings bonds, domestic, foreign and state and local series, matured debt, and the miscellaneous interest lines) are reported together as other_public. Savings bond and miscellaneous lines are their own interest amounts: they have no accrued, discount or premium split and go in the column other_lines."
  },
  {
   "id": "F6",
   "source": "S1",
   "section": "Monthly Treasury Statement",
   "text": "Each Monthly Treasury Statement report lists the months of its own fiscal year and of the previous fiscal year, one block per year, headed `FY yyyy`; the rows with record_type_cd MTH are the months, named October to September. A month is therefore listed in every report from its own year and from the next year, and the later listings carry the revisions."
  },
  {
   "id": "F7",
   "source": "S7",
   "section": "Reference CPI of TIPS",
   "text": "The reference CPI of a TIPS on a day is the CPI-U (not seasonally adjusted) of the third month before the day's month, moved toward the CPI-U of the second month before it by the share of the month elapsed, (day - 1) divided by the days in the month. The reference CPI of the first of a month is the CPI-U of three months earlier. Treasury publishes it to five decimals."
  },
  {
   "id": "F8",
   "source": "S5",
   "section": "Auctions",
   "text": "A reopening is a further auction of an existing security and carries the CUSIP of its original issue; the file has one line per auction, so the issuance of a CUSIP is the sum over its lines. The amount issued is `awarded_amt`, the total par awarded: it includes the Federal Reserve's add-ons, which sit outside the offering amount. Cash management bills are bills."
  },
  {
   "id": "F9",
   "source": "S6",
   "section": "Par yield curve",
   "text": "Treasury added tenors to the curve during the window and the yearly files differ: the 2-month yield is published from 2018-10-16, the 4-month yield from 2022-10-19 and the 1.5-month (6-week) yield from 2025-02-18, and the column is empty on earlier days. The column headers are `1 Mo`, `2 Mo` and so on, except `1.5 Month`. Dates are month/day/year."
  },
  {
   "id": "F10",
   "source": "S3",
   "section": "Debt by security class",
   "text": "The Monthly Statement of the Public Debt names its classes Bills, Notes, Bonds, Treasury Inflation-Protected Securities, Floating Rate Notes and Federal Financing Bank; the last has no auctions. Amounts are in millions of dollars, total and held by the public (the rest is held by government accounts); TIPS are reported at inflation-adjusted principal."
  },
  {
   "id": "F11",
   "source": "S5",
   "section": "Stock rebuild",
   "text": "A security is outstanding from its issue date until the day it is redeemed. A security maturing on a weekend or a Federal Reserve holiday is redeemed on the next business day, so it is still outstanding at a month-end that falls on its maturity date when that day is not a business day. Federal Reserve holidays are New Year's Day, Martin Luther King Jr. Day, Washington's Birthday, Memorial Day, Juneteenth, Independence Day, Labor Day, Columbus Day, Veterans Day, Thanksgiving and Christmas. A holiday that falls on a Sunday is observed on the Monday; one that falls on a Saturday is not moved to the Friday, because Federal Reserve Banks stay open."
  },
  {
   "id": "F12",
   "source": "S5",
   "section": "Stock rebuild",
   "text": "A TIPS is carried at inflation-adjusted principal: its par times the reference CPI of the day divided by the reference CPI of the TIPS's original dated date (`original_dated_date`, else `dated_date`). Floating rate notes, notes, bonds and bills are carried at par."
  },
  {
   "id": "F14",
   "source": "S3",
   "section": "Reconciliation",
   "text": "Compare the rebuild with the Monthly Statement of the Public Debt for the five auctioned classes only (bills, notes, bonds, tips, frn): the Federal Financing Bank class has no auctions. The MSPD amounts are in millions of dollars and are the amount outstanding at the month-end, TIPS at inflation-adjusted principal."
  },
  {
   "id": "F15",
   "source": "S2",
   "section": "TIPS inflation compensation",
   "text": "The inflation compensation Treasury reports for a month is the accretion of TIPS principal in that month: the principal outstanding at the previous month-end times the growth of the reference CPI over the month. TIPS issued during the month and the principal of those redeemed are small next to it and are ignored in the check."
  },
  {
   "id": "F16",
   "source": "S5",
   "section": "Maturity wall",
   "text": "A maturity counts in the month of the day the security is redeemed (the next business day when it matures on a weekend or holiday). TIPS are counted at their inflation-adjusted principal as of 2025-09-30, the last reference CPI of the window, since future inflation is not known. Only the securities outstanding at 2025-09-30 mature in the wall: later issuance is not part of it."
  },
  {
   "id": "F17",
   "source": "S4",
   "section": "Reported average rates",
   "text": "Treasury's reported average interest rate of a security type is a rate on the stock outstanding at the month-end (`avg_interest_rate_amt`, percent). The year's reported rate is the value at its last month-end, September. The reported TIPS rate is the coupon rate: it does not include the inflation compensation. `Total Marketable` is the rate on bills, notes, bonds, TIPS, floating rate notes and the Federal Financing Bank together."
  },
  {
   "id": "F13",
   "source": "S5",
   "section": "Stock rebuild",
   "text": "The rebuild uses the auction file only. Treasury's buybacks, which retire securities before maturity, are not in the workspace and are not deducted."
  }
 ],
 "decisions": [
  {
   "id": "Q1",
   "question": "Which year does the client count by: the federal fiscal year or the calendar year?",
   "answer": "The client counts by federal fiscal year: October through September, labelled by the year it ends in, so 2021 runs from October 2020 to September 2021.",
   "convention": "Count by federal fiscal year, October through September, labelled by the year it ends in (2021 is October 2020 to September 2021).",
   "plausible_default": "calendar years",
   "source": "client call (decisions.json Q1)"
  },
  {
   "id": "Q2",
   "question": "Which interest lines does the client count: only interest on the public, or also interest the government pays to its own accounts?",
   "answer": "Only interest on public issues counts. Leave out the Government Account Series: it is the government paying itself.",
   "convention": "Only the public-issues category counts; leave out the Government Account Series (intragovernmental).",
   "plausible_default": "every category in the file",
   "source": "client call (decisions.json Q2)"
  },
  {
   "id": "Q3",
   "question": "What dollars does the client want constant-dollar amounts in: which base year and which CPI average?",
   "answer": "Constant fiscal-2023 dollars. Deflate each year with its own average CPI-U (all items, not seasonally adjusted, the mean of its twelve months) relative to the 2023 average.",
   "convention": "Express constant dollars in 2023 dollars: multiply by the CPI-U (all items, not seasonally adjusted) average of fiscal 2023 and divide by the average of the amount's own fiscal year, each average over that year's twelve months.",
   "plausible_default": "dollars of the latest year, 2025",
   "source": "client call (decisions.json Q3)"
  },
  {
   "id": "Q4",
   "question": "Does the client count the inflation compensation on TIPS as interest?",
   "answer": "The client counts the inflation compensation on TIPS as interest cost: it goes in the TIPS series and in the total.",
   "convention": "Count the inflation compensation on TIPS as interest cost: include that line in the TIPS series and in the total.",
   "plausible_default": "leave it out of interest",
   "source": "client call (decisions.json Q4)"
  },
  {
   "id": "Q5",
   "question": "What is a security's interest amount made of: which line groups are summed?",
   "answer": "A security's interest is its accrued interest plus its amortized discount plus its amortized premium (premium amortization is negative); treasury bills only have discount.",
   "convention": "A security's interest is its accrued interest plus its amortized discount plus its amortized premium, summing the published amounts with their signs.",
   "plausible_default": "only the accrued interest lines",
   "source": "client call (decisions.json Q5)"
  },
  {
   "id": "Q6",
   "question": "Which published figure of a month's deficit does the client use when the month appears in several Treasury statements?",
   "answer": "Use each month's figures as last revised: take them from the most recent statement that lists the month, not the first one published.",
   "convention": "Use each month's receipts, outlays and deficit as last revised: take them from the most recent statement that lists the month, not the first one published.",
   "plausible_default": "the first published figure",
   "source": "client call (decisions.json Q6)"
  },
  {
   "id": "Q10",
   "question": "In what unit and rounding are dollar figures reported in the tables?",
   "answer": "Dollar amounts go in billions of dollars, rounded to two decimals.",
   "convention": "Report dollar amounts in billions of dollars, rounded to two decimals, in every table from the interest bill on (the monthly Treasury source files stay in their own units).",
   "plausible_default": "millions of dollars",
   "source": "team convention (decisions.json Q10)"
  },
  {
   "id": "Q7",
   "question": "What balance are the implied rates divided by: the average balance or the closing one?",
   "answer": "Divide by the average of the period's twelve month-end balances, not by the closing balance.",
   "convention": "Implied rates divide by the average of the fiscal year's twelve month-end balances (the `avg_bn` of the denominator table is that average), not by the closing balance.",
   "plausible_default": "the closing balance",
   "source": "client call (decisions.json Q7)"
  },
  {
   "id": "R1",
   "question": "When is the rebuilt stock replaced by the reported stock?",
   "answer": "Keep the rebuilt stock of a class and month when it is within 0.25 percent of the reported stock; where it is further away, the month is flagged and the reported stock replaces it.",
   "convention": "Reconciliation: a class-month is flagged when the rebuilt stock differs from the reported stock by more than 0.25 percent of the reported stock; the corrected stock keeps the rebuilt amount where it is not flagged and takes the reported amount where it is.",
   "plausible_default": "keep every rebuilt amount",
   "source": "builder's choice: no client call on record for the reconciliation, pending the user's review"
  },
  {
   "id": "Q8",
   "question": "How is the change in interest split when rates and debt both move: where does the cross term go?",
   "answer": "The cross term goes to the rate effect: the rate effect is the change in the rate times the new debt, and the volume effect is the change in debt times the old rate.",
   "convention": "In the decomposition the cross term goes to the rate effect: rate effect = change in rate x new average stock, volume effect = change in average stock x old rate, with the rate the unrounded interest over the average stock.",
   "plausible_default": "the cross term goes to the volume effect",
   "source": "client call (decisions.json Q8)"
  },
  {
   "id": "Q11",
   "question": "How are rates written in the tables?",
   "answer": "Rates are written in percent, rounded to three decimals: 3.264 means 3.264 percent, never a fraction.",
   "convention": "Write rates in percent, rounded to three decimals (3.264 means 3.264 percent), not as fractions.",
   "plausible_default": "fractions",
   "source": "team convention (decisions.json Q11)"
  },
  {
   "id": "Q13",
   "question": "How are a scenario's basis points applied over the years?",
   "answer": "A scenario's basis points are added every year, cumulatively: the 50 scenario is +50 in the first year, +100 in the second and +150 in the third, on top of the rate of the last year of data.",
   "convention": "A scenario's basis points are added cumulatively every year: +50, +100, +150 and so on in the first, second and third year after 2025 for the 50 scenario, on top of the last year's rate.",
   "plausible_default": "a one-time step",
   "source": "team convention (decisions.json Q13)"
  },
  {
   "id": "P2",
   "question": "How is maturing debt reissued in the projection?",
   "answer": "Bills roll into bills. The principal of notes, bonds, TIPS and floaters that matures is reissued across those four classes in the proportions of fiscal 2025's gross issuance (the bill share left out: gross bill issuance is a roll-over, not a funding choice). New issuance other than bills is assumed to mature after 2030.",
   "convention": "Projection: bills roll into bills; maturing notes, bonds, TIPS and floaters are reissued across notes, bonds, TIPS and floaters in the proportions of fiscal 2025's issuance amounts; new issuance other than bills matures after 2030.",
   "plausible_default": "all maturing debt reissued at the full gross mix, bills included",
   "source": "builder's choice: no client call on record for the rollover, pending the user's review"
  },
  {
   "id": "P3",
   "question": "What is the marginal (new-issue) rate of a class?",
   "answer": "The awarded-weighted average of the year's auction yields of the class (the investment rate for bills, the real yield for TIPS). For floating rate notes, the year's mean 3-month par yield plus the awarded-weighted spread. A year is the fiscal year of the issue date.",
   "convention": "Marginal rates: per fiscal year of the issue date, the awarded-weighted average of the auction yields of the class (investment rate for bills, real yield for TIPS); for floating rate notes the fiscal year's mean 3-month par yield plus the awarded-weighted spread.",
   "plausible_default": "the average coupon of the securities issued in the year",
   "source": "builder's choice: no client call on record for the marginal rate, pending the user's review"
  },
  {
   "id": "Q9",
   "question": "What primary deficit do the scenarios assume?",
   "answer": "Hold the primary deficit at the average of the last three years' primary deficits (fiscal 2023 to 2025), the same nominal amount every year.",
   "convention": "In the scenarios the primary deficit (the deficit less interest) is the average of the primary deficits of fiscal 2023, 2024 and 2025 (the deficit as last revised, the interest of the whole of public issues), the same nominal amount every year.",
   "plausible_default": "the 2025 primary deficit",
   "source": "client call (decisions.json Q9)"
  },
  {
   "id": "P4",
   "question": "How does the scenario engine run?",
   "answer": "Per year 2026 to 2030 and class: the stock is the rollover stock plus the earlier borrowing of the class; bills and floaters pay the year's path rate; notes, bonds and TIPS blend their average rate with the path rate on the fresh amount (the year's reissue plus last year's borrowing), starting from Treasury's reported September 2025 average rate of the class (for TIPS the reported coupon rate). TIPS inflation compensation is the TIPS stock times the path's inflation, scaled by the ratio of reported to computed accrual over fiscal 2025. Borrowing is the primary deficit plus the year's interest, split across notes, bonds, TIPS and floaters like the rollover's reissue of 2026; debt is the stocks plus the year's borrowing.",
   "convention": "Scenario engine: for year y and class c, S = rollover stock + earlier borrowing of the class. Bills and floaters pay the path rate of the year; notes, bonds and TIPS: E = ((S - fresh) x E_previous + fresh x path rate) / S, with fresh the year's reissue plus last year's borrowing of the class and E for 2025 Treasury's reported September 2025 rate (TIPS: the reported coupon rate). Interest = sum of E x S / 100 over the five classes + TIPS inflation compensation = TIPS S x the path's annual inflation x (reported / computed accrual of fiscal 2025, the TIPS accrual check). Borrowing = primary deficit + interest, split over notes, bonds, TIPS and floaters like the rollover's reissue of 2026; end debt = sum of S + borrowing.",
   "plausible_default": "every class reprices fully every year",
   "source": "builder's choice: no client call on record for the engine, pending the user's review"
  },
  {
   "id": "P5",
   "question": "What does keeping interest over receipts flat mean?",
   "answer": "Receipts of fiscal 2025 grow at their mean annual growth of fiscal 2023 to 2025; the target is the ratio of interest to receipts of fiscal 2026 on the +0 basis point, base-inflation path, applied to each year's receipts; the break-even is the cumulative shift between the +0 and +100 base-inflation paths that reaches the target.",
   "convention": "Break-even: receipts of fiscal 2025 grow at their mean annual growth rate of fiscal 2023 to 2025; the interest target of a year is the interest-to-receipts ratio of fiscal 2026 on the +0 bp, base-inflation path times that year's receipts; the break-even shift is the cumulative shift, by linear interpolation between the +0 and +100 bp base-inflation paths, that reaches the target.",
   "plausible_default": "keep the fiscal 2025 ratio",
   "source": "builder's choice, pending the user's review"
  },
  {
   "id": "P1",
   "question": "How are the three inflation paths for the TIPS cost drawn?",
   "answer": "From the last CPI-U of the window (September 2025), the CPI-U compounds monthly at the trailing twelve-month inflation rate (September 2025 over September 2024) for the base path, and at that rate minus 1.5 and plus 1.5 percentage points for the low and high paths.",
   "convention": "Inflation paths: from the September 2025 CPI-U, compound monthly at the trailing twelve-month rate (September 2025 over September 2024) for the base path, and at that rate minus 1.5 and plus 1.5 percentage points for the low and high paths: cpi(k) = cpi(Sep 2025) x (1 + rate)^(k/12) for the k-th month after September 2025.",
   "plausible_default": "a flat 2 percent a year on every path",
   "source": "builder's choice: no client call on record for the scenario inflation, pending the user's review"
  }
 ]
}
GRAPH_JSON_EOF
cat > "$T/taskgraph.py" <<'TASKGRAPH_EOF'
"""Graph-task kit, the pure part: graph.json loading, levels and stages, instruction rendering, output parsing and the
check comparator. Standard library only: write_task ships this file as tests/taskgraph.py (the grader and the
reference's CLI import it), so it must not import anything from collabbench.

graph.json (see the contract): sources and nodes. A node reads sources and upstream nodes; its level is its longest-path
distance from the sources (sources are level 0), computed here from the inputs and never trusted from the file.

Outputs. A node writes one file at output.path, format "json" or "csv". The parsed form of an output is what the
reference functions receive for their upstream nodes and what the comparator walks:
- json: whatever json.loads returns (NaN and Infinity are refused);
- csv: a list of row dicts, one per line under the header, each value coerced ("" -> None, integers, floats, else str).
  A csv node declares output.columns (the header) and output.key (the columns that identify a row).
A reference function returns the JSON-able form (a csv node: a list of row dicts); `roundtrip` serialises and parses it,
so expected and agent outputs always meet in the same parsed form.

Checks. Each node declares check families: {"id", "what", "count", "tolerance", "select", "fields"?}.
- `select` is a "/"-separated path into the parsed output ("*" matches every key of a dict or every item of a list).
  A csv node is keyed first: {"<key1>|<key2>": row}, so "*/anti_slope" is the anti_slope cell of every row.
- Every match in the REFERENCE output is one check. A selected scalar is compared under the family's tolerance. A selected
  dict is compared on `fields` (default: every key); the check passes when all of them do. With tolerance "set" a
  selected list is compared as a set of items (one check).
- A family may restrict its items to rows of the REFERENCE output: "where" (rows matching) and "where_not" (rows not
  matching), each {column: [values]} or a list of such dicts (any one may match), so that one family is one lab fact.
- tolerance: "exact" | "abs X" | "rel P%" | "set" | "rel P% or abs X" (within either). Numbers compare as numbers (1 == 1.0), booleans only with booleans,
  None only with None. A path absent from the agent's output fails its check. Extra keys, rows or items are ignored.
"""

import csv
import io
import json
import math
import re
from collections import deque
from pathlib import Path

KINDS = ("src", "work", "rework", "deliv")
NODE_REQUIRED = ("id", "title", "inputs", "output", "checks")
_INT = re.compile(r"-?[0-9]+")


class GraphError(ValueError):
    """graph.json is not a valid graph."""


# ---- loading, levels, stages -----------------------------------------------------------------------------------------

class Graph:
    def __init__(self, data: dict):
        self.data = data
        self.title = data.get("title", data.get("graph", ""))
        self.name = data["graph"]
        self.sources = {s["id"]: s for s in data.get("sources", [])}
        nodes = data.get("nodes", [])
        self.nodes = {n["id"]: n for n in nodes}
        if len(self.sources) != len(data.get("sources", [])) or len(self.nodes) != len(nodes):
            raise GraphError("duplicate id")
        if set(self.sources) & set(self.nodes):
            raise GraphError(f"ids used by a source and a node: {sorted(set(self.sources) & set(self.nodes))}")
        self.facts = {f["id"]: f for f in data.get("facts", [])}
        self.decisions = {d["id"]: d for d in data.get("decisions", [])}
        self.level = self._levels()
        self.stages = self._stages()
        for nid, n in self.nodes.items():
            if "level" in n and n["level"] != self.level[nid]:
                raise GraphError(f"node {nid}: level {n['level']} in the file, {self.level[nid]} from its inputs")
            n["level"] = self.level[nid]
            for fid in n.get("facts", []):
                if fid not in self.facts:
                    raise GraphError(f"node {nid}: unknown fact {fid}")
            for qid in n.get("decisions", []):
                if qid not in self.decisions:
                    raise GraphError(f"node {nid}: unknown decision {qid}")

    def _levels(self) -> dict[str, int]:
        for nid, n in self.nodes.items():
            for k in NODE_REQUIRED:
                if k not in n:
                    raise GraphError(f"node {nid}: missing {k}")
            for i in n["inputs"]:
                if i not in self.sources and i not in self.nodes:
                    raise GraphError(f"node {nid}: unknown input {i}")
        level = {s: 0 for s in self.sources}
        indeg = {nid: sum(i in self.nodes for i in n["inputs"]) for nid, n in self.nodes.items()}
        ready = deque(nid for nid, d in indeg.items() if d == 0)
        done = 0
        while ready:
            nid = ready.popleft()
            done += 1
            level[nid] = 1 + max((level[i] for i in self.nodes[nid]["inputs"]), default=0)
            for m, n in self.nodes.items():
                if nid in n["inputs"]:
                    indeg[m] -= 1
                    if indeg[m] == 0:
                        ready.append(m)
        if done != len(self.nodes):
            raise GraphError(f"cycle among {sorted(set(self.nodes) - set(level))}")
        return level

    def _stages(self) -> list[list[int]]:
        top = max(self.level.values(), default=0)
        stages = self.data.get("stages") or [[i, i] for i in range(1, top + 1)]
        prev = 0
        for first, last in stages:
            if first != prev + 1 or last < first:
                raise GraphError(f"stages must be contiguous groups of levels starting at 1: {stages}")
            prev = last
        if prev != top:
            raise GraphError(f"stages end at level {prev}, the graph at {top}")
        return [list(s) for s in stages]

    @property
    def n_stages(self) -> int:
        return len(self.stages)

    def last_level(self, stage: int) -> int:
        return self.stages[stage - 1][1]

    def stage_nodes(self, stage: int) -> list[str]:
        """The nodes that stage `stage` exposes: every node of level <= the stage's last level (stages are cumulative;
        graph.json's optional "stages" is a list of [first_level, last_level] pairs, default one level per stage)."""
        last = self.last_level(stage)
        return [nid for nid, n in self.nodes.items() if n["level"] <= last]

    def stage_sources(self, stage: int) -> list[str]:
        return list(self.sources)  # sources are complete from stage 1 on: every file is in the workspace

    def upstream_nodes(self, nid: str) -> list[str]:
        return [i for i in self.nodes[nid]["inputs"] if i in self.nodes]

    def order(self, stage: int) -> list[str]:
        """The stage's nodes with upstream before downstream."""
        out, seen = [], set()

        def visit(nid):
            if nid in seen:
                return
            seen.add(nid)
            for u in self.upstream_nodes(nid):
                visit(u)
            out.append(nid)
        for nid in self.stage_nodes(stage):
            visit(nid)
        return out

    @property
    def max_level(self) -> int:
        return max((n["level"] for n in self.nodes.values()), default=0)


def load_graph(source) -> Graph:
    if isinstance(source, dict):
        return Graph(json.loads(json.dumps(source)))
    return Graph(json.loads(Path(source).read_text()))


# ---- instruction ----------------------------------------------------------------------------------------------------

def render_instruction(g: Graph, stage: int, intro: str = "", reserved: str = "", notes: str = "") -> str:
    """The agent's instruction for a stage: each node's output path, schema and what, and what it reads. Never the facts,
    the decisions or the nodes' `hard` notes."""
    names = g.order(stage)
    lines = [f"# {g.title}", ""]
    if intro.strip():
        lines += [intro.strip(), ""]
    used = [s for s in g.sources if any(s in g.nodes[n]["inputs"] for n in names)]
    lines += ["## Sources", ""]
    for sid in used:
        s = g.sources[sid]
        lines.append(f"- **{sid}**, " + ", ".join(f"`{f}`" for f in s["files"]) + (f": {s['what']}" if s.get("what") else ""))
    unused = [s for s in g.sources if s not in used]
    if unused:
        lines.append("- Also in the workspace, for later steps: " +
                     ", ".join(f"{s} ({', '.join(f'`{f}`' for f in g.sources[s]['files'])})" for s in unused) + ".")
    if notes:
        lines += ["", f"The team's records are in `{notes}`; read them before you start."]
    lines += ["", "## What to produce", "",
              f"Stage {stage} has {len(names)} deliverable{'s' if len(names) != 1 else ''}, each one file under "
              "`/workspace/results/` at the exact path given. A deliverable that reads another one is built from that "
              "file's correct content, so mistakes carry downstream. Each file is scored against a reference "
              "computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you "
              "like, but the deliverables are the files, not a program.", ""]
    for nid in names:
        n = g.nodes[nid]
        out = n["output"]
        reads = [f"{i} (`{g.sources[i]['files'][0]}`{'...' if len(g.sources[i]['files']) > 1 else ''})"
                 if i in g.sources else f"{i} (`{g.nodes[i]['output']['path']}`)" for i in n["inputs"]]
        units = f" ({n['units']} units, graded separately inside the file)" if n.get("units") else ""
        lines += [f"### {nid}: {n['title']}{units}", "",
                  n.get("what", ""), "",
                  f"- Reads: {', '.join(reads)}",
                  f"- Writes: `/workspace/{out['path']}` ({out['format']})",
                  f"- Format: {out['schema']}", ""]
    if reserved:
        lines += [reserved.strip(), ""]
    return "\n".join(lines).rstrip() + "\n"


# ---- outputs: serialise and parse -------------------------------------------------------------------------------------

def _refuse_constant(name):
    raise ValueError(f"{name} is not valid JSON")


def coerce(text: str):
    t = text.strip()
    if t == "":
        return None
    if _INT.fullmatch(t):
        return int(t)
    try:
        x = float(t)
    except ValueError:
        return text
    return x if math.isfinite(x) else text


def _cell(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if not math.isfinite(v):
            raise ValueError("non-finite number")
        return repr(v)
    return str(v)


def serialize(node: dict, obj) -> str:
    out = node["output"]
    if out["format"] == "json":
        return json.dumps(obj, indent=1, allow_nan=False) + "\n"
    cols = out["columns"]
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(cols)
    for row in obj:
        if set(row) - set(cols):
            raise ValueError(f"row has columns outside the header: {sorted(set(row) - set(cols))}")
        w.writerow([_cell(row.get(c)) for c in cols])
    return buf.getvalue()


def parse_output(node: dict, data: bytes | str):
    """The parsed form of an output file; raises ValueError when it is malformed."""
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    out = node["output"]
    if out["format"] == "json":
        return json.loads(text, parse_constant=_refuse_constant)
    rows = list(csv.reader(io.StringIO(text)))
    if not rows or not rows[0]:
        raise ValueError("empty csv")
    header = [h.strip() for h in rows[0]]
    if len(set(header)) != len(header):
        raise ValueError("duplicate column")
    parsed = []
    for r in rows[1:]:
        if not r or all(not c.strip() for c in r):
            continue
        if len(r) != len(header):
            raise ValueError("a row's width differs from the header")
        parsed.append({h: coerce(c) for h, c in zip(header, r)})
    return parsed


def roundtrip(node: dict, obj):
    return parse_output(node, serialize(node, obj))


def keyed(node: dict, parsed):
    """The comparison view of a parsed output: a csv node's rows keyed by their key columns; a duplicate key is malformed."""
    if node["output"]["format"] != "csv":
        return parsed
    key = node["output"]["key"]
    out = {}
    for row in parsed:
        if any(k not in row or row[k] is None for k in key):
            raise ValueError("a row lacks its key")
        k = "|".join(str(row[c]) for c in key)
        if k in out:
            raise ValueError(f"duplicate key {k}")
        out[k] = row
    return out


# ---- the comparator ------------------------------------------------------------------------------------------------------

def parse_tolerance(text: str) -> tuple[str, float]:
    t = text.strip().lower()
    if " or " in t:  # "rel 1% or abs 0.001": a value passes when it is within either
        return "any", [parse_tolerance(part) for part in t.split(" or ")]
    if t in ("exact", "set"):
        return t, 0.0
    m = re.fullmatch(r"abs\s+([0-9.eE+-]+)", t)
    if m:
        return "abs", float(m.group(1))
    m = re.fullmatch(r"rel\s+([0-9.eE+-]+)\s*%", t)
    if m:
        return "rel", float(m.group(1)) / 100
    raise GraphError(f"unknown tolerance {text!r}")


def _is_num(x) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def values_match(want, got, tol: tuple) -> bool:
    kind, t = tol
    if kind == "any":
        return any(values_match(want, got, one) for one in t)
    if isinstance(want, dict):
        return isinstance(got, dict) and all(k in got and values_match(v, got[k], tol) for k, v in want.items())
    if isinstance(want, list):
        if kind == "set":
            if not isinstance(got, list):
                return False
            dump = lambda xs: {json.dumps(x, sort_keys=True) for x in xs}  # noqa: E731
            return dump(want) == dump(got)
        return (isinstance(got, list) and len(got) == len(want)
                and all(values_match(a, b, tol) for a, b in zip(want, got)))
    if want is None or isinstance(want, (bool, str)):
        return type(got) is type(want) and got == want
    if not _is_num(got):
        return False
    if isinstance(got, float) and not math.isfinite(got):
        return False
    if kind == "exact" or kind == "set":
        return got == want
    if kind == "abs":
        return abs(got - want) <= t + 1e-12
    return abs(got - want) <= t * abs(want) + 1e-12


def select(obj, path: str):
    """Yield (concrete path tuple, value) for every match of `path` ("a/*/b") in `obj`."""
    def walk(o, parts, here):
        if not parts:
            yield here, o
            return
        head, rest = parts[0], parts[1:]
        if head == "*":
            items = o.items() if isinstance(o, dict) else enumerate(o) if isinstance(o, list) else ()
            for k, v in items:
                yield from walk(v, rest, here + (str(k),))
        elif isinstance(o, dict) and head in o:
            yield from walk(o[head], rest, here + (head,))
        elif isinstance(o, list) and head.isdigit() and int(head) < len(o):
            yield from walk(o[int(head)], rest, here + (head,))
    yield from walk(obj, [p for p in path.split("/") if p != ""], ())


def lookup(obj, path: tuple[str, ...]):
    """The value at a concrete path, or raise KeyError."""
    for p in path:
        if isinstance(obj, dict) and p in obj:
            obj = obj[p]
        elif isinstance(obj, list) and p.isdigit() and int(p) < len(obj):
            obj = obj[int(p)]
        else:
            raise KeyError(p)
    return obj


def _row_in(row, conds) -> bool:
    """`conds` is a dict {column: [values]} (all must hold) or a list of such dicts (any may hold)."""
    if isinstance(conds, dict):
        conds = [conds]
    return any(isinstance(row, dict) and all(row.get(c) in vals for c, vals in cond.items()) for cond in conds)


def expand_checks(node: dict, expected) -> list[dict]:
    """Every check of a node, from its reference output (parsed form, csv already keyed): one dict per check with the
    family id, the concrete path, the wanted value, the tolerance and the fields compared."""
    out = []
    for fam in node["checks"]["families"]:
        tol = parse_tolerance(fam["tolerance"])
        for path, value in select(expected, fam["select"]):
            if "where" in fam and not _row_in(value, fam["where"]):
                continue
            if "where_not" in fam and _row_in(value, fam["where_not"]):
                continue
            want = value
            if fam.get("fields") and isinstance(value, dict):
                want = {f: value[f] for f in fam["fields"]}
            out.append({"family": fam["id"], "path": path, "want": want, "tol": tol})
    return out


def evaluate(checks: list[dict], got, against=None) -> dict:
    """Run the checks on the agent's keyed output. `against` (a keyed output, the reference re-run on the agent's own
    upstream data) supplies the wanted values instead of each check's own, for the conditional score; a path it lacks fails."""
    per, passed = {}, 0
    for c in checks:
        ok = False
        try:
            want = c["want"] if against is None else lookup(against, c["path"])
            if against is not None and isinstance(c["want"], dict) and isinstance(want, dict):
                want = {f: want[f] for f in c["want"]}
            ok = values_match(want, lookup(got, c["path"]), c["tol"])
        except (KeyError, TypeError):
            ok = False
        fam = per.setdefault(c["family"], [0, 0])
        fam[1] += 1
        fam[0] += ok
        passed += ok
    return {"passed": passed, "total": len(checks), "families": per}


def node_score(node: dict, res: dict) -> float:
    """A node's score from `evaluate`: the mean of its families' scores weighted by each family's declared `count`; a
    family's score is the fraction of its items (rows, keys or cells) that match, so a family over many items gives
    partial credit and a family declared once (count 1) contributes its item fraction."""
    num = den = 0.0
    for fam in node["checks"]["families"]:
        p, t = res["families"].get(fam["id"], [0, 0])
        w = float(fam.get("count", t))
        num += w * (p / t if t else 0.0)
        den += w
    return num / den if den else 0.0


# ---- reference runs --------------------------------------------------------------------------------------------------

def run_reference(g: Graph, ref, src, stage: int) -> dict:
    """Every node output of stage <= `stage` from `ref.node_<id>(up, src)`, in the roundtripped parsed form."""
    outputs: dict = {}
    for nid in g.order(stage):
        fn = getattr(ref, f"node_{nid}", None)
        if fn is None:
            raise NotImplementedError(f"reference has no node_{nid}")
        up = {u: outputs[u] for u in g.upstream_nodes(nid)}
        outputs[nid] = roundtrip(g.nodes[nid], fn(up, Path(src)))
    return outputs


def write_outputs(g: Graph, outputs: dict, out_dir) -> list[Path]:
    paths = []
    for nid, obj in outputs.items():
        p = Path(out_dir) / g.nodes[nid]["output"]["path"]
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(serialize(g.nodes[nid], obj))
        paths.append(p)
    return paths


def reference_cli(ref_module, graph_json, argv=None) -> None:
    """python reference.py <src_dir> <out_dir> --stage S: write every node output of stage <= S under <out_dir>."""
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("out")
    p.add_argument("--stage", type=int, required=True)
    a = p.parse_args(argv)
    g = load_graph(graph_json)
    write_outputs(g, run_reference(g, ref_module, a.src, a.stage), a.out)
TASKGRAPH_EOF
cat > "$T/reference.py" <<'REFERENCE_EOF'
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
REFERENCE_EOF
cat > "$T/run.py" <<'RUNNER_EOF'
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import taskgraph  # noqa: E402

spec = importlib.util.spec_from_file_location("graph_reference", HERE / "reference.py")
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)
taskgraph.reference_cli(ref, HERE / "graph.json")
RUNNER_EOF
python3 -I "$T/run.py" "$W" "$W" --stage 4
