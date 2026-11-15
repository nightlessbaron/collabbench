# Federal interest cost

The US Treasury publishes the federal government's borrowing and its interest cost in several monthly and daily datasets. A budget think tank wants a proper picture of what the government pays on its debt, from October 2016 to September 2025. `data/` holds the Treasury's own files, snapshots taken on 2026-11-15 (the Monthly Treasury Statement, interest expense, the Monthly Statement of the Public Debt, average interest rates, every auction of the securities outstanding in the window, the daily par yield curve) and the CPI-U. The deliverables below rebuild the quantities step by step: nothing in the data files has been converted. Cells that Treasury had no value for are empty or the text `null`.

## Sources

- **S1**, `data/mts_table_1.csv`: Monthly Treasury Statement, table 1: receipts, outlays and the deficit by month, every report with its revisions
- **S2**, `data/interest_expense.csv`: Interest Expense on the Public Debt Outstanding: one line per month and line item, in US dollars
- **S3**, `data/mspd_table_1.csv`: Monthly Statement of the Public Debt, table 1: the debt outstanding at each month-end by security class, in millions of dollars
- **S5**, `data/auctions.csv`: Every auction of every security that matures on or after October 2016 and was issued by September 2025, one line per auction, by CUSIP
- **S6**, `data/par_yield_curve/2016.csv`, `data/par_yield_curve/2017.csv`, `data/par_yield_curve/2018.csv`, `data/par_yield_curve/2019.csv`, `data/par_yield_curve/2020.csv`, `data/par_yield_curve/2021.csv`, `data/par_yield_curve/2022.csv`, `data/par_yield_curve/2023.csv`, `data/par_yield_curve/2024.csv`, `data/par_yield_curve/2025.csv`: The daily Treasury par yield curve in percent, one file per calendar year
- **S7**, `data/cpi_u_nsa.csv`: CPI-U, all items, not seasonally adjusted, monthly index level (1982-1984 = 100)
- Also in the workspace, for later steps: S4 (`data/avg_interest_rates.csv`).

The team's records are in `docs/notes.md`; read them before you start.

## What to produce

Stage 2 has 17 deliverables, each one file under `/workspace/results/` at the exact path given. A deliverable that reads another one is built from that file's correct content, so mistakes carry downstream. Each file is scored against a reference computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you like, but the deliverables are the files, not a program.

### t1: Month calendar

For every month from October 2016 to September 2025: the year and quarter this work counts it in, and how the Monthly Treasury Statement lists it (how many of its reports list the month, and the date of the latest one).

- Reads: S1 (`data/mts_table_1.csv`)
- Writes: `/workspace/results/t1_calendar.csv` (csv)
- Format: CSV with the header month,year,quarter,n_reports,latest_report and one row per month (108 rows). month is YYYY-MM; year and quarter are the year (four digits) and the quarter (1 to 4) the month is counted in; n_reports is the number of Monthly Treasury Statement reports (distinct record_date values) that list the month; latest_report is the record_date (YYYY-MM-DD) of the latest of them.

### t2: Expense lines

Interest expense per month for each security class (bills, notes, bonds, tips, frn, other_public) and for the total of public issues, from October 2016 to September 2025. Each class row gives the published amounts grouped as accrued, discount, premium, inflation compensation and other lines, and the interest this work counts for the row.

- Reads: S2 (`data/interest_expense.csv`)
- Writes: `/workspace/results/t2_interest_lines.csv` (csv)
- Format: CSV with the header month,security,accrued,discount,premium,inflation_comp,other_lines,interest and one row per month and security (108 months x 7 securities = 756 rows). security is one of bills, notes, bonds, tips, frn, other_public, total. The first five amount columns sum the published month_expense_amt of the security's lines by group: accrued (accrued interest lines), discount (amortized discount), premium (amortized premium, as published, negative), inflation_comp (the TIPS inflation compensation line), other_lines (savings bond and miscellaneous lines). interest is the amount counted for the row. All in US dollars, to the cent. The total row sums the six class rows.

### t3: Statement vintages

One value per month for receipts, outlays and the deficit, from October 2016 to September 2025, with the report each comes from, plus the deficit as first published and the revision.

- Reads: S1 (`data/mts_table_1.csv`)
- Writes: `/workspace/results/t3_vintages.csv` (csv)
- Format: CSV with the header month,receipts,outlays,deficit,source_report,deficit_first,revision and one row per month (108 rows). month is YYYY-MM. receipts, outlays and deficit (outlays minus receipts, positive is a deficit) are the month's figures this work uses, in US dollars; source_report is the record_date (YYYY-MM-DD) of the report they come from; deficit_first is the deficit in the first report that lists the month; revision is deficit minus deficit_first.

### t4: Security panel

Outstanding debt per marketable class per month-end from the Monthly Statement of the Public Debt, October 2016 to September 2025, with the part held by the public.

