# Notes

The team's records for this work.

## Interest expense lines

- The interest file lists one security under different names in different line groups: Treasury Inflation Protected Securities appear as "Inflation Protected Securities (TIPS)" under accrued interest and as "Treasury Inflation Protected Securities (TIPS)" under amortized discount and amortized premium. They are the same security.
- "Int. Expense Inflation Compensation (TIPS)" is listed in the accrued-interest group, but it is the inflation compensation on TIPS principal, not coupon interest, and Treasury reports it as its own line.
- Amounts are published with their signs: amortized premium is published as a negative amount, so adding the published amounts of a security's lines is the same as subtracting the premium amortization. Treasury bills have no coupon: their interest is amortized discount.
- Interest on the Government Account Series is interest the government pays to its own trust funds and accounts (intragovernmental). The file lists it as a separate expense category from the interest on public issues.
- Lines that belong to none of bills, notes, bonds, TIPS and floating rate notes (savings bonds, domestic, foreign and state and local series, matured debt, and the miscellaneous interest lines) are reported together as other_public. Savings bond and miscellaneous lines are their own interest amounts: they have no accrued, discount or premium split and go in the column other_lines.

## Monthly Treasury Statement

- Each Monthly Treasury Statement report lists the months of its own fiscal year and of the previous fiscal year, one block per year, headed `FY yyyy`; the rows with record_type_cd MTH are the months, named October to September. A month is therefore listed in every report from its own year and from the next year, and the later listings carry the revisions.

## Reference CPI of TIPS

- The reference CPI of a TIPS on a day is the CPI-U (not seasonally adjusted) of the third month before the day's month, moved toward the CPI-U of the second month before it by the share of the month elapsed, (day - 1) divided by the days in the month. The reference CPI of the first of a month is the CPI-U of three months earlier. Treasury publishes it to five decimals.

## Auctions

- A reopening is a further auction of an existing security and carries the CUSIP of its original issue; the file has one line per auction, so the issuance of a CUSIP is the sum over its lines. The amount issued is `awarded_amt`, the total par awarded: it includes the Federal Reserve's add-ons, which sit outside the offering amount. Cash management bills are bills.

## Par yield curve

- Treasury added tenors to the curve during the window and the yearly files differ: the 2-month yield is published from 2018-10-16, the 4-month yield from 2022-10-19 and the 1.5-month (6-week) yield from 2025-02-18, and the column is empty on earlier days. The column headers are `1 Mo`, `2 Mo` and so on, except `1.5 Month`. Dates are month/day/year.

## Debt by security class

- The Monthly Statement of the Public Debt names its classes Bills, Notes, Bonds, Treasury Inflation-Protected Securities, Floating Rate Notes and Federal Financing Bank; the last has no auctions. Amounts are in millions of dollars, total and held by the public (the rest is held by government accounts); TIPS are reported at inflation-adjusted principal.

## Stock rebuild

- A security is outstanding from its issue date until the day it is redeemed. A security maturing on a weekend or a Federal Reserve holiday is redeemed on the next business day, so it is still outstanding at a month-end that falls on its maturity date when that day is not a business day. Federal Reserve holidays are New Year's Day, Martin Luther King Jr. Day, Washington's Birthday, Memorial Day, Juneteenth, Independence Day, Labor Day, Columbus Day, Veterans Day, Thanksgiving and Christmas. A holiday that falls on a Sunday is observed on the Monday; one that falls on a Saturday is not moved to the Friday, because Federal Reserve Banks stay open.
- A TIPS is carried at inflation-adjusted principal: its par times the reference CPI of the day divided by the reference CPI of the TIPS's original dated date (`original_dated_date`, else `dated_date`). Floating rate notes, notes, bonds and bills are carried at par.
- The rebuild uses the auction file only. Treasury's buybacks, which retire securities before maturity, are not in the workspace and are not deducted.

## Reconciliation

- Compare the rebuild with the Monthly Statement of the Public Debt for the five auctioned classes only (bills, notes, bonds, tips, frn): the Federal Financing Bank class has no auctions. The MSPD amounts are in millions of dollars and are the amount outstanding at the month-end, TIPS at inflation-adjusted principal.

## TIPS inflation compensation

- The inflation compensation Treasury reports for a month is the accretion of TIPS principal in that month: the principal outstanding at the previous month-end times the growth of the reference CPI over the month. TIPS issued during the month and the principal of those redeemed are small next to it and are ignored in the check.

## Maturity wall

- A maturity counts in the month of the day the security is redeemed (the next business day when it matures on a weekend or holiday). TIPS are counted at their inflation-adjusted principal as of 2025-09-30, the last reference CPI of the window, since future inflation is not known. Only the securities outstanding at 2025-09-30 mature in the wall: later issuance is not part of it.

## Conventions

- Count by federal fiscal year, October through September, labelled by the year it ends in (2021 is October 2020 to September 2021).
- Only the public-issues category counts; leave out the Government Account Series (intragovernmental).
- Express constant dollars in 2023 dollars: multiply by the CPI-U (all items, not seasonally adjusted) average of fiscal 2023 and divide by the average of the amount's own fiscal year, each average over that year's twelve months.
- Count the inflation compensation on TIPS as interest cost: include that line in the TIPS series and in the total.
- A security's interest is its accrued interest plus its amortized discount plus its amortized premium, summing the published amounts with their signs.
- Use each month's receipts, outlays and deficit as last revised: take them from the most recent statement that lists the month, not the first one published.
- Report dollar amounts in billions of dollars, rounded to two decimals, in every table from the interest bill on (the monthly Treasury source files stay in their own units).
- Implied rates divide by the average of the fiscal year's twelve month-end balances (the `avg_bn` of the denominator table is that average), not by the closing balance.
- Reconciliation: a class-month is flagged when the rebuilt stock differs from the reported stock by more than 0.25 percent of the reported stock; the corrected stock keeps the rebuilt amount where it is not flagged and takes the reported amount where it is.
- Inflation paths: from the September 2025 CPI-U, compound monthly at the trailing twelve-month rate (September 2025 over September 2024) for the base path, and at that rate minus 1.5 and plus 1.5 percentage points for the low and high paths: cpi(k) = cpi(Sep 2025) x (1 + rate)^(k/12) for the k-th month after September 2025.
