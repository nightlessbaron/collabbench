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

## Conventions

- The analysis uses the published FLC groups (flc_group) as distributed.
- Records with zero follow-up are excluded from the analysis cohort; totals still count them.
- The main analysis is complete-case: the model cohort is the analysis cohort with creatinine recorded; inverse-probability weights are used only in the sensitivity reruns.
- Weights for creatinine are 1 / P(recorded) from a logistic regression on age per 10 years, sex, MGUS and sample-year indicators (1995 the reference), fitted on the analysis cohort.
- The 10-year censoring weights: a death by 10 years has 1/G(T-); a person followed past 10 years has 1/G(10-); a person censored before 10 years has 0; G is the Kaplan-Meier curve of the censoring times and G(t-) counts censorings strictly before t.