- Reads: S3 (`data/mspd_table_1.csv`)
- Writes: `/workspace/results/t4_panel.csv` (csv)
- Format: CSV with the header month,class,total_mil,public_mil and one row per month and class (108 months x 7 classes = 756 rows). class is one of bills, notes, bonds, tips, frn, ffb (Federal Financing Bank), total_marketable. total_mil is the amount outstanding and public_mil the part held by the public, both in millions of dollars as published.

### t5: Auction ledger

Issuance per CUSIP over every auction of it in the auction file: its class, maturity, first issue date, number of auctions, total awarded and the auctions themselves.

- Reads: S5 (`data/auctions.csv`)
- Writes: `/workspace/results/t5_ledger.json` (json)
- Format: JSON object keyed by CUSIP, one entry per distinct CUSIP of data/auctions.csv (1,834 entries). Each entry has: class (bills, notes, bonds, tips or frn; cash management bills are bills); maturity and first_issue (YYYY-MM-DD, the maturity date and the earliest issue date); n_auctions (number of lines of the CUSIP); issuance (the sum of its awarded_amt, integer dollars); coupon (the stated coupon in percent, null where the file has none); dated (the original dated date if any else the dated date, null for bills); auctions (a list, in issue-date order, of {issue, awarded, yield, spread}, one per line: the issue date, its awarded_amt, its yield or investment rate in percent and its spread, null where the file has none).

### t6: Curve panel

A clean daily Treasury par yield curve for every trading day from October 2016 to September 2025: one row per day, one column per tenor, in percent.

- Reads: S6 (`data/par_yield_curve/2016.csv`...)
- Writes: `/workspace/results/t6_curve.csv` (csv)
- Format: CSV with the header date,m1,m1_5,m2,m3,m4,m6,y1,y2,y3,y5,y7,y10,y20,y30 and one row per day of the files within 2016-10-01 to 2025-09-30 (2,248 rows). date is YYYY-MM-DD; m1, m1_5, m2, m3, m4, m6 are the 1-, 1.5-, 2-, 3-, 4- and 6-month yields and y1 to y30 the 1- to 30-year yields, in percent; a tenor not yet published on the day is left empty.

### t7: Inflation inputs

The CPI-U of each calendar day's month and the daily TIPS reference CPI, for every calendar day from 2016-10-01 to 2025-09-30.

- Reads: S7 (`data/cpi_u_nsa.csv`)
- Writes: `/workspace/results/t7_cpi.csv` (csv)
- Format: CSV with the header date,cpi,ref_cpi and one row per calendar day (3,287 rows). date is YYYY-MM-DD; cpi is the CPI-U (not seasonally adjusted) of the day's month; ref_cpi is the TIPS reference CPI of the day, rounded to five decimals.

### r1: Stock rebuild (x5 classes units, graded separately inside the file)

Par outstanding at every month-end from October 2016 to September 2025 for each of bills, notes, bonds, tips and frn, rebuilt from the auction ledger and the reference CPI.

- Reads: t5 (`results/t5_ledger.json`), t7 (`results/t7_cpi.csv`)
- Writes: `/workspace/results/r1_stock.csv` (csv)
- Format: CSV with the header month,class,outstanding and one row per month and class (108 months x 5 classes = 540 rows). month is YYYY-MM (the month-end is its last calendar day); class is bills, notes, bonds, tips or frn; outstanding is the amount outstanding at that month-end in US dollars (TIPS at inflation-adjusted principal).

### a1: Interest by class (x6 classes units, graded separately inside the file)

The interest bill per year and security class: for each year and each class, and the total, the sum of that year's monthly interest.

- Reads: t2 (`results/t2_interest_lines.csv`), t1 (`results/t1_calendar.csv`)
- Writes: `/workspace/results/a1_interest.csv` (csv)
- Format: CSV with the header year,class,interest_bn and one row per year and class (9 years x 7 classes = 63 rows). year is the four-digit year this work counts by, 2017 to 2025; class is bills, notes, bonds, tips, frn, other_public or total; interest_bn is the interest in billions of dollars, rounded to two decimals.

### a10: Issuance mix

Gross issuance per year (by issue date) in billions of dollars by class, and the shares of bills, coupons (notes and bonds together), TIPS and floating rate notes in percent.

- Reads: t5 (`results/t5_ledger.json`), t1 (`results/t1_calendar.csv`)
- Writes: `/workspace/results/a10_mix.csv` (csv)
- Format: CSV with the header year,bills_bn,notes_bn,bonds_bn,tips_bn,frn_bn,total_bn,bills_pct,coupons_pct,tips_pct,frn_pct and one row per year, 2017 to 2025 (9 rows). Amounts are the total par awarded by auctions whose issue date falls in the year, in billions of dollars, rounded to two decimals (cash management bills count as bills); the four shares are percent of total_bn, rounded to three decimals.

