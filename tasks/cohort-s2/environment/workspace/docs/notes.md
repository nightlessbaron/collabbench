# Notes

The team's records for this work.

## Records

- flc_group is the grouping used in the original analysis: ten consecutive ranges of kappa+lambda, formed in the original study (about twice the size of this file). In this file the groups are unequal in size (730 to 820 people).
- Three subjects gave their blood sample on their death date, so their followup_days is 0 (ids 31, 54 and 722; samples 1996, 1999, 1999).
- FLC tiers are low = groups 1 to 3, mid = 4 to 7, high = 8 to 10.
- sample_year is the calendar year of the blood sample, 1995 to 2003; the counts by sample year use it.
- There is no status column: a person died if and only if cause_chapter is filled.
- The file has no dates. Enrolment is taken at exact age `age` and at calendar time sample_year + 0.5 (1 July). Attained age is age plus elapsed years; calendar time is sample_year + 0.5 plus elapsed years. Lexis cells are sex x attained 5-year age band (50-54 ... 95-99, then 100 and over) x calendar year, closed on the left; a death belongs to the cell that holds its exit point.
- A year is 365.25 days: time in years is followup_days / 365.25.
- Creatinine is used as recorded: the dataset documentation gives no unit and no conversion is applied. Age per 10 years is age / 10; male is 1 for M.
- Cause of death has four classes: Circulatory, Neoplasms, Respiratory and Other. Other is every other chapter in the file (Mental, Nervous, Digestive, External Causes, Endocrine, Genitourinary, Ill Defined, Infectious, Injury and Poisoning, Musculoskeletal, Blood, Skin, Congenital).
- Survival at a time is the Kaplan-Meier value after the last step at or before it; a death and a censoring at the same time both count as at risk just before it. The restricted mean survival time to a horizon is the area under the same step curve from 0 to the horizon. The horizons are 5 and 10 years.
- Cox models use Breslow's rule for ties (equal followup_days), partial likelihood maximised by Newton-Raphson to convergence, standard errors from the observed information.
- The only life table in the workspace is the US 2008 period life table (NCHS, tables for females and males, single years of age to 100 and over). It is applied to every calendar year of follow-up. The death rate of a 5-year age band is the sum of d(x) over the sum of L(x) across its single years; the band 100 and over uses the open interval, l(100) / T(100).
- Age standardisation uses the US 2000 standard population (SEER, 19 age groups) restricted to the groups the cohort spans: 50-54, 55-59, ..., 80-84 and 85 and over; the weights are each group's share of that total. Attained-age bands 85 and above (85-89 ... 100 and over) are merged into one band.
- Expected survival is Ederer II with intervals of one year of follow-up: in each interval the expected hazard is the expected deaths over the person-years of everyone still under observation in it, taken from the life-table rate of each person's attained-age band and calendar year; survival to k years is exp(minus the sum of the first k interval hazards).
- The excess-hazard model is a Poisson regression on the split cells with the expected deaths of the cell as the offset (the log ratio of observed to expected). Covariates: the band midpoint (lower edge + 2.5) / 10, male, and FLC tier indicators for mid and high (low is the reference).
- Fine-Gray: the risk set at a death from the cause of interest holds everyone with an observation time at or after it, and everyone who died earlier of another cause, the latter with weight G(t-)/G(T-), where G is the Kaplan-Meier curve of the censoring times and G(t-) counts censorings strictly before t. Covariates: age_per_10y, male and the natural log of the c3 flc_sum, on the analysis cohort. Breslow ties.
- The proportional-hazards test is the Grambsch-Therneau test with g(t) = time in years: for each term, chisq = (sum over deaths of (g - mean g) times the scaled Schoenfeld residual)^2 / (d V_kk sum (g - mean g)^2), d the number of deaths, V the variance matrix of the coefficients; one degree of freedom. A term fails when p < 0.01. Time-varying terms use one change point, at 5 years.
- The FLC forms compared are: log (natural log of flc_sum), linear (flc_sum), tier (mid and high indicators), decile (published groups 2 to 10 against group 1), and a restricted cubic spline with three knots at the 10th, 50th and 90th percentiles of flc_sum (linear term plus the one nonlinear term of Harrell's basis). The best form has the lowest AIC (2 df minus 2 log partial likelihood).

## Conventions

- The analysis uses the published FLC groups (flc_group) as distributed.
- Records with zero follow-up are excluded from the analysis cohort; totals still count them.
- The main analysis is complete-case: the model cohort is the analysis cohort with creatinine recorded; inverse-probability weights are used only in the sensitivity reruns.
- Weights for creatinine are 1 / P(recorded) from a logistic regression on age per 10 years, sex, MGUS and sample-year indicators (1995 the reference), fitted on the analysis cohort.
- The 10-year censoring weights: a death by 10 years has 1/G(T-); a person followed past 10 years has 1/G(10-); a person censored before 10 years has 0; G is the Kaplan-Meier curve of the censoring times and G(t-) counts censorings strictly before t.
- Terms of the final model whose proportional-hazards test has p < 0.01 get a separate coefficient before and after 5 years (no stratification); the FLC form is the one with the lowest AIC.
- The shape of the FLC effect is the one with the lowest AIC among log, linear, tier, decile and a three-knot restricted cubic spline.
