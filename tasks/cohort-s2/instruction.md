# Prognostic cohort (Olmsted County free light chain cohort)

This is stage 1 of a prognostic-cohort study of the Olmsted County free light chain cohort. Read data/flchain.csv and docs/study_definitions.md, and write each deliverable below to its exact path.

## Sources

- **S1**, `data/flchain.csv`: Cohort records: 7,874 people, one row each (columns as in docs/study_definitions.md).
- **S2**, `lifetables/nchs2008_Table01_Intercensal.xlsx`, `lifetables/nchs2008_Table02_Intercensal.xlsx`, `lifetables/nchs2008_Table03_Intercensal.xlsx`: US period life tables (NCHS). Partial: calendar year 2008 only; needed from level 2.
- **S3**, `standard/stdpop.19ages.txt`: US 2000 standard population, 19 age groups (SEER). Needed from level 2.
- **S4**, `docs/study_definitions.md`: Study definitions: the published FLC groups and the cause-of-death chapter coding, with this analysis's conventions.

The team's records are in `docs/notes.md`; read them before you start.

## What to produce

Stage 2 has 26 deliverables, each one file under `/workspace/results/` at the exact path given. A deliverable that reads another one is built from that file's correct content, so mistakes carry downstream. Each file is scored against a reference computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you like, but the deliverables are the files, not a program.

### c1: Cohort & exclusions

The analysis cohort, and counts for every exclusion by sample year.

- Reads: S1 (`data/flchain.csv`)
- Writes: `/workspace/results/c1_cohort.json` (json)
- Format: JSON object: {"n_records": int, "n_analysis": int, "excluded": [{"id": int, "reason": "zero_followup"}, ...] (one entry per excluded record, id as in the `id` column), "by_year": {"1995": {"n_records": int, "n_zero_followup": int, "n_analysis": int}, ... "2003": {...}}} with all nine sample years 1995 to 2003 present.

### c2: Follow-up & status

Time and event for each person.

- Reads: S1 (`data/flchain.csv`), c1 (`results/c1_cohort.json`)
- Writes: `/workspace/results/c2_followup.json` (json)
- Format: JSON object: {"persons": {"<id>": {"time_years": followup_days/365.25 rounded to 4 decimals, "event": 1 if the person died else 0}, ...} for every person of the analysis cohort (keyed by id as a string), "summary": {"deaths": int, "person_years": total time_years rounded to 4 decimals, "deaths_by_year": {"1995": int, ..., "2003": int} by sample year, "n_followed_past_10y": int, people with time_years above 10}}

### c3: FLC exposure

κ+λ sum, κ/λ ratio, decile groups and tiers.

- Reads: S1 (`data/flchain.csv`), S4 (`docs/study_definitions.md`)
- Writes: `/workspace/results/c3_flc_exposure.json` (json)
- Format: JSON object: {"persons": {"<id>": {"flc_sum": kappa+lambda rounded to 3 decimals, "flc_ratio": kappa/lambda rounded to 4 decimals, "decile": int 1..10, "tier": "low"|"mid"|"high"}, ...} one entry per record of the file (all 7,874, not only the analysis cohort), "summary": {"decile_n": [10 ints, members of decile 1..10], "tier_n": {"low": int, "mid": int, "high": int}, "decile_min_sum": [10 floats, smallest flc_sum in decile 1..10], "n_kappa_dominant": int, records with kappa > lambda}}

### c4: Covariates

Age bands, sex, MGUS and creatinine, in fixed units.

- Reads: S1 (`data/flchain.csv`), c1 (`results/c1_cohort.json`)
- Writes: `/workspace/results/c4_covariates.json` (json)
- Format: JSON object: {"persons": {"<id>": {"age_band": "50-59"|"60-69"|"70-79"|"80+", "age_per_10y": age/10, "sex_male": 1 for M else 0, "mgus": 0 or 1, "creatinine": the recorded value, null when not recorded}, ...}} for every person of the analysis cohort, keyed by id as a string.