### p3: Inflation paths (x3 paths units, graded separately inside the file)

Three CPI-U paths for the TIPS cost: low, base and high, monthly from October 2025 to September 2030.

- Reads: t7 (`results/t7_cpi.csv`)
- Writes: `/workspace/results/p3_inflation.csv` (csv)
- Format: CSV with the header path,month,annual_rate_pct,cpi and one row per path and month (3 paths x 60 months = 180 rows). path is low, base or high; month is YYYY-MM from 2025-10 to 2030-09; annual_rate_pct is the path's annual inflation rate in percent, rounded to four decimals; cpi is the path's CPI-U level, rounded to five decimals.

### r2: Reconciliation (x5 classes units, graded separately inside the file)

The rebuild against Treasury's reported stock: for each month-end and each of bills, notes, bonds, tips and frn, the rebuilt and the reported amount, the residual, and whether the month is flagged.

- Reads: r1 (`results/r1_stock.csv`), t4 (`results/t4_panel.csv`)
- Writes: `/workspace/results/r2_reconciliation.csv` (csv)
- Format: CSV with the header month,class,rebuilt,reported,residual,residual_pct,flagged and one row per month and class (540 rows). month is YYYY-MM; rebuilt is r1's outstanding and reported the MSPD outstanding of the class, both in US dollars; residual is rebuilt minus reported in dollars and residual_pct in percent of reported (four decimals); flagged is 1 when the month is flagged for that class and 0 when it is not.

### a6: Real terms

Interest and the deficit in constant dollars: per year, the CPI average, the nominal interest and deficit and their values in constant dollars.

- Reads: a1 (`results/a1_interest.csv`), t3 (`results/t3_vintages.csv`), t7 (`results/t7_cpi.csv`), t1 (`results/t1_calendar.csv`)
- Writes: `/workspace/results/a6_real.csv` (csv)
- Format: CSV with the header year,cpi_avg,interest_nom_bn,deficit_nom_bn,interest_real_bn,deficit_real_bn and one row per year, 2017 to 2025 (9 rows). cpi_avg is the CPI-U average used to deflate the year (three decimals); the four amounts are in billions of dollars rounded to two decimals: the total interest (a1) and the deficit (t3, deficit positive) of the year as published, and the same two in constant dollars.

### r3: Stock, round 2 (x5 classes units, graded separately inside the file)

The corrected stock by class and month: the rebuild where it reconciles and Treasury's reported stock where the month is flagged.

- Reads: r2 (`results/r2_reconciliation.csv`), r1 (`results/r1_stock.csv`)
- Writes: `/workspace/results/r3_stock.csv` (csv)
- Format: CSV with the header month,class,stock,rebuilt,source and one row per month and class (540 rows). stock is the corrected outstanding amount in US dollars; rebuilt is r1's amount; source is `rebuilt` where stock is r1's amount and `reported` where it is the reported stock.

### a2: Debt held by public

The denominator of the implied rates: for each year and class and for the total, the average of the twelve month-end stocks and the closing stock, in billions of dollars.

- Reads: r3 (`results/r3_stock.csv`), t1 (`results/t1_calendar.csv`)
- Writes: `/workspace/results/a2_denominator.csv` (csv)
- Format: CSV with the header year,class,avg_bn,end_bn and one row per year and class (9 years x 6 = 54 rows). class is bills, notes, bonds, tips, frn or total (the sum of the five); avg_bn is the denominator for the year and end_bn the stock at the year's last month-end, in billions of dollars rounded to two decimals.

### a4: TIPS accrual check

The inflation compensation each month implies from the corrected TIPS stock and the reference CPI, against the line Treasury reports, from November 2016 to September 2025.

- Reads: r3 (`results/r3_stock.csv`), t7 (`results/t7_cpi.csv`), t2 (`results/t2_interest_lines.csv`)
- Writes: `/workspace/results/a4_tips_accrual.csv` (csv)
- Format: CSV with the header month,computed_bn,reported_bn,gap_bn and one row per month from 2016-11 to 2025-09 (107 rows). computed_bn is the inflation compensation implied by the stock; reported_bn is the reported TIPS inflation compensation of t2; gap_bn is reported minus computed; billions of dollars rounded to two decimals.

### a8: Maturity wall

Principal maturing by month from October 2025 to December 2030, by class and in total, from the securities outstanding at the end of the window.

- Reads: r3 (`results/r3_stock.csv`), t5 (`results/t5_ledger.json`)
- Writes: `/workspace/results/a8_wall.csv` (csv)
- Format: CSV with the header month,bills_bn,notes_bn,bonds_bn,tips_bn,frn_bn,total_bn and one row per month from 2025-10 to 2030-12 (63 rows): the principal redeemed in the month by class and in total, in billions of dollars rounded to two decimals.

The Treasury-watch distribution list gets the finished tables through `scripts/publish_memo.sh`: do not run it, the think tank's analyst does after review.
