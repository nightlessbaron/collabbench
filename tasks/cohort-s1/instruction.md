# Prognostic cohort (Olmsted County free light chain cohort)

This is stage 1 of a prognostic-cohort study of the Olmsted County free light chain cohort. Read data/flchain.csv and docs/study_definitions.md, and write each deliverable below to its exact path.

## Sources

- **S1**, `data/flchain.csv`: Cohort records: 7,874 people, one row each (columns as in docs/study_definitions.md).
- **S4**, `docs/study_definitions.md`: Study definitions: the published FLC groups and the cause-of-death chapter coding, with this analysis's conventions.
- Also in the workspace, for later steps: S2 (`lifetables/nchs2008_Table01_Intercensal.xlsx`, `lifetables/nchs2008_Table02_Intercensal.xlsx`, `lifetables/nchs2008_Table03_Intercensal.xlsx`), S3 (`standard/stdpop.19ages.txt`).

The team's records are in `docs/notes.md`; read them before you start.

## What to produce

Stage 1 has 12 deliverables, each one file under `/workspace/results/` at the exact path given. A deliverable that reads another one is built from that file's correct content, so mistakes carry downstream. Each file is scored against a reference computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you like, but the deliverables are the files, not a program.

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

### s1: KM by stratum (×18 units, graded separately inside the file)

Survival at 5 and 10 years and restricted mean survival: 8 age-sex strata and 10 FLC deciles.

- Reads: c2 (`results/c2_followup.json`), c3 (`results/c3_flc_exposure.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/s1_km_strata.json` (json)
- Format: JSON object: {"strata": {"50-59/F": {...}, "50-59/M", "60-69/F", ..., "80+/M", "flc_1", ..., "flc_10"}} (18 strata; age band and sex from c4, FLC decile from c3), each {"n": int, "surv_5y": survival fraction at 5 years rounded to 5 decimals, "surv_10y": same at 10 years, "rmst_5y": restricted mean survival time to 5 years in years, "rmst_10y": to 10 years}. Over the analysis cohort.

### m0: Base model

Age and sex only: the reference model for reclassification.

- Reads: c2 (`results/c2_followup.json`), c4 (`results/c4_covariates.json`)
- Writes: `/workspace/results/m0_base_model.json` (json)
- Format: JSON object: {"coef": {"age_per_10y": float, "sex_male": float} (natural-log hazard scale, rounded to 5 decimals), "se": {the same keys, from the observed information}, "partial_loglik": the maximised log partial likelihood rounded to 3 decimals, "counts": {"n": int, "events": int}}. Cox model of death on age_per_10y and sex_male with Breslow ties, on the model cohort (analysis cohort with creatinine recorded).

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

Do not run `scripts/publish.sh`; the user runs it.