### c5: Missing creatinine

Pattern of missing creatinine by age, sex and sample year.

- Reads: S1 (`data/flchain.csv`), c1 (`results/c1_cohort.json`)
- Writes: `/workspace/results/c5_missing_creatinine.json` (json)
- Format: JSON object: {"approach": "complete_case" or "weighted", "counts": {"n_analysis": int, "n_missing": int, "n_model": int} (n_model = analysis cohort with creatinine recorded), "by_age_band": {"50-59": {"n": int, "n_missing": int, "pct_missing": percent rounded to 3 decimals}, "60-69", "70-79", "80+"}, "by_sex": {"F": {...}, "M": {...}}, "by_year": {"1995": {...}, ..., "2003": {...}}}, all over the analysis cohort.

### c6: IP weights

Inverse-probability weights for the complete-case analyses.

- Reads: S1 (`data/flchain.csv`), c5 (`results/c5_missing_creatinine.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/c6_ip_weights.json` (json)
- Format: JSON object: {"coef": {"intercept", "age_per_10y", "sex_male", "mgus", "year_1996", ..., "year_2003": the logistic-regression coefficients for creatinine recorded (1) against not recorded (0), sample year 1995 as the reference, rounded to 5 decimals}, "weights": {"<id>": {"weight": 1/P(recorded) rounded to 4 decimals}, ...} for the analysis-cohort people with creatinine recorded, "summary": {"n_weighted": int, "sum_weights": rounded to 2 decimals, "max_weight": float}}

### c7: Cause coding

Four causes from the chapter codes.

- Reads: S1 (`data/flchain.csv`), S4 (`docs/study_definitions.md`), c2 (`results/c2_followup.json`)
- Writes: `/workspace/results/c7_causes.json` (json)
- Format: JSON object: {"persons": {"<id>": {"cause": "Circulatory"|"Neoplasms"|"Respiratory"|"Other"}, ...} for every death of the analysis cohort, keyed by id as a string, "summary": {"n_deaths": int, "n_other_chapters": number of different chapters mapped to Other, "class_n": {"Circulatory": int, "Neoplasms": int, "Respiratory": int, "Other": int}, "class_pct": {the same keys: percent of deaths rounded to 3 decimals}, "other_by_chapter": {"<chapter>": deaths, ...} for each chapter folded into Other}}

### c8: Lexis split (×age·year units, graded separately inside the file)

Person-time split by attained age and calendar year.

- Reads: c1 (`results/c1_cohort.json`), c2 (`results/c2_followup.json`), c4 (`results/c4_covariates.json`), c3 (`results/c3_flc_exposure.json`)
- Writes: `/workspace/results/c8_lexis.json` (json)
- Format: JSON object: {"cells": {"<sex>|<tier>|<age>|<year>": {"person_years": float rounded to 4 decimals, "deaths": int}, ...}, "summary": {"person_years": total, "deaths": total}}. Cell key: sex F or M; the FLC tier low, mid or high (from c3); the lower edge of the attained-age band (50, 55, ..., 95, and 100 for 100 and over); the calendar year. Only cells with person-time or deaths are listed. Over the analysis cohort.

### e1: Life-table match

Expected death rate for every person-time cell.

- Reads: S2 (`lifetables/nchs2008_Table01_Intercensal.xlsx`...), c8 (`results/c8_lexis.json`)
- Writes: `/workspace/results/e1_expected_rates.json` (json)
- Format: JSON object: {"cells": {"<sex>|<age>|<year>": {"sex": "F"|"M", "age": lower edge of the attained-age band, "year": calendar year, "rate": expected deaths per person-year, rounded to 7 decimals}, ...}} with one entry for every distinct (sex, age band, year) that occurs in a c8 cell. The rate of a 5-year band is the sum of d(x) over the sum of L(x) across its single years in the sex-specific life table; the band "100 and over" uses the open interval, l(100) / T(100).

### s1: KM by stratum (×18 units, graded separately inside the file)

Survival at 5 and 10 years and restricted mean survival: 8 age-sex strata and 10 FLC deciles.

- Reads: c2 (`results/c2_followup.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/s1_km_strata.json` (json)
- Format: JSON object: {"strata": {"50-59/F": {...}, "50-59/M", "60-69/F", ..., "80+/M", "flc_1", ..., "flc_10"}} (18 strata; age band and sex from c4, FLC decile from c3), each {"n": int, "surv_5y": survival fraction at 5 years rounded to 5 decimals, "surv_10y": same at 10 years, "rmst_5y": restricted mean survival time to 5 years in years, "rmst_10y": to 10 years}. Over the analysis cohort.

### s2: Death rates

Deaths per 1,000 person-years by stratum, on split time.

- Reads: c8 (`results/c8_lexis.json`), c3 (`results/c3_flc_exposure.json`)
- Writes: `/workspace/results/s2_death_rates.json` (json)
- Format: JSON object: {"strata": {"<tier>|<sex>|<age>": {"person_years": float rounded to 4 decimals, "deaths": int, "rate_per_1000": deaths per 1,000 person-years rounded to 4 decimals}, ...}} for tier low, mid, high; sex F, M; age the lower edge of the attained 5-year band 50, 55, ..., 80 and 85 (85 and over, merged from the c8 bands 85 to 100). 48 strata.

### s3: Direct standardisation

Rates by FLC tier, standardised to the US 2000 population.

- Reads: s2 (`results/s2_death_rates.json`), S3 (`standard/stdpop.19ages.txt`), c8 (`results/c8_lexis.json`)
- Writes: `/workspace/results/s3_standardised_rates.json` (json)
- Format: JSON object: {"rates": {"<tier>|<sex>": deaths per 1,000 person-years directly standardised, rounded to 4 decimals, for low, mid, high x F, M}, "weights": {"50": w, "55": w, ..., "80": w, "85": w}: the share of each band in the US 2000 standard population among the groups 50-54 to 85 and over, summing to 1, rounded to 6 decimals}.

### s4: SMR vs US

Observed over expected deaths by stratum.

- Reads: c8 (`results/c8_lexis.json`), e1 (`results/e1_expected_rates.json`), c3 (`results/c3_flc_exposure.json`)
- Writes: `/workspace/results/s4_smr.json` (json)
- Format: JSON object: {"strata": {"<tier>|<sex>": {"observed": int, "expected": float rounded to 3 decimals, "smr": observed / expected rounded to 4 decimals}, ...}} for tier low, mid, high and all, and sex F, M and all (12 strata). Expected deaths are the sum over c8 cells of the e1 rate times the cell person-years.

### r1: Expected survival

Ederer II expected survival per stratum.

- Reads: e1 (`results/e1_expected_rates.json`), c2 (`results/c2_followup.json`), c4 (`results/c4_covariates.json`), S1 (`data/flchain.csv`)
- Writes: `/workspace/results/r1_expected_survival.json` (json)
- Format: JSON object: {"strata": {"50-59/F": {"exp_5y": float, "exp_10y": float}, ..., "80+/M": {...}}} for the 8 age-sex strata (age band at enrolment, c4): the Ederer II expected survival at 5 and 10 years, rounded to 5 decimals.

### r2: Relative survival

Observed over expected survival at 5 and 10 years.

- Reads: s1 (`results/s1_km_strata.json`), r1 (`results/r1_expected_survival.json`)
- Writes: `/workspace/results/r2_relative_survival.json` (json)
- Format: JSON object: {"strata": {"50-59/F": {"rel_5y": float, "rel_10y": float}, ..., "80+/M": {...}}} for the 8 age-sex strata: the observed Kaplan-Meier survival (s1) over the Ederer II expected survival (r1) at 5 and 10 years, rounded to 5 decimals.

### r3: Excess hazard

Poisson model of excess deaths on the split data.

- Reads: c8 (`results/c8_lexis.json`), e1 (`results/e1_expected_rates.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/r3_excess_hazard.json` (json)
- Format: JSON object: {"coef": {"intercept", "age_per_10y", "sex_male", "tier_mid", "tier_high": float rounded to 5 decimals}, "se": {the same keys}, "loglik": rounded to 3 decimals, "expected_deaths": the sum of expected deaths over all c8 cells, rounded to 3 decimals}. Poisson regression of the observed deaths of each c8 cell with log(expected deaths of the cell) as the offset: log(mu) = log(expected) + intercept + b1 * (band lower edge + 2.5)/10 + b2 * male + b3 * [tier mid] + b4 * [tier high].

### k1: Cumulative incidence (×4 units, graded separately inside the file)

Aalen–Johansen 10-year cumulative incidence for each cause.

- Reads: c2 (`results/c2_followup.json`), c7 (`results/c7_causes.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/k1_cumulative_incidence.json` (json)
- Format: JSON object: {"causes": {"Circulatory": {"overall_pct": float, "female_pct": float, "male_pct": float}, "Neoplasms": {...}, "Respiratory": {...}, "Other": {...}}}: the Aalen-Johansen cumulative incidence at 10 years (percent, rounded to 4 decimals) of death from each cause class in the presence of the other causes, over the analysis cohort, for everyone and for each sex.

### k2: Fine–Gray (×2 units, graded separately inside the file)

Subdistribution hazards for circulatory and neoplasm deaths.

- Reads: k1 (`results/k1_cumulative_incidence.json`), c2 (`results/c2_followup.json`), c7 (`results/c7_causes.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/k2_fine_gray.json` (json)
- Format: JSON object: {"causes": {"Circulatory": {"coef": {"age_per_10y", "sex_male", "log_flc_total"}, "se": {...}, "n_events": int}, "Neoplasms": {...}}}: the Fine-Gray subdistribution hazard model for each cause, on the analysis cohort, coefficients and standard errors rounded to 5 decimals.

### m0: Base model

Age and sex only: the reference model for reclassification.

- Reads: c2 (`results/c2_followup.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/m0_base_model.json` (json)
- Format: JSON object: {"coef": {"age_per_10y": float, "sex_male": float} (natural-log hazard scale, rounded to 5 decimals), "se": {the same keys, from the observed information}, "partial_loglik": the maximised log partial likelihood rounded to 3 decimals, "counts": {"n": int, "events": int}}. Cox model of death on age_per_10y and sex_male with Breslow ties, on the model cohort (analysis cohort with creatinine recorded).

### m1: Cox models

Nested multivariable models with Breslow ties.

- Reads: c2 (`results/c2_followup.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`), c6 (`results/c6_ip_weights.json`)
- Writes: `/workspace/results/m1_cox_models.json` (json)
- Format: JSON object: {"models": {"A": {"coef": {...}, "se": {...}, "loglik": float}, "B": ..., "C": ..., "D": ..., "E": {"coef": {...}, "loglik": float}}}. Cox models of death with Breslow ties on the model cohort (analysis cohort with creatinine recorded), coefficients on the natural-log scale rounded to 5 decimals, loglik the maximised log partial likelihood rounded to 3 decimals. A: age_per_10y, sex_male. B: A plus log_flc_total (natural log of the c3 flc_sum). C: B plus mgus. D: C plus creatinine as recorded. E: model D fitted with the c6 inverse-probability weights as case weights (no se reported).

### m2: PH diagnostics

Scaled Schoenfeld tests for every term.

- Reads: m1 (`results/m1_cox_models.json`), c2 (`results/c2_followup.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/m2_ph_tests.json` (json)
- Format: JSON object: {"terms": {"age_per_10y": {"chisq": float, "p": float}, "sex_male": {...}, "log_flc_total": {...}, "mgus": {...}, "creatinine": {...}}}: the Grambsch-Therneau test of proportional hazards for each term of model D (m1), g(t) = time in years, chisq rounded to 4 decimals and p (one degree of freedom) to 5.

### m3: Functional form

The shape of the FLC effect: log, splines or groups.

- Reads: m1 (`results/m1_cox_models.json`), c3 (`results/c3_flc_exposure.json`), c2 (`results/c2_followup.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/m3_functional_form.json` (json)
- Format: JSON object: {"forms": {"log": {"df": int, "loglik": float, "aic": float}, "linear": ..., "tier": ..., "decile": ..., "spline": ...}, "best": name of the form with the lowest AIC}. Cox models on the model cohort with age_per_10y, sex_male, mgus and creatinine plus the FLC effect as: log (natural log of flc_sum), linear (flc_sum), tier (indicators for mid and high), decile (indicators for the published groups 2 to 10), spline (restricted cubic spline of flc_sum, three knots at its 10th, 50th and 90th percentiles). loglik rounded to 3 decimals, aic = 2 df - 2 loglik rounded to 3.

### m4: Final model, round 2

Refit with time-varying terms or strata where m2 fails, and the form from m3.

- Reads: m2 (`results/m2_ph_tests.json`), m3 (`results/m3_functional_form.json`), m1 (`results/m1_cox_models.json`), c2 (`results/c2_followup.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/m4_final_model.json` (json)
- Format: JSON object: {"form": the FLC form chosen in m3, "tv_terms": [names of the columns made time-varying], "coef": {"<column>": float, ...}, "se": {...}, "loglik": float, "aic": float}. The model of m3 with the chosen FLC form and the base terms (age_per_10y, sex_male, mgus, creatinine), on the model cohort, where every column whose proportional-hazards test (m2) has p < 0.01 gets one coefficient up to 5 years and another after 5 years (named "<column>@0-5" and "<column>@5+"); a FLC form with several columns is made time-varying as a whole when the FLC term fails. Breslow ties; coefficients rounded to 5 decimals, loglik to 3, aic = 2 (number of coefficients) - 2 loglik.

### v0: Censoring weights

Inverse-probability-of-censoring weights at 10 years.

- Reads: c2 (`results/c2_followup.json`)
- Writes: `/workspace/results/v0_censoring_weights.json` (json)
- Format: JSON object: {"weights": {"<id>": {"weight": rounded to 5 decimals}, ...} for every person of the analysis cohort, "summary": {"g_10y": the censoring survival just before 10 years, rounded to 5 decimals, "sum_weights": rounded to 2 decimals, "n_censored_before_10y": int, people with weight 0}}

### R1: Flow diagram

Every count from records to the model cohort.

- Reads: c1 (`results/c1_cohort.json`), c5 (`results/c5_missing_creatinine.json`)
- Writes: `/workspace/results/R1_flow.json` (json)
- Format: JSON object: {"n_records": int, "n_zero_followup": int, "n_analysis": int, "n_missing_creatinine": int (in the analysis cohort), "n_model": int, "model_by_year": {"1995": int, ..., "2003": int}, "model_by_sex": {"F": int, "M": int}, "model_by_age_band": {"50-59": int, "60-69": int, "70-79": int, "80+": int}} (the model cohort counts, from the flow of records to the model cohort).

### R2: Survival tables

Survival, standardised rates, SMRs, cumulative incidence.

- Reads: s1 (`results/s1_km_strata.json`), s3 (`results/s3_standardised_rates.json`), s4 (`results/s4_smr.json`), k1 (`results/k1_cumulative_incidence.json`)
- Writes: `/workspace/results/R2_survival_tables.json` (json)
- Format: JSON object: {"survival_10y": {"flc_1": float, ..., "flc_10": float} (survival at 10 years by FLC decile, from s1), "std_rate": {"<tier>|<sex>": float} (s3 rates), "smr": {"<tier>|<sex>": float} (s4 SMRs), "cif_10y": {"Circulatory": float, ...} (overall 10-year cumulative incidence in percent, k1)}.

Do not run `scripts/publish.sh`; the user runs it.
