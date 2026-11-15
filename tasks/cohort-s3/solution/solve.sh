#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
T="$(mktemp -d)"
cat > "$T/graph.json" <<'GRAPH_JSON_EOF'
{
 "graph": "cohort",
 "title": "Prognostic cohort (Olmsted County free light chain cohort)",
 "sources": [
  {
   "id": "S1",
   "files": [
    "data/flchain.csv"
   ],
   "what": "Cohort records: 7,874 people, one row each (columns as in docs/study_definitions.md)."
  },
  {
   "id": "S2",
   "files": [
    "lifetables/nchs2008_Table01_Intercensal.xlsx",
    "lifetables/nchs2008_Table02_Intercensal.xlsx",
    "lifetables/nchs2008_Table03_Intercensal.xlsx"
   ],
   "what": "US period life tables (NCHS). Partial: calendar year 2008 only; needed from level 2.",
   "stage_from": 2
  },
  {
   "id": "S3",
   "files": [
    "standard/stdpop.19ages.txt"
   ],
   "what": "US 2000 standard population, 19 age groups (SEER). Needed from level 2.",
   "stage_from": 2
  },
  {
   "id": "S4",
   "files": [
    "docs/study_definitions.md"
   ],
   "what": "Study definitions: the published FLC groups and the cause-of-death chapter coding, with this analysis's conventions."
  }
 ],
 "nodes": [
  {
   "id": "c1",
   "title": "Cohort & exclusions",
   "level": 1,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1"
   ],
   "what": "The analysis cohort, and counts for every exclusion by sample year.",
   "hard_page": "Records with zero follow-up have no time at risk.",
   "checks": {
    "count": 12,
    "families": [
     {
      "id": "n_records",
      "what": "n_records",
      "count": 1,
      "select": "n_records",
      "tolerance": "exact"
     },
     {
      "id": "n_analysis",
      "what": "n_analysis",
      "count": 1,
      "select": "n_analysis",
      "tolerance": "exact"
     },
     {
      "id": "excluded",
      "what": "set of excluded record ids",
      "count": 1,
      "select": "excluded",
      "tolerance": "set"
     },
     {
      "id": "by_year",
      "what": "per sample year, the (records, zero-follow-up, analysis) row",
      "count": 9,
      "select": "by_year/*",
      "fields": [
       "n_records",
       "n_zero_followup",
       "n_analysis"
      ],
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {
    "A": "Q2 (are the three zero-follow-up records dropped?) is held by the simulated human."
   },
   "output": {
    "path": "results/c1_cohort.json",
    "format": "json",
    "schema": "JSON object: {\"n_records\": int, \"n_analysis\": int, \"excluded\": [{\"id\": int, \"reason\": \"zero_followup\"}, ...] (one entry per excluded record, id as in the `id` column), \"by_year\": {\"1995\": {\"n_records\": int, \"n_zero_followup\": int, \"n_analysis\": int}, ... \"2003\": {...}}} with all nine sample years 1995 to 2003 present."
   },
   "hard": [
    "Records with zero follow-up have no time at risk: three of the 7,874 records have followup_days 0 (ids 31, 54, 722; samples taken on the death date) -> F2, Q2"
   ],
   "facts": [
    "F2",
    "F5",
    "F7"
   ],
   "decisions": [
    "Q2"
   ]
  },
  {
   "id": "c2",
   "title": "Follow-up & status",
   "level": 2,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "c1"
   ],
   "what": "Time and event for each person.",
   "hard_page": "Death is recorded only by whether the cause field is filled. There is no status column.",
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "time_years",
      "what": "time_years, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.0005",
      "fields": [
       "time_years"
      ]
     },
     {
      "id": "event",
      "what": "event, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "event"
      ]
     },
     {
      "id": "deaths",
      "what": "summary.deaths",
      "count": 1,
      "select": "summary/deaths",
      "tolerance": "exact"
     },
     {
      "id": "person_years",
      "what": "summary.person_years",
      "count": 1,
      "select": "summary/person_years",
      "tolerance": "abs 0.5"
     },
     {
      "id": "deaths_by_year",
      "what": "summary.deaths_by_year (fraction of the 9 years)",
      "count": 1,
      "select": "summary/deaths_by_year/*",
      "tolerance": "exact"
     },
     {
      "id": "n_followed_past_10y",
      "what": "summary.n_followed_past_10y",
      "count": 1,
      "select": "summary/n_followed_past_10y",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/c2_followup.json",
    "format": "json",
    "schema": "JSON object: {\"persons\": {\"<id>\": {\"time_years\": followup_days/365.25 rounded to 4 decimals, \"event\": 1 if the person died else 0}, ...} for every person of the analysis cohort (keyed by id as a string), \"summary\": {\"deaths\": int, \"person_years\": total time_years rounded to 4 decimals, \"deaths_by_year\": {\"1995\": int, ..., \"2003\": int} by sample year, \"n_followed_past_10y\": int, people with time_years above 10}}"
   },
   "facts": [
    "F3",
    "F7"
   ],
   "decisions": [],
   "hard": [
    "Death is recorded only by whether the cause field is filled; there is no status column -> F3"
   ]
  },
  {
   "id": "c3",
   "title": "FLC exposure",
   "level": 1,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "S4"
   ],
   "what": "κ+λ sum, κ/λ ratio, decile groups and tiers.",
   "hard_page": "Decision: the published decile groups, or deciles recomputed from these records.",
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "flc_sum",
      "what": "flc_sum, every person (fraction of rows that match)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.0005",
      "fields": [
       "flc_sum"
      ]
     },
     {
      "id": "flc_ratio",
      "what": "flc_ratio, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.00005",
      "fields": [
       "flc_ratio"
      ]
     },
     {
      "id": "decile",
      "what": "decile, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "decile"
      ]
     },
     {
      "id": "tier",
      "what": "tier, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "tier"
      ]
     },
     {
      "id": "decile_n",
      "what": "summary.decile_n (fraction of the 10 entries)",
      "count": 1,
      "select": "summary/decile_n/*",
      "tolerance": "exact"
     },
     {
      "id": "tier_n",
      "what": "summary.tier_n (fraction of the 3 entries)",
      "count": 1,
      "select": "summary/tier_n/*",
      "tolerance": "exact"
     },
     {
      "id": "decile_min_sum",
      "what": "summary.decile_min_sum (fraction of the 10 entries)",
      "count": 1,
      "select": "summary/decile_min_sum/*",
      "tolerance": "abs 0.0005"
     },
     {
      "id": "n_kappa_dominant",
      "what": "summary.n_kappa_dominant",
      "count": 1,
      "select": "summary/n_kappa_dominant",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {
    "P": "F1 and F4 sit in private notes.",
    "A": "Q1 (published groups or recomputed) is held by the simulated human."
   },
   "output": {
    "path": "results/c3_flc_exposure.json",
    "format": "json",
    "schema": "JSON object: {\"persons\": {\"<id>\": {\"flc_sum\": kappa+lambda rounded to 3 decimals, \"flc_ratio\": kappa/lambda rounded to 4 decimals, \"decile\": int 1..10, \"tier\": \"low\"|\"mid\"|\"high\"}, ...} one entry per record of the file (all 7,874, not only the analysis cohort), \"summary\": {\"decile_n\": [10 ints, members of decile 1..10], \"tier_n\": {\"low\": int, \"mid\": int, \"high\": int}, \"decile_min_sum\": [10 floats, smallest flc_sum in decile 1..10], \"n_kappa_dominant\": int, records with kappa > lambda}}"
   },
   "hard": [
    "Decision: the published decile groups or deciles recomputed from these records; the published groups come from a study twice this size, so their sizes here are unequal (730 to 820) -> F1, Q1",
    "Tiers group the deciles 1-3, 4-7, 8-10, not thirds of the people -> F4"
   ],
   "facts": [
    "F1",
    "F4"
   ],
   "decisions": [
    "Q1"
   ]
  },
  {
   "id": "c4",
   "title": "Covariates",
   "level": 2,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "c1"
   ],
   "what": "Age bands, sex, MGUS and creatinine, in fixed units.",
   "hard_page": null,
   "checks": {
    "count": 5,
    "families": [
     {
      "id": "age_band",
      "what": "age_band, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "age_band"
      ]
     },
     {
      "id": "age_per_10y",
      "what": "age_per_10y, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.0005",
      "fields": [
       "age_per_10y"
      ]
     },
     {
      "id": "sex_male",
      "what": "sex_male, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "sex_male"
      ]
     },
     {
      "id": "mgus",
      "what": "mgus, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "mgus"
      ]
     },
     {
      "id": "creatinine",
      "what": "creatinine, every person (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.0005",
      "fields": [
       "creatinine"
      ]
     }
    ]
   },
   "overlays": {
    "P": ""
   },
   "output": {
    "path": "results/c4_covariates.json",
    "format": "json",
    "schema": "JSON object: {\"persons\": {\"<id>\": {\"age_band\": \"50-59\"|\"60-69\"|\"70-79\"|\"80+\", \"age_per_10y\": age/10, \"sex_male\": 1 for M else 0, \"mgus\": 0 or 1, \"creatinine\": the recorded value, null when not recorded}, ...}} for every person of the analysis cohort, keyed by id as a string."
   },
   "facts": [
    "F8"
   ],
   "decisions": [],
   "hard": [
    "Creatinine is blank for 1,350 records and has no unit in the dataset documentation; it is used as recorded -> F8"
   ]
  },
  {
   "id": "c5",
   "title": "Missing creatinine",
   "level": 2,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "c1"
   ],
   "what": "Pattern of missing creatinine by age, sex and sample year.",
   "hard_page": "Decision: complete-case analysis or weighting.",
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "approach",
      "what": "approach",
      "count": 1,
      "select": "approach",
      "tolerance": "exact"
     },
     {
      "id": "counts",
      "what": "counts",
      "count": 1,
      "select": "counts",
      "tolerance": "exact"
     },
     {
      "id": "by_age_band",
      "what": "by_age_band: n and n_missing",
      "count": 1,
      "select": "by_age_band/*",
      "tolerance": "exact",
      "fields": [
       "n",
       "n_missing"
      ]
     },
     {
      "id": "by_sex",
      "what": "by_sex: n and n_missing",
      "count": 1,
      "select": "by_sex/*",
      "tolerance": "exact",
      "fields": [
       "n",
       "n_missing"
      ]
     },
     {
      "id": "by_year",
      "what": "by_year: n and n_missing",
      "count": 1,
      "select": "by_year/*",
      "tolerance": "exact",
      "fields": [
       "n",
       "n_missing"
      ]
     },
     {
      "id": "pct_missing_by_year",
      "what": "by_year pct_missing",
      "count": 1,
      "select": "by_year/*",
      "tolerance": "abs 0.05",
      "fields": [
       "pct_missing"
      ]
     }
    ]
   },
   "overlays": {
    "A": ""
   },
   "output": {
    "path": "results/c5_missing_creatinine.json",
    "format": "json",
    "schema": "JSON object: {\"approach\": \"complete_case\" or \"weighted\", \"counts\": {\"n_analysis\": int, \"n_missing\": int, \"n_model\": int} (n_model = analysis cohort with creatinine recorded), \"by_age_band\": {\"50-59\": {\"n\": int, \"n_missing\": int, \"pct_missing\": percent rounded to 3 decimals}, \"60-69\", \"70-79\", \"80+\"}, \"by_sex\": {\"F\": {...}, \"M\": {...}}, \"by_year\": {\"1995\": {...}, ..., \"2003\": {...}}}, all over the analysis cohort."
   },
   "facts": [
    "F5"
   ],
   "decisions": [
    "Q3"
   ],
   "hard": [
    "Decision: complete-case analysis or weighting; missingness is far from even (2002: 44 of 48 samples, 1996: 13%) -> Q3"
   ]
  },
  {
   "id": "c6",
   "title": "IP weights",
   "level": 3,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "c5",
    "c4"
   ],
   "what": "Inverse-probability weights for the complete-case analyses.",
   "hard_page": null,
   "checks": {
    "count": 5,
    "families": [
     {
      "id": "coef",
      "what": "coef (fraction of the 12 terms)",
      "count": 1,
      "select": "coef/*",
      "tolerance": "abs 0.001"
     },
     {
      "id": "weights",
      "what": "weight, every weighted person (fraction of rows)",
      "count": 1,
      "select": "weights/*",
      "tolerance": "rel 0.1%",
      "fields": [
       "weight"
      ]
     },
     {
      "id": "sum_weights",
      "what": "summary.sum_weights",
      "count": 1,
      "select": "summary/sum_weights",
      "tolerance": "rel 0.1%"
     },
     {
      "id": "max_weight",
      "what": "summary.max_weight",
      "count": 1,
      "select": "summary/max_weight",
      "tolerance": "rel 0.1%"
     },
     {
      "id": "n_weighted",
      "what": "summary.n_weighted",
      "count": 1,
      "select": "summary/n_weighted",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/c6_ip_weights.json",
    "format": "json",
    "schema": "JSON object: {\"coef\": {\"intercept\", \"age_per_10y\", \"sex_male\", \"mgus\", \"year_1996\", ..., \"year_2003\": the logistic-regression coefficients for creatinine recorded (1) against not recorded (0), sample year 1995 as the reference, rounded to 5 decimals}, \"weights\": {\"<id>\": {\"weight\": 1/P(recorded) rounded to 4 decimals}, ...} for the analysis-cohort people with creatinine recorded, \"summary\": {\"n_weighted\": int, \"sum_weights\": rounded to 2 decimals, \"max_weight\": float}}"
   },
   "facts": [],
   "decisions": [
    "Q4"
   ],
   "hard": [
    "The weights depend on a model chosen by the team: covariates, link and solver -> Q4 (the logistic maximum likelihood fit is unique, so any solver that converges gives the same coefficients)"
   ]
  },
  {
   "id": "c7",
   "title": "Cause coding",
   "level": 3,
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "S4",
    "c2"
   ],
   "what": "Four causes from the chapter codes.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "cause",
      "what": "cause, every death (fraction of rows)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "exact",
      "fields": [
       "cause"
      ]
     },
     {
      "id": "n_deaths",
      "what": "summary.n_deaths",
      "count": 1,
      "select": "summary/n_deaths",
      "tolerance": "exact"
     },
     {
      "id": "class_n",
      "what": "summary.class_n",
      "count": 1,
      "select": "summary/class_n/*",
      "tolerance": "exact"
     },
     {
      "id": "class_pct",
      "what": "summary.class_pct",
      "count": 1,
      "select": "summary/class_pct/*",
      "tolerance": "abs 0.05"
     },
     {
      "id": "other_by_chapter",
      "what": "summary.other_by_chapter",
      "count": 1,
      "select": "summary/other_by_chapter/*",
      "tolerance": "exact"
     },
     {
      "id": "n_other_chapters",
      "what": "summary.n_other_chapters",
      "count": 1,
      "select": "summary/n_other_chapters",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {
    "P": "",
    "V": ""
   },
   "output": {
    "path": "results/c7_causes.json",
    "format": "json",
    "schema": "JSON object: {\"persons\": {\"<id>\": {\"cause\": \"Circulatory\"|\"Neoplasms\"|\"Respiratory\"|\"Other\"}, ...} for every death of the analysis cohort, keyed by id as a string, \"summary\": {\"n_deaths\": int, \"n_other_chapters\": number of different chapters mapped to Other, \"class_n\": {\"Circulatory\": int, \"Neoplasms\": int, \"Respiratory\": int, \"Other\": int}, \"class_pct\": {the same keys: percent of deaths rounded to 3 decimals}, \"other_by_chapter\": {\"<chapter>\": deaths, ...} for each chapter folded into Other}}"
   },
   "facts": [
    "F9",
    "F3"
   ],
   "decisions": [],
   "hard": [
    "Thirteen ICD-9 chapter headings are folded into Other (Mental, Nervous, Digestive, External Causes, ...); Ill Defined is one of them -> F9 (S4 section 3)"
   ]
  },
  {
   "id": "c8",
   "title": "Lexis split",
   "level": 3,
   "kind": "work",
   "units": "×age·year",
   "inputs": [
    "c1",
    "c2",
    "c4",
    "c3"
   ],
   "what": "Person-time split by attained age and calendar year.",
   "hard_page": "Rates must use attained age, not age at enrolment. Follow-up spans more than a decade.",
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "cell_person_years",
      "what": "cell person-years (fraction of cells)",
      "count": 4,
      "select": "cells/*",
      "tolerance": "abs 0.01",
      "fields": [
       "person_years"
      ]
     },
     {
      "id": "cell_deaths",
      "what": "cell deaths (fraction of cells)",
      "count": 4,
      "select": "cells/*",
      "tolerance": "exact",
      "fields": [
       "deaths"
      ]
     },
     {
      "id": "total_person_years",
      "what": "summary.person_years",
      "count": 1,
      "select": "summary/person_years",
      "tolerance": "abs 0.5"
     },
     {
      "id": "total_deaths",
      "what": "summary.deaths",
      "count": 1,
      "select": "summary/deaths",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/c8_lexis.json",
    "format": "json",
    "schema": "JSON object: {\"cells\": {\"<sex>|<tier>|<age>|<year>\": {\"person_years\": float rounded to 4 decimals, \"deaths\": int}, ...}, \"summary\": {\"person_years\": total, \"deaths\": total}}. Cell key: sex F or M; the FLC tier low, mid or high (from c3); the lower edge of the attained-age band (50, 55, ..., 95, and 100 for 100 and over); the calendar year. Only cells with person-time or deaths are listed. Over the analysis cohort."
   },
   "facts": [
    "F6",
    "F7"
   ],
   "decisions": [],
   "hard": [
    "Rates must use attained age, not age at enrolment: follow-up reaches 14.3 years, so a person enrolled at 61 is in four age bands -> F6, F7",
    "The file has no dates; the calendar position of enrolment is a convention -> F6"
   ]
  },
  {
   "id": "e1",
   "title": "Life-table match",
   "level": 4,
   "kind": "work",
   "units": null,
   "inputs": [
    "S2",
    "c8"
   ],
   "what": "Expected death rate for every person-time cell.",
   "hard_page": "Life tables close with an open top age interval. The oldest members need it.",
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "rate",
      "what": "rate, every (sex, age, year) cell (fraction of cells)",
      "count": 4,
      "select": "cells/*",
      "tolerance": "rel 0.1%",
      "fields": [
       "rate"
      ]
     },
     {
      "id": "rate_top",
      "what": "rate for the open band 100 and over",
      "count": 2,
      "select": "cells/*",
      "tolerance": "rel 0.1%",
      "fields": [
       "rate"
      ],
      "where": {
       "age": [
        100
       ]
      }
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/e1_expected_rates.json",
    "format": "json",
    "schema": "JSON object: {\"cells\": {\"<sex>|<age>|<year>\": {\"sex\": \"F\"|\"M\", \"age\": lower edge of the attained-age band, \"year\": calendar year, \"rate\": expected deaths per person-year, rounded to 7 decimals}, ...}} with one entry for every distinct (sex, age band, year) that occurs in a c8 cell. The rate of a 5-year band is the sum of d(x) over the sum of L(x) across its single years in the sex-specific life table; the band \"100 and over\" uses the open interval, l(100) / T(100)."
   },
   "facts": [
    "F12",
    "F6"
   ],
   "decisions": [],
   "hard": [
    "Life tables close with an open top age interval ('100 and over', q = 1): its rate has to come from l(100)/T(100), not from a single year of age; the oldest members need it (verified in the table file) -> F12",
    "The only life table in the workspace is the 2008 table; it is applied to every calendar year -> F12"
   ]
  },
  {
   "id": "s1",
   "title": "KM by stratum",
   "level": 3,
   "kind": "work",
   "units": "×18",
   "inputs": [
    "c2",
    "c3",
    "c4"
   ],
   "what": "Survival at 5 and 10 years and restricted mean survival: 8 age-sex strata and 10 FLC deciles.",
   "hard_page": null,
   "checks": {
    "count": 36,
    "families": [
     {
      "id": "surv_5y",
      "what": "surv_5y (fraction of the 18 strata)",
      "count": 9,
      "select": "strata/*",
      "tolerance": "abs 0.005",
      "fields": [
       "surv_5y"
      ]
     },
     {
      "id": "surv_10y",
      "what": "surv_10y",
      "count": 9,
      "select": "strata/*",
      "tolerance": "abs 0.005",
      "fields": [
       "surv_10y"
      ]
     },
     {
      "id": "rmst_5y",
      "what": "rmst_5y",
      "count": 9,
      "select": "strata/*",
      "tolerance": "abs 0.05",
      "fields": [
       "rmst_5y"
      ]
     },
     {
      "id": "rmst_10y",
      "what": "rmst_10y",
      "count": 9,
      "select": "strata/*",
      "tolerance": "abs 0.05",
      "fields": [
       "rmst_10y"
      ]
     }
    ]
   },
   "overlays": {
    "S": ""
   },
   "output": {
    "path": "results/s1_km_strata.json",
    "format": "json",
    "schema": "JSON object: {\"strata\": {\"50-59/F\": {...}, \"50-59/M\", \"60-69/F\", ..., \"80+/M\", \"flc_1\", ..., \"flc_10\"}} (18 strata; age band and sex from c4, FLC decile from c3), each {\"n\": int, \"surv_5y\": survival fraction at 5 years rounded to 5 decimals, \"surv_10y\": same at 10 years, \"rmst_5y\": restricted mean survival time to 5 years in years, \"rmst_10y\": to 10 years}. Over the analysis cohort."
   },
   "facts": [
    "F10",
    "F7"
   ],
   "decisions": [
    "Q1"
   ],
   "hard": [
    "Follow-up is censored, not complete: 5,070 of 7,871 people were followed past 10 years but 1,040 were censored before it, so survival at 10 years cannot be read as the share followed past 10 years or the share not recorded dead -> F10, F3",
    "Strata overlap: every person is in one age-sex stratum and one FLC decile -> Q1"
   ]
  },
  {
   "id": "s2",
   "title": "Death rates",
   "level": 4,
   "kind": "work",
   "units": null,
   "inputs": [
    "c8",
    "c3"
   ],
   "what": "Deaths per 1,000 person-years by stratum, on split time.",
   "hard_page": null,
   "checks": {
    "count": 12,
    "families": [
     {
      "id": "rate",
      "what": "rate_per_1000 (fraction of the 48 strata)",
      "count": 6,
      "select": "strata/*",
      "tolerance": "abs 0.05",
      "fields": [
       "rate_per_1000"
      ]
     },
     {
      "id": "person_years",
      "what": "person_years",
      "count": 3,
      "select": "strata/*",
      "tolerance": "abs 0.5",
      "fields": [
       "person_years"
      ]
     },
     {
      "id": "deaths",
      "what": "deaths",
      "count": 3,
      "select": "strata/*",
      "tolerance": "exact",
      "fields": [
       "deaths"
      ]
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/s2_death_rates.json",
    "format": "json",
    "schema": "JSON object: {\"strata\": {\"<tier>|<sex>|<age>\": {\"person_years\": float rounded to 4 decimals, \"deaths\": int, \"rate_per_1000\": deaths per 1,000 person-years rounded to 4 decimals}, ...}} for tier low, mid, high; sex F, M; age the lower edge of the attained 5-year band 50, 55, ..., 80 and 85 (85 and over, merged from the c8 bands 85 to 100). 48 strata."
   },
   "facts": [
    "F6",
    "F13",
    "F4"
   ],
   "decisions": [],
   "hard": [
    "Rates are on split time: a person contributes person-years to each attained-age band they pass through, not to their enrolment band (a person enrolled at 61 reaches 65 within four years) -> F6",
    "The standard population's top group is 85 and over, so the bands 85 to 100 are merged here -> F13"
   ]
  },
  {
   "id": "s3",
   "title": "Direct standardisation",
   "level": 5,
   "kind": "work",
   "units": null,
   "inputs": [
    "s2",
    "S3",
    "c8"
   ],
   "what": "Rates by FLC tier, standardised to the US 2000 population.",
   "hard_page": "Band-specific rates come from attained-age person-time, not baseline age.",
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "rate",
      "what": "standardised rate (fraction of the 6 tier-sex rates)",
      "count": 6,
      "select": "rates/*",
      "tolerance": "abs 0.3"
     },
     {
      "id": "weights",
      "what": "standard-population weight (fraction of the 8 bands)",
      "count": 2,
      "select": "weights/*",
      "tolerance": "abs 0.0005"
     }
    ]
   },
   "overlays": {
    "P": ""
   },
   "output": {
    "path": "results/s3_standardised_rates.json",
    "format": "json",
    "schema": "JSON object: {\"rates\": {\"<tier>|<sex>\": deaths per 1,000 person-years directly standardised, rounded to 4 decimals, for low, mid, high x F, M}, \"weights\": {\"50\": w, \"55\": w, ..., \"80\": w, \"85\": w}: the share of each band in the US 2000 standard population among the groups 50-54 to 85 and over, summing to 1, rounded to 6 decimals}."
   },
   "facts": [
    "F13"
   ],
   "decisions": [],
   "hard": [
    "Band-specific rates come from attained-age person-time (s2), not baseline age; the standard population's top group is 85 and over, so 85 to 100 is one band -> F13"
   ]
  },
  {
   "id": "s4",
   "title": "SMR vs US",
   "level": 5,
   "kind": "work",
   "units": null,
   "inputs": [
    "c8",
    "e1",
    "c3"
   ],
   "what": "Observed over expected deaths by stratum.",
   "hard_page": null,
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "smr",
      "what": "smr (fraction of the 12 strata)",
      "count": 4,
      "select": "strata/*",
      "tolerance": "rel 0.5%",
      "fields": [
       "smr"
      ]
     },
     {
      "id": "expected",
      "what": "expected deaths",
      "count": 4,
      "select": "strata/*",
      "tolerance": "rel 0.5%",
      "fields": [
       "expected"
      ]
     },
     {
      "id": "observed",
      "what": "observed deaths",
      "count": 2,
      "select": "strata/*",
      "tolerance": "exact",
      "fields": [
       "observed"
      ]
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/s4_smr.json",
    "format": "json",
    "schema": "JSON object: {\"strata\": {\"<tier>|<sex>\": {\"observed\": int, \"expected\": float rounded to 3 decimals, \"smr\": observed / expected rounded to 4 decimals}, ...}} for tier low, mid, high and all, and sex F, M and all (12 strata). Expected deaths are the sum over c8 cells of the e1 rate times the cell person-years."
   },
   "facts": [
    "F12"
   ],
   "decisions": [],
   "hard": [
    "Expected deaths need the life-table rate of each split cell, so a mistake in the life-table match (e1) or the attained-age split (c8) moves every SMR; low-tier people die at 0.65 of the US rate and high-tier at 1.33 -> F12"
   ]
  },
  {
   "id": "r1",
   "title": "Expected survival",
   "level": 5,
   "kind": "work",
   "units": null,
   "inputs": [
    "e1",
    "c2",
    "c4",
    "S1"
   ],
   "what": "Ederer II expected survival per stratum.",
   "hard_page": null,
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "exp_5y",
      "what": "exp_5y (fraction of the 8 strata)",
      "count": 5,
      "select": "strata/*",
      "tolerance": "abs 0.002",
      "fields": [
       "exp_5y"
      ]
     },
     {
      "id": "exp_10y",
      "what": "exp_10y",
      "count": 5,
      "select": "strata/*",
      "tolerance": "abs 0.003",
      "fields": [
       "exp_10y"
      ]
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/r1_expected_survival.json",
    "format": "json",
    "schema": "JSON object: {\"strata\": {\"50-59/F\": {\"exp_5y\": float, \"exp_10y\": float}, ..., \"80+/M\": {...}}} for the 8 age-sex strata (age band at enrolment, c4): the Ederer II expected survival at 5 and 10 years, rounded to 5 decimals."
   },
   "facts": [
    "F14",
    "F6"
   ],
   "decisions": [],
   "hard": [
    "Ederer II keeps people in the expected-survival average only while they are under observation, so the average hazard comes from the follow-up that was actually observed, and the expected rates change with attained age and calendar year inside follow-up -> F14, F6"
   ]
  },
  {
   "id": "r2",
   "title": "Relative survival",
   "level": 6,
   "kind": "work",
   "units": null,
   "inputs": [
    "s1",
    "r1"
   ],
   "what": "Observed over expected survival at 5 and 10 years.",
   "hard_page": null,
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "rel_5y",
      "what": "rel_5y (fraction of the 8 strata)",
      "count": 5,
      "select": "strata/*",
      "tolerance": "abs 0.003",
      "fields": [
       "rel_5y"
      ]
     },
     {
      "id": "rel_10y",
      "what": "rel_10y",
      "count": 5,
      "select": "strata/*",
      "tolerance": "abs 0.005",
      "fields": [
       "rel_10y"
      ]
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/r2_relative_survival.json",
    "format": "json",
    "schema": "JSON object: {\"strata\": {\"50-59/F\": {\"rel_5y\": float, \"rel_10y\": float}, ..., \"80+/M\": {...}}} for the 8 age-sex strata: the observed Kaplan-Meier survival (s1) over the Ederer II expected survival (r1) at 5 and 10 years, rounded to 5 decimals."
   },
   "facts": [
    "F14",
    "F10"
   ],
   "decisions": [],
   "hard": [
    "The ratio inherits both inputs: it is above 1 for the young (the cohort outlives the 2008 life table's average) and falls to 0.83 at 80 and over -> F14"
   ]
  },
  {
   "id": "r3",
   "title": "Excess hazard",
   "level": 5,
   "kind": "work",
   "units": null,
   "inputs": [
    "c8",
    "e1",
    "c3",
    "c4"
   ],
   "what": "Poisson model of excess deaths on the split data.",
   "hard_page": null,
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "coef",
      "what": "coef",
      "count": 4,
      "select": "coef/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "se",
      "what": "se",
      "count": 2,
      "select": "se/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "loglik",
      "what": "loglik",
      "count": 1,
      "select": "loglik",
      "tolerance": "abs 1.0"
     },
     {
      "id": "expected_deaths",
      "what": "expected_deaths",
      "count": 1,
      "select": "expected_deaths",
      "tolerance": "abs 1.0"
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/r3_excess_hazard.json",
    "format": "json",
    "schema": "JSON object: {\"coef\": {\"intercept\", \"age_per_10y\", \"sex_male\", \"tier_mid\", \"tier_high\": float rounded to 5 decimals}, \"se\": {the same keys}, \"loglik\": rounded to 3 decimals, \"expected_deaths\": the sum of expected deaths over all c8 cells, rounded to 3 decimals}. Poisson regression of the observed deaths of each c8 cell with log(expected deaths of the cell) as the offset: log(mu) = log(expected) + intercept + b1 * (band lower edge + 2.5)/10 + b2 * male + b3 * [tier mid] + b4 * [tier high]."
   },
   "facts": [
    "F15",
    "F6"
   ],
   "decisions": [],
   "hard": [
    "The excess-hazard model fitted on split cells, not on people: the additive form (expected + y exp(xb)) has no maximum on this cohort because observed deaths (2,166) fall below the life-table expectation (2,267); the Poisson regression on the observed/expected ratio is used instead -> F15"
   ]
  },
  {
   "id": "k1",
   "title": "Cumulative incidence",
   "level": 4,
   "kind": "work",
   "units": "×4",
   "inputs": [
    "c2",
    "c7",
    "c4"
   ],
   "what": "Aalen–Johansen 10-year cumulative incidence for each cause.",
   "hard_page": "One minus Kaplan–Meier for a single cause overstates it.",
   "checks": {
    "count": 12,
    "families": [
     {
      "id": "overall",
      "what": "overall_pct (fraction of the 4 causes)",
      "count": 4,
      "select": "causes/*",
      "tolerance": "abs 0.05",
      "fields": [
       "overall_pct"
      ]
     },
     {
      "id": "female",
      "what": "female_pct",
      "count": 4,
      "select": "causes/*",
      "tolerance": "abs 0.05",
      "fields": [
       "female_pct"
      ]
     },
     {
      "id": "male",
      "what": "male_pct",
      "count": 4,
      "select": "causes/*",
      "tolerance": "abs 0.05",
      "fields": [
       "male_pct"
      ]
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/k1_cumulative_incidence.json",
    "format": "json",
    "schema": "JSON object: {\"causes\": {\"Circulatory\": {\"overall_pct\": float, \"female_pct\": float, \"male_pct\": float}, \"Neoplasms\": {...}, \"Respiratory\": {...}, \"Other\": {...}}}: the Aalen-Johansen cumulative incidence at 10 years (percent, rounded to 4 decimals) of death from each cause class in the presence of the other causes, over the analysis cohort, for everyone and for each sex."
   },
   "facts": [
    "F10",
    "F9",
    "F3"
   ],
   "decisions": [],
   "hard": [
    "One minus Kaplan-Meier for a single cause overstates it: for Circulatory deaths it gives 8.84% at 10 years, the Aalen-Johansen value is 8.16% (computed on this file) -> F10, F3"
   ]
  },
  {
   "id": "k2",
   "title": "Fine–Gray",
   "level": 5,
   "kind": "work",
   "units": "×2",
   "inputs": [
    "k1",
    "c2",
    "c7",
    "c3",
    "c4"
   ],
   "what": "Subdistribution hazards for circulatory and neoplasm deaths.",
   "hard_page": null,
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "coef",
      "what": "coef (fraction of the 6 coefficients)",
      "count": 4,
      "select": "causes/*/coef/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "se",
      "what": "se",
      "count": 2,
      "select": "causes/*/se/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "n_events",
      "what": "n_events",
      "count": 2,
      "select": "causes/*",
      "tolerance": "exact",
      "fields": [
       "n_events"
      ]
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/k2_fine_gray.json",
    "format": "json",
    "schema": "JSON object: {\"causes\": {\"Circulatory\": {\"coef\": {\"age_per_10y\", \"sex_male\", \"log_flc_total\"}, \"se\": {...}, \"n_events\": int}, \"Neoplasms\": {...}}}: the Fine-Gray subdistribution hazard model for each cause, on the analysis cohort, coefficients and standard errors rounded to 5 decimals."
   },
   "facts": [
    "F16",
    "F9"
   ],
   "decisions": [],
   "hard": [
    "People who died of another cause stay in the risk set with a decaying weight; treating them as censored gives a cause-specific hazard, a different quantity -> F16"
   ]
  },
  {
   "id": "m0",
   "title": "Base model",
   "level": 3,
   "kind": "work",
   "units": null,
   "inputs": [
    "c2",
    "c4"
   ],
   "what": "Age and sex only: the reference model for reclassification.",
   "hard_page": null,
   "checks": {
    "count": 4,
    "families": [
     {
      "id": "coef",
      "what": "coef",
      "count": 1,
      "select": "coef/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "se",
      "what": "se",
      "count": 1,
      "select": "se/*",
      "tolerance": "abs 0.005"
     },
     {
      "id": "partial_loglik",
      "what": "partial_loglik",
      "count": 1,
      "select": "partial_loglik",
      "tolerance": "abs 1.0"
     },
     {
      "id": "counts",
      "what": "counts",
      "count": 1,
      "select": "counts",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/m0_base_model.json",
    "format": "json",
    "schema": "JSON object: {\"coef\": {\"age_per_10y\": float, \"sex_male\": float} (natural-log hazard scale, rounded to 5 decimals), \"se\": {the same keys, from the observed information}, \"partial_loglik\": the maximised log partial likelihood rounded to 3 decimals, \"counts\": {\"n\": int, \"events\": int}}. Cox model of death on age_per_10y and sex_male with Breslow ties, on the model cohort (analysis cohort with creatinine recorded)."
   },
   "facts": [
    "F11",
    "F3"
   ],
   "decisions": [
    "Q3"
   ],
   "hard": [
    "Ties are equal followup_days; Breslow's rule gives each tied death the whole risk set -> F11",
    "The base model sits on the model cohort, not the analysis cohort, so the later reclassification compares models on the same people -> Q3"
   ]
  },
  {
   "id": "m1",
   "title": "Cox models",
   "level": 4,
   "kind": "work",
   "units": null,
   "inputs": [
    "c2",
    "c3",
    "c4",
    "c6"
   ],
   "what": "Nested multivariable models with Breslow ties.",
   "hard_page": null,
   "checks": {
    "count": 12,
    "families": [
     {
      "id": "coef",
      "what": "coef (fraction of the 19 coefficients)",
      "count": 6,
      "select": "models/*/coef/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "se",
      "what": "se (models A to D)",
      "count": 4,
      "select": "models/*/se/*",
      "tolerance": "abs 0.005"
     },
     {
      "id": "loglik",
      "what": "loglik (fraction of the 5 models)",
      "count": 2,
      "select": "models/*",
      "tolerance": "abs 1.0",
      "fields": [
       "loglik"
      ]
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/m1_cox_models.json",
    "format": "json",
    "schema": "JSON object: {\"models\": {\"A\": {\"coef\": {...}, \"se\": {...}, \"loglik\": float}, \"B\": ..., \"C\": ..., \"D\": ..., \"E\": {\"coef\": {...}, \"loglik\": float}}}. Cox models of death with Breslow ties on the model cohort (analysis cohort with creatinine recorded), coefficients on the natural-log scale rounded to 5 decimals, loglik the maximised log partial likelihood rounded to 3 decimals. A: age_per_10y, sex_male. B: A plus log_flc_total (natural log of the c3 flc_sum). C: B plus mgus. D: C plus creatinine as recorded. E: model D fitted with the c6 inverse-probability weights as case weights (no se reported)."
   },
   "facts": [
    "F11"
   ],
   "decisions": [
    "Q3",
    "Q4"
   ],
   "hard": [
    "Nested models share one cohort: the 6,521 people with creatinine recorded, so the likelihoods are comparable (Q3); model D reproduces Inspire's five-covariate model -> Q3, F11",
    "Model E weights the likelihood by 1/P(recorded), so its log-likelihood is on another scale (about -17,880 against -15,429) -> Q4"
   ]
  },
  {
   "id": "m2",
   "title": "PH diagnostics",
   "level": 5,
   "kind": "work",
   "units": null,
   "inputs": [
    "m1",
    "c2",
    "c3",
    "c4"
   ],
   "what": "Scaled Schoenfeld tests for every term.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "chisq",
      "what": "chisq (fraction of the 5 terms)",
      "count": 3,
      "select": "terms/*",
      "tolerance": "rel 2% or abs 0.1",
      "fields": [
       "chisq"
      ]
     },
     {
      "id": "p",
      "what": "p",
      "count": 3,
      "select": "terms/*",
      "tolerance": "abs 0.005",
      "fields": [
       "p"
      ]
     }
    ]
   },
   "overlays": {
    "V": ""
   },
   "output": {
    "path": "results/m2_ph_tests.json",
    "format": "json",
    "schema": "JSON object: {\"terms\": {\"age_per_10y\": {\"chisq\": float, \"p\": float}, \"sex_male\": {...}, \"log_flc_total\": {...}, \"mgus\": {...}, \"creatinine\": {...}}}: the Grambsch-Therneau test of proportional hazards for each term of model D (m1), g(t) = time in years, chisq rounded to 4 decimals and p (one degree of freedom) to 5."
   },
   "facts": [
    "F17",
    "F11"
   ],
   "decisions": [],
   "hard": [
    "Proportional hazards fail for age (chisq 35.5) and for the FLC term (chisq 21.4); sex, MGUS and creatinine pass -> F17"
   ]
  },
  {
   "id": "m3",
   "title": "Functional form",
   "level": 5,
   "kind": "work",
   "units": null,
   "inputs": [
    "m1",
    "c3",
    "c2",
    "c4"
   ],
   "what": "The shape of the FLC effect: log, splines or groups.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "aic",
      "what": "aic (fraction of the 5 forms)",
      "count": 3,
      "select": "forms/*",
      "tolerance": "abs 1.0",
      "fields": [
       "aic"
      ]
     },
     {
      "id": "loglik",
      "what": "loglik",
      "count": 2,
      "select": "forms/*",
      "tolerance": "abs 0.5",
      "fields": [
       "loglik"
      ]
     },
     {
      "id": "best",
      "what": "best",
      "count": 1,
      "select": "best",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/m3_functional_form.json",
    "format": "json",
    "schema": "JSON object: {\"forms\": {\"log\": {\"df\": int, \"loglik\": float, \"aic\": float}, \"linear\": ..., \"tier\": ..., \"decile\": ..., \"spline\": ...}, \"best\": name of the form with the lowest AIC}. Cox models on the model cohort with age_per_10y, sex_male, mgus and creatinine plus the FLC effect as: log (natural log of flc_sum), linear (flc_sum), tier (indicators for mid and high), decile (indicators for the published groups 2 to 10), spline (restricted cubic spline of flc_sum, three knots at its 10th, 50th and 90th percentiles). loglik rounded to 3 decimals, aic = 2 df - 2 loglik rounded to 3."
   },
   "facts": [
    "F18"
   ],
   "decisions": [
    "Q8"
   ],
   "hard": [
    "The shape of the FLC effect is chosen on AIC, which penalises the nine decile terms: the log form wins (AIC 30,867 against 30,883 for the spline and 30,900 for deciles) -> F18, Q8"
   ]
  },
  {
   "id": "m4",
   "title": "Final model, round 2",
   "level": 6,
   "kind": "rework",
   "units": null,
   "inputs": [
    "m2",
    "m3",
    "m1",
    "c2",
    "c3",
    "c4"
   ],
   "what": "Refit with time-varying terms or strata where m2 fails, and the form from m3.",
   "hard_page": "Fixes flow into every later score and table.",
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "form",
      "what": "form",
      "count": 1,
      "select": "form",
      "tolerance": "exact"
     },
     {
      "id": "tv_terms",
      "what": "tv_terms",
      "count": 1,
      "select": "tv_terms",
      "tolerance": "set"
     },
     {
      "id": "coef",
      "what": "coef (fraction of the coefficients)",
      "count": 5,
      "select": "coef/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "se",
      "what": "se",
      "count": 2,
      "select": "se/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "loglik",
      "what": "loglik",
      "count": 1,
      "select": "loglik",
      "tolerance": "abs 1.0"
     }
    ]
   },
   "overlays": {
    "H": ""
   },
   "output": {
    "path": "results/m4_final_model.json",
    "format": "json",
    "schema": "JSON object: {\"form\": the FLC form chosen in m3, \"tv_terms\": [names of the columns made time-varying], \"coef\": {\"<column>\": float, ...}, \"se\": {...}, \"loglik\": float, \"aic\": float}. The model of m3 with the chosen FLC form and the base terms (age_per_10y, sex_male, mgus, creatinine), on the model cohort, where every column whose proportional-hazards test (m2) has p < 0.01 gets one coefficient up to 5 years and another after 5 years (named \"<column>@0-5\" and \"<column>@5+\"); a FLC form with several columns is made time-varying as a whole when the FLC term fails. Breslow ties; coefficients rounded to 5 decimals, loglik to 3, aic = 2 (number of coefficients) - 2 loglik."
   },
   "facts": [
    "F17",
    "F18"
   ],
   "decisions": [
    "Q6"
   ],
   "hard": [
    "Fixes flow into every later score: age and the FLC effect are time-varying (age 0.86 per 10 years in the first five years, 1.11 after; FLC 1.07 then 0.56) -> Q6, F17"
   ]
  },
  {
   "id": "v0",
   "title": "Censoring weights",
   "level": 3,
   "kind": "work",
   "units": null,
   "inputs": [
    "c2"
   ],
   "what": "Inverse-probability-of-censoring weights at 10 years.",
   "hard_page": null,
   "checks": {
    "count": 4,
    "families": [
     {
      "id": "weights",
      "what": "weight, every person (fraction of rows)",
      "count": 1,
      "select": "weights/*",
      "tolerance": "rel 0.1%",
      "fields": [
       "weight"
      ]
     },
     {
      "id": "g_10y",
      "what": "summary.g_10y",
      "count": 1,
      "select": "summary/g_10y",
      "tolerance": "abs 0.001"
     },
     {
      "id": "sum_weights",
      "what": "summary.sum_weights",
      "count": 1,
      "select": "summary/sum_weights",
      "tolerance": "rel 0.1%"
     },
     {
      "id": "n_censored_before_10y",
      "what": "summary.n_censored_before_10y",
      "count": 1,
      "select": "summary/n_censored_before_10y",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/v0_censoring_weights.json",
    "format": "json",
    "schema": "JSON object: {\"weights\": {\"<id>\": {\"weight\": rounded to 5 decimals}, ...} for every person of the analysis cohort, \"summary\": {\"g_10y\": the censoring survival just before 10 years, rounded to 5 decimals, \"sum_weights\": rounded to 2 decimals, \"n_censored_before_10y\": int, people with weight 0}}"
   },
   "facts": [
    "F3",
    "F7"
   ],
   "decisions": [
    "Q5"
   ],
   "hard": [
    "Censoring is the event for G, and a death and a censoring at the same time are not ordered by the data: 1,040 people censored before 10 years get weight 0 and the rest carry their weight -> Q5"
   ]
  },
  {
   "id": "v1",
   "title": "Risk score",
   "level": 7,
   "kind": "work",
   "units": null,
   "inputs": [
    "m4",
    "c2",
    "c3",
    "c4"
   ],
   "what": "Score and 10-year predicted risk for each person.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "lp_early",
      "what": "lp_early (fraction of the 6,521 people)",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.0005",
      "fields": [
       "lp_early"
      ]
     },
     {
      "id": "lp_late",
      "what": "lp_late",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.0005",
      "fields": [
       "lp_late"
      ]
     },
     {
      "id": "risk_10y",
      "what": "risk_10y",
      "count": 1,
      "select": "persons/*",
      "tolerance": "abs 0.001",
      "fields": [
       "risk_10y"
      ]
     },
     {
      "id": "mean_risk",
      "what": "summary.mean_risk_10y",
      "count": 1,
      "select": "summary/mean_risk_10y",
      "tolerance": "abs 0.001"
     },
     {
      "id": "h0_5y",
      "what": "summary.H0_5y",
      "count": 1,
      "select": "summary/H0_5y",
      "tolerance": "rel 1%"
     },
     {
      "id": "h0_10y",
      "what": "summary.H0_10y",
      "count": 1,
      "select": "summary/H0_10y",
      "tolerance": "rel 1%"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/v1_risk_score.json",
    "format": "json",
    "schema": "JSON object: {\"persons\": {\"<id>\": {\"lp_early\": float, \"lp_late\": float, \"risk_10y\": float}, ...} for every person of the model cohort (analysis cohort with creatinine recorded), keyed by id as a string, all rounded to 5 decimals, \"summary\": {\"mean_risk_10y\": float, \"H0_5y\": the Breslow baseline cumulative hazard of the final model at 5 years, \"H0_10y\": at 10 years, both rounded to 9 decimals}}. lp_early and lp_late are the linear predictors with the final model (m4) coefficients before and after 5 years; risk_10y = 1 - exp(-(H0 over the first 5 years x exp(lp_early) + H0 between 5 and 10 years x exp(lp_late)))."
   },
   "facts": [
    "F19",
    "F11"
   ],
   "decisions": [
    "Q6"
   ],
   "hard": [
    "The final model has time-varying terms, so a person has an early and a late linear predictor and the 10-year risk needs the baseline hazard split at 5 years; a score from the plain model would rank people differently (mean 10-year risk 25.4%) -> F19, Q6"
   ]
  },
  {
   "id": "v2",
   "title": "Bootstrap optimism",
   "level": 8,
   "kind": "work",
   "units": "×200",
   "inputs": [
    "v1",
    "c1",
    "m4",
    "c2",
    "c3",
    "c4"
   ],
   "what": "Optimism-corrected performance over fixed resample indices.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "c_boot",
      "what": "c_boot (fraction of the 200 resamples)",
      "count": 2,
      "select": "resamples/*",
      "tolerance": "abs 0.001",
      "fields": [
       "c_boot"
      ]
     },
     {
      "id": "c_test",
      "what": "c_test",
      "count": 2,
      "select": "resamples/*",
      "tolerance": "abs 0.001",
      "fields": [
       "c_test"
      ]
     },
     {
      "id": "apparent",
      "what": "apparent_c",
      "count": 1,
      "select": "apparent_c",
      "tolerance": "abs 0.001"
     },
     {
      "id": "corrected",
      "what": "corrected_c",
      "count": 1,
      "select": "corrected_c",
      "tolerance": "abs 0.001"
     }
    ]
   },
   "overlays": {
    "S": ""
   },
   "output": {
    "path": "results/v2_bootstrap_optimism.json",
    "format": "json",
    "schema": "JSON object: {\"apparent_c\": Harrell C of the final-model 10-year risk on the model cohort, \"resamples\": {\"1\": {\"c_boot\": float, \"c_test\": float}, ..., \"200\": {...}}, \"optimism\": mean over the 200 resamples of (c_boot - c_test), \"corrected_c\": apparent_c - optimism}, all rounded to 5 decimals. Resample b refits the final model structure (m4 form and time-varying terms, with its Breslow baseline) on the resampled people; c_boot is its Harrell C on the resample, c_test its Harrell C on the original model cohort."
   },
   "facts": [
    "F21",
    "F22"
   ],
   "decisions": [],
   "hard": [
    "The resample indices are fixed by the team (a SplitMix64 stream, seed 20261115), so the 200 results are reproducible; optimism is small here (0.0007) because the model has 7 coefficients on 1,959 deaths -> F21"
   ]
  },
  {
   "id": "v3",
   "title": "Calibration",
   "level": 8,
   "kind": "work",
   "units": null,
   "inputs": [
    "v1",
    "v0",
    "c2"
   ],
   "what": "Observed against predicted 10-year risk by decile of risk.",
   "hard_page": "Observed risk ignoring censoring is biased.",
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "mean_pred",
      "what": "mean_pred (fraction of the 10 groups)",
      "count": 3,
      "select": "groups/*",
      "tolerance": "abs 0.002",
      "fields": [
       "mean_pred"
      ]
     },
     {
      "id": "observed",
      "what": "observed",
      "count": 3,
      "select": "groups/*",
      "tolerance": "abs 0.005",
      "fields": [
       "observed"
      ]
     },
     {
      "id": "n",
      "what": "n",
      "count": 1,
      "select": "groups/*",
      "tolerance": "exact",
      "fields": [
       "n"
      ]
     },
     {
      "id": "slope",
      "what": "slope",
      "count": 1,
      "select": "slope",
      "tolerance": "abs 0.02"
     },
     {
      "id": "intercept",
      "what": "intercept",
      "count": 1,
      "select": "intercept",
      "tolerance": "abs 0.02"
     },
     {
      "id": "mae",
      "what": "mean_abs_error",
      "count": 1,
      "select": "mean_abs_error",
      "tolerance": "abs 0.003"
     }
    ]
   },
   "overlays": {
    "I": ""
   },
   "output": {
    "path": "results/v3_calibration.json",
    "format": "json",
    "schema": "JSON object: {\"groups\": {\"1\": {\"n\": int, \"mean_pred\": float, \"observed\": float}, ..., \"10\": {...}}, \"slope\": float, \"intercept\": float, \"mean_abs_error\": float}, rounded to 5 decimals. The model cohort is cut into ten groups of near-equal size by rank of risk_10y (v1); observed is the inverse-probability-of-censoring-weighted share of the group that died by 10 years; slope and intercept come from an OLS fit of cloglog(observed) on cloglog(mean_pred) over the ten groups; mean_abs_error is the mean of |mean_pred - observed|."
   },
   "facts": [
    "F23",
    "F22"
   ],
   "decisions": [
    "Q5"
   ],
   "hard": [
    "Observed risk ignoring censoring is biased: counting everyone alive at the end of follow-up as a survivor gives 24.6% died by 10 years overall (81.0% in the top group) against 25.8% (84.0%) with the censoring weights -> F23, Q5"
   ]
  },
  {
   "id": "v4",
   "title": "Discrimination",
   "level": 8,
   "kind": "work",
   "units": null,
   "inputs": [
    "v1",
    "v0",
    "c2"
   ],
   "what": "Harrell's and Uno's C.",
   "hard_page": null,
   "checks": {
    "count": 4,
    "families": [
     {
      "id": "harrell_c",
      "what": "harrell_c",
      "count": 1,
      "select": "harrell_c",
      "tolerance": "abs 0.001"
     },
     {
      "id": "harrell_pairs",
      "what": "harrell_pairs",
      "count": 1,
      "select": "harrell_pairs",
      "tolerance": "exact"
     },
     {
      "id": "uno_c",
      "what": "uno_c",
      "count": 1,
      "select": "uno_c",
      "tolerance": "abs 0.001"
     },
     {
      "id": "uno_weight",
      "what": "uno_weight",
      "count": 1,
      "select": "uno_weight",
      "tolerance": "rel 0.1%"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/v4_discrimination.json",
    "format": "json",
    "schema": "JSON object: {\"harrell_c\": float, \"harrell_pairs\": int, comparable pairs, \"uno_c\": float, \"uno_weight\": float, the denominator weight, rounded to 2 decimals}: concordance of risk_10y (v1) on the model cohort; Harrell: all comparable pairs; Uno: pairs whose earlier death is before 10 years, each weighted by (v0 weight of that death) squared. C values rounded to 5 decimals."
   },
   "facts": [
    "F22"
   ],
   "decisions": [],
   "hard": [
    "Ties: a pair is comparable only when the earlier time is a death and strictly earlier; tied risks count one half (10,050,896 comparable pairs on this cohort) -> F22"
   ]
  },
  {
   "id": "v7",
   "title": "Recalibrated score",
   "level": 9,
   "kind": "rework",
   "units": null,
   "inputs": [
    "v3",
    "v1"
   ],
   "what": "Score recalibrated where v3 shows a systematic slope.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "risk",
      "what": "risk_10y (fraction of the 6,521 people)",
      "count": 3,
      "select": "persons/*",
      "tolerance": "abs 0.001",
      "fields": [
       "risk_10y"
      ]
     },
     {
      "id": "recal",
      "what": "recal",
      "count": 2,
      "select": "recal/*",
      "tolerance": "abs 0.02"
     },
     {
      "id": "mean",
      "what": "summary.mean_risk_10y",
      "count": 1,
      "select": "summary/mean_risk_10y",
      "tolerance": "abs 0.001"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/v7_recalibrated.json",
    "format": "json",
    "schema": "JSON object: {\"persons\": {\"<id>\": {\"risk_10y\": float}, ...} for the model cohort, \"recal\": {\"intercept\": float, \"slope\": float} (from v3), \"summary\": {\"mean_risk_10y\": float}}: the recalibrated 10-year risk 1 - exp(-exp(intercept + slope x cloglog(risk_10y))), rounded to 5 decimals."
   },
   "facts": [
    "F23"
   ],
   "decisions": [
    "Q10"
   ],
   "hard": [
    "The calibration slope is 0.957: only a mild shrinkage (the model is close to calibrated in this cohort), so the recalibration moves mean risk from 25.4% to 25.7% -> Q10"
   ]
  },
  {
   "id": "v5",
   "title": "Reclassification",
   "level": 10,
   "kind": "work",
   "units": null,
   "inputs": [
    "v7",
    "m0",
    "c2",
    "c4",
    "c3",
    "v0"
   ],
   "what": "Net reclassification against the base model.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "nri",
      "what": "nri",
      "count": 3,
      "select": "nri/*",
      "tolerance": "abs 0.005"
     },
     {
      "id": "moves",
      "what": "moves",
      "count": 3,
      "select": "moves/*",
      "tolerance": "abs 0.005"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/v5_reclassification.json",
    "format": "json",
    "schema": "JSON object: {\"nri\": {\"events\": float, \"nonevents\": float, \"total\": float}, \"moves\": {\"up_events\": float, \"down_events\": float, \"up_nonevents\": float, \"down_nonevents\": float}}, rounded to 5 decimals. Categories of 10-year risk: below 10%, 10% to below 25%, 25% and above. The base risk comes from the m0 model with its coefficients fixed and a Breslow baseline on the model cohort; the new risk is v7. Events: people who died by 10 years; non-events: people followed past 10 years; each counted with its v0 weight. up/down: the share moving to a higher/lower category."
   },
   "facts": [
    "F24",
    "F23"
   ],
   "decisions": [
    "Q7"
   ],
   "hard": [
    "Net reclassification with censoring: only deaths by 10 years and people followed past 10 years can be classed, each with its censoring weight; the people censored before 10 years carry none -> F24, Q7"
   ]
  },
  {
   "id": "v6",
   "title": "Net benefit",
   "level": 10,
   "kind": "work",
   "units": null,
   "inputs": [
    "v7",
    "v0",
    "c2"
   ],
   "what": "Decision curves at fixed thresholds.",
   "hard_page": null,
   "checks": {
    "count": 6,
    "families": [
     {
      "id": "model",
      "what": "model",
      "count": 3,
      "select": "model/*",
      "tolerance": "abs 0.003"
     },
     {
      "id": "treat_all",
      "what": "treat_all",
      "count": 3,
      "select": "treat_all/*",
      "tolerance": "abs 0.003"
     }
    ]
   },
   "overlays": {
    "A": ""
   },
   "output": {
    "path": "results/v6_net_benefit.json",
    "format": "json",
    "schema": "JSON object: {\"model\": {\"0.10\": float, \"0.20\": float, \"0.30\": float}, \"treat_all\": {\"0.10\": float, ...}, \"prevalence_10y\": float}, rounded to 5 decimals: the net benefit of treating everyone with v7 risk_10y at or above the threshold, TP/n - FP/n x t/(1-t), and of treating everyone, with TP the weighted deaths by 10 years above the threshold and FP the weighted people followed past 10 years above it."
   },
   "facts": [
    "F25"
   ],
   "decisions": [
    "Q11"
   ],
   "hard": [
    "Thresholds are the team's: 10%, 20% and 30%; at 30% treating everyone has negative net benefit (-0.061) while the model keeps +0.119 -> F25, Q11"
   ]
  },
  {
   "id": "z1",
   "title": "Sensitivity reruns",
   "level": 7,
   "kind": "work",
   "units": "×5",
   "inputs": [
    "m4",
    "c6",
    "k2",
    "c3",
    "c2",
    "c4",
    "c7"
   ],
   "what": "The final model rerun five ways: complete-case vs weighted; dropping the first two years; dropping MGUS; tiers instead of deciles; competing-risks version.",
   "hard_page": null,
   "checks": {
    "count": 15,
    "families": [
     {
      "id": "n",
      "what": "n",
      "count": 3,
      "select": "runs/*",
      "tolerance": "exact",
      "fields": [
       "n"
      ]
     },
     {
      "id": "events",
      "what": "events",
      "count": 3,
      "select": "runs/*",
      "tolerance": "exact",
      "fields": [
       "events"
      ]
     },
     {
      "id": "coef",
      "what": "coef (fraction of all coefficients)",
      "count": 6,
      "select": "runs/*/coef/*",
      "tolerance": "abs 0.02"
     },
     {
      "id": "hr",
      "what": "hr_p90_p10",
      "count": 3,
      "select": "runs/*/hr_p90_p10/*",
      "tolerance": "rel 2%"
     }
    ]
   },
   "overlays": {
    "S": "",
    "A": ""
   },
   "output": {
    "path": "results/z1_sensitivity.json",
    "format": "json",
    "schema": "JSON object: {\"runs\": {\"main\": R, \"weighted\": R, \"drop_first_2y\": R, \"drop_mgus\": R, \"tiers\": R, \"competing\": R}} where R = {\"n\": persons, \"events\": deaths (of the cause analysed), \"coef\": {\"<column>\": float rounded to 5 decimals, ...}, \"hr_p90_p10\": {\"early\": float, \"late\": float}} (the hazard ratio of the 90th against the 10th percentile of flc_sum, before and after 5 years, rounded to 4 decimals). main is the final model (m4); the reruns change one thing each: weighted (c6 weights as case weights), drop_first_2y (deaths and time before 2 years removed, clock not reset), drop_mgus (people with MGUS and the MGUS term removed), tiers (FLC as tier indicators), competing (Fine-Gray subdistribution hazard of circulatory death, no time-varying terms)."
   },
   "facts": [
    "F20",
    "F16"
   ],
   "decisions": [
    "Q9"
   ],
   "hard": [
    "The headline FLC effect changes with the rerun: 2.89 at 5 years in the main model, 2.25 when the first two years are dropped and 1.56 for the competing-risks version (an early effect that is partly early death) -> F20, Q9"
   ]
  },
  {
   "id": "R1",
   "title": "Flow diagram",
   "level": 3,
   "kind": "deliv",
   "units": null,
   "inputs": [
    "c1",
    "c5"
   ],
   "what": "Every count from records to the model cohort.",
   "hard_page": null,
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "n_records",
      "what": "n_records",
      "count": 1,
      "select": "n_records",
      "tolerance": "exact"
     },
     {
      "id": "n_zero_followup",
      "what": "n_zero_followup",
      "count": 1,
      "select": "n_zero_followup",
      "tolerance": "exact"
     },
     {
      "id": "n_analysis",
      "what": "n_analysis",
      "count": 1,
      "select": "n_analysis",
      "tolerance": "exact"
     },
     {
      "id": "n_missing_creatinine",
      "what": "n_missing_creatinine",
      "count": 1,
      "select": "n_missing_creatinine",
      "tolerance": "exact"
     },
     {
      "id": "n_model",
      "what": "n_model",
      "count": 1,
      "select": "n_model",
      "tolerance": "exact"
     },
     {
      "id": "model_by_year",
      "what": "model_by_year",
      "count": 1,
      "select": "model_by_year/*",
      "tolerance": "exact"
     },
     {
      "id": "model_by_sex",
      "what": "model_by_sex",
      "count": 1,
      "select": "model_by_sex/*",
      "tolerance": "exact"
     },
     {
      "id": "model_by_age_band",
      "what": "model_by_age_band",
      "count": 1,
      "select": "model_by_age_band/*",
      "tolerance": "exact"
     }
    ]
   },
   "overlays": {
    "V": ""
   },
   "output": {
    "path": "results/R1_flow.json",
    "format": "json",
    "schema": "JSON object: {\"n_records\": int, \"n_zero_followup\": int, \"n_analysis\": int, \"n_missing_creatinine\": int (in the analysis cohort), \"n_model\": int, \"model_by_year\": {\"1995\": int, ..., \"2003\": int}, \"model_by_sex\": {\"F\": int, \"M\": int}, \"model_by_age_band\": {\"50-59\": int, \"60-69\": int, \"70-79\": int, \"80+\": int}} (the model cohort counts, from the flow of records to the model cohort)."
   },
   "facts": [
    "F5"
   ],
   "decisions": [
    "Q2",
    "Q3"
   ],
   "hard": [
    "Every count must agree with c1 and c5: a different cohort rule upstream changes the whole diagram -> Q2, Q3"
   ]
  },
  {
   "id": "R2",
   "title": "Survival tables",
   "level": 6,
   "kind": "deliv",
   "units": null,
   "inputs": [
    "s1",
    "s3",
    "s4",
    "k1"
   ],
   "what": "Survival, standardised rates, SMRs, cumulative incidence.",
   "hard_page": null,
   "checks": {
    "count": 12,
    "families": [
     {
      "id": "survival_10y",
      "what": "survival_10y (fraction of the 10 deciles)",
      "count": 4,
      "select": "survival_10y/*",
      "tolerance": "abs 0.005"
     },
     {
      "id": "std_rate",
      "what": "std_rate",
      "count": 3,
      "select": "std_rate/*",
      "tolerance": "abs 0.3"
     },
     {
      "id": "smr",
      "what": "smr",
      "count": 3,
      "select": "smr/*",
      "tolerance": "rel 0.5%"
     },
     {
      "id": "cif_10y",
      "what": "cif_10y",
      "count": 2,
      "select": "cif_10y/*",
      "tolerance": "abs 0.05"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/R2_survival_tables.json",
    "format": "json",
    "schema": "JSON object: {\"survival_10y\": {\"flc_1\": float, ..., \"flc_10\": float} (survival at 10 years by FLC decile, from s1), \"std_rate\": {\"<tier>|<sex>\": float} (s3 rates), \"smr\": {\"<tier>|<sex>\": float} (s4 SMRs), \"cif_10y\": {\"Circulatory\": float, ...} (overall 10-year cumulative incidence in percent, k1)}."
   },
   "facts": [
    "F10"
   ],
   "decisions": [
    "Q1"
   ],
   "hard": [
    "Each headline number must agree with its source node: the table is assembled, not recomputed -> Q1, F10"
   ]
  },
  {
   "id": "R3",
   "title": "Relative survival",
   "level": 7,
   "kind": "deliv",
   "units": null,
   "inputs": [
    "r2",
    "r3"
   ],
   "what": "Relative survival and the excess-hazard model.",
   "hard_page": null,
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "rel10",
      "what": "relative_survival_10y",
      "count": 4,
      "select": "relative_survival_10y/*",
      "tolerance": "abs 0.005"
     },
     {
      "id": "excess",
      "what": "excess_ratio",
      "count": 4,
      "select": "excess_ratio/*",
      "tolerance": "rel 2%"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/R3_relative_survival.json",
    "format": "json",
    "schema": "JSON object: {\"relative_survival_10y\": {\"50-59/F\": float, ..., \"80+/M\": float} (from r2), \"excess_ratio\": {\"age_per_10y\": float, \"sex_male\": float, \"tier_mid\": float, \"tier_high\": float}: exp of the r3 coefficients, rounded to 4 decimals}."
   },
   "facts": [
    "F15",
    "F14"
   ],
   "decisions": [],
   "hard": [
    "Assembled from r2 and r3: the excess-ratio model is on the observed/expected ratio (high tier 2.05 against low), not an additive excess hazard -> F15"
   ]
  },
  {
   "id": "R4",
   "title": "Model & validation",
   "level": 11,
   "kind": "deliv",
   "units": null,
   "inputs": [
    "m4",
    "v2",
    "v4",
    "v5",
    "v6"
   ],
   "what": "Final model, optimism, discrimination, reclassification, net benefit.",
   "hard_page": null,
   "checks": {
    "count": 14,
    "families": [
     {
      "id": "model",
      "what": "model coef",
      "count": 4,
      "select": "model/*",
      "tolerance": "abs 0.01"
     },
     {
      "id": "optimism",
      "what": "optimism",
      "count": 2,
      "select": "optimism/*",
      "tolerance": "abs 0.001"
     },
     {
      "id": "discrimination",
      "what": "discrimination",
      "count": 2,
      "select": "discrimination/*",
      "tolerance": "abs 0.001"
     },
     {
      "id": "reclass",
      "what": "reclassification",
      "count": 3,
      "select": "reclassification/*",
      "tolerance": "abs 0.005"
     },
     {
      "id": "nb",
      "what": "net_benefit",
      "count": 3,
      "select": "net_benefit/*",
      "tolerance": "abs 0.003"
     }
    ]
   },
   "overlays": {
    "H": ""
   },
   "output": {
    "path": "results/R4_model_validation.json",
    "format": "json",
    "schema": "JSON object: {\"model\": {\"<column>\": float} (m4 coefficients), \"optimism\": {\"apparent_c\": float, \"corrected_c\": float} (v2), \"discrimination\": {\"harrell_c\": float, \"uno_c\": float} (v4), \"reclassification\": {\"events\": float, \"nonevents\": float, \"total\": float} (v5 nri), \"net_benefit\": {\"0.10\": float, \"0.20\": float, \"0.30\": float} (v6 model)}."
   },
   "facts": [
    "F21"
   ],
   "decisions": [
    "Q6"
   ],
   "hard": [
    "Assembled from m4, v2, v4, v5 and v6: a wrong final model changes every number in it -> Q6"
   ]
  },
  {
   "id": "R5",
   "title": "Sensitivity table",
   "level": 8,
   "kind": "deliv",
   "units": null,
   "inputs": [
    "z1"
   ],
   "what": "The five reruns against the main estimate.",
   "hard_page": null,
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "hr_early",
      "what": "hr_early (fraction of the 5 reruns)",
      "count": 3,
      "select": "reruns/*",
      "tolerance": "rel 2%",
      "fields": [
       "hr_early"
      ]
     },
     {
      "id": "hr_late",
      "what": "hr_late",
      "count": 3,
      "select": "reruns/*",
      "tolerance": "rel 2%",
      "fields": [
       "hr_late"
      ]
     },
     {
      "id": "main",
      "what": "main",
      "count": 1,
      "select": "main",
      "tolerance": "rel 2%"
     },
     {
      "id": "max",
      "what": "max_abs_log_ratio",
      "count": 1,
      "select": "max_abs_log_ratio",
      "tolerance": "abs 0.03"
     }
    ]
   },
   "overlays": {},
   "output": {
    "path": "results/R5_sensitivity_table.json",
    "format": "json",
    "schema": "JSON object: {\"main\": {\"hr_early\": float, \"hr_late\": float}, \"reruns\": {\"weighted\": {\"hr_early\": float, \"hr_late\": float}, \"drop_first_2y\": ..., \"drop_mgus\": ..., \"tiers\": ..., \"competing\": ...}, \"max_abs_log_ratio\": the largest |log(rerun / main)| over the five reruns and both periods, rounded to 4 decimals}: the z1 hazard ratios (90th against 10th percentile of flc_sum)."
   },
   "facts": [
    "F20"
   ],
   "decisions": [],
   "hard": [
    "The reruns move the early FLC effect much more than the late one (largest change 0.62 on the log scale, the competing-risks version at 5 years) -> F20"
   ]
  }
 ],
 "facts": [
  {
   "id": "F1",
   "text": "flc_group is the grouping used in the original analysis: ten consecutive ranges of kappa+lambda, formed in the original study (about twice the size of this file). In this file the groups are unequal in size (730 to 820 people).",
   "source": "S4 section 2; flchain help page"
  },
  {
   "id": "F2",
   "text": "Three subjects gave their blood sample on their death date, so their followup_days is 0 (ids 31, 54 and 722; samples 1996, 1999, 1999).",
   "source": "flchain help page (futime); S4 section 1"
  },
  {
   "id": "F4",
   "text": "FLC tiers are low = groups 1 to 3, mid = 4 to 7, high = 8 to 10.",
   "source": "S4 section 3 (convention of this analysis)"
  },
  {
   "id": "F5",
   "text": "sample_year is the calendar year of the blood sample, 1995 to 2003; the counts by sample year use it.",
   "source": "flchain help page (sample.yr); S4 section 1"
  },
  {
   "id": "F3",
   "text": "There is no status column: a person died if and only if cause_chapter is filled.",
   "source": "S4 section 1; flchain help page (chapter)"
  },
  {
   "id": "F6",
   "text": "The file has no dates. Enrolment is taken at exact age `age` and at calendar time sample_year + 0.5 (1 July). Attained age is age plus elapsed years; calendar time is sample_year + 0.5 plus elapsed years. Lexis cells are sex x attained 5-year age band (50-54 ... 95-99, then 100 and over) x calendar year, closed on the left; a death belongs to the cell that holds its exit point.",
   "source": "study office convention (the data carry no dates)"
  },
  {
   "id": "F7",
   "text": "A year is 365.25 days: time in years is followup_days / 365.25.",
   "source": "study office convention"
  },
  {
   "id": "F8",
   "text": "Creatinine is used as recorded: the dataset documentation gives no unit and no conversion is applied. Age per 10 years is age / 10; male is 1 for M.",
   "source": "flchain help page (creatinine); study office convention"
  },
  {
   "id": "F9",
   "text": "Cause of death has four classes: Circulatory, Neoplasms, Respiratory and Other. Other is every other chapter in the file (Mental, Nervous, Digestive, External Causes, Endocrine, Genitourinary, Ill Defined, Infectious, Injury and Poisoning, Musculoskeletal, Blood, Skin, Congenital).",
   "source": "S4 section 3"
  },
  {
   "id": "F10",
   "text": "Survival at a time is the Kaplan-Meier value after the last step at or before it; a death and a censoring at the same time both count as at risk just before it. The restricted mean survival time to a horizon is the area under the same step curve from 0 to the horizon. The horizons are 5 and 10 years.",
   "source": "study office convention"
  },
  {
   "id": "F11",
   "text": "Cox models use Breslow's rule for ties (equal followup_days), partial likelihood maximised by Newton-Raphson to convergence, standard errors from the observed information.",
   "source": "study office convention"
  },
  {
   "id": "F12",
   "text": "The only life table in the workspace is the US 2008 period life table (NCHS, tables for females and males, single years of age to 100 and over). It is applied to every calendar year of follow-up. The death rate of a 5-year age band is the sum of d(x) over the sum of L(x) across its single years; the band 100 and over uses the open interval, l(100) / T(100).",
   "source": "S2 (lifetables/); study office convention"
  },
  {
   "id": "F13",
   "text": "Age standardisation uses the US 2000 standard population (SEER, 19 age groups) restricted to the groups the cohort spans: 50-54, 55-59, ..., 80-84 and 85 and over; the weights are each group's share of that total. Attained-age bands 85 and above (85-89 ... 100 and over) are merged into one band.",
   "source": "S3; study office convention"
  },
  {
   "id": "F14",
   "text": "Expected survival is Ederer II with intervals of one year of follow-up: in each interval the expected hazard is the expected deaths over the person-years of everyone still under observation in it, taken from the life-table rate of each person's attained-age band and calendar year; survival to k years is exp(minus the sum of the first k interval hazards).",
   "source": "study office convention"
  },
  {
   "id": "F15",
   "text": "The excess-hazard model is a Poisson regression on the split cells with the expected deaths of the cell as the offset (the log ratio of observed to expected). Covariates: the band midpoint (lower edge + 2.5) / 10, male, and FLC tier indicators for mid and high (low is the reference).",
   "source": "study office convention"
  },
  {
   "id": "F16",
   "text": "Fine-Gray: the risk set at a death from the cause of interest holds everyone with an observation time at or after it, and everyone who died earlier of another cause, the latter with weight G(t-)/G(T-), where G is the Kaplan-Meier curve of the censoring times and G(t-) counts censorings strictly before t. Covariates: age_per_10y, male and the natural log of the c3 flc_sum, on the analysis cohort. Breslow ties.",
   "source": "study office convention"
  },
  {
   "id": "F17",
   "text": "The proportional-hazards test is the Grambsch-Therneau test with g(t) = time in years: for each term, chisq = (sum over deaths of (g - mean g) times the scaled Schoenfeld residual)^2 / (d V_kk sum (g - mean g)^2), d the number of deaths, V the variance matrix of the coefficients; one degree of freedom. A term fails when p < 0.01. Time-varying terms use one change point, at 5 years.",
   "source": "study office convention"
  },
  {
   "id": "F18",
   "text": "The FLC forms compared are: log (natural log of flc_sum), linear (flc_sum), tier (mid and high indicators), decile (published groups 2 to 10 against group 1), and a restricted cubic spline with three knots at the 10th, 50th and 90th percentiles of flc_sum (linear term plus the one nonlinear term of Harrell's basis). The best form has the lowest AIC (2 df minus 2 log partial likelihood).",
   "source": "study office convention"
  },
  {
   "id": "F19",
   "text": "The final-model risk score: for each person of the model cohort lp_early and lp_late are the linear predictors using the m4 coefficients for the period before and after 5 years (a column that is not time-varying has one coefficient in both). The baseline cumulative hazard is the Breslow estimate from the final-model fit; the 10-year risk is 1 - exp(-(H0(0,5] exp(lp_early) + H0(5,10] exp(lp_late))).",
   "source": "study office convention"
  },
  {
   "id": "F20",
   "text": "The five sensitivity reruns of the final model are: weighted (the c6 weights as case weights); drop_first_2y (everyone enters at 2 years: deaths and time before 2 years are removed, people with time up to 2 years leave, the clock is not reset); drop_mgus (people with MGUS removed, MGUS term dropped); tiers (the FLC form is the tier indicators, time-varying as the main model's FLC term is); competing (Fine-Gray subdistribution hazard of circulatory death on the model cohort with the main model's terms and no time-varying terms). The headline FLC effect of a run is the hazard ratio between the 90th and the 10th percentile of flc_sum (model cohort, type 7 quantiles), before and after 5 years; for the tier form it is the high tier against the low tier.",
   "source": "study office convention"
  },
  {
   "id": "F21",
   "text": "Bootstrap resamples are fixed: the model cohort sorted by id ascending is indexed from 0; resample b of 200 takes n draws, each the next 64-bit output of the SplitMix64 stream (seed 20261115, one stream for all resamples, state += 0x9E3779B97F4A7C15, z = (z xor z>>30) x 0xBF58476D1CE4E5B9, z = (z xor z>>27) x 0x94D049BB133111EB, output z xor z>>31, all mod 2^64) modulo n. Optimism is the mean over resamples of C on the resample minus C on the original data.",
   "source": "study office convention"
  },
  {
   "id": "F22",
   "text": "Harrell's C: over pairs with the earlier time a death and strictly earlier than the other time, the share in which the earlier death has the higher 10-year risk; a tie in risk counts one half. Uno's C (truncated at 10 years): the same over pairs whose earlier death is before 10 years, each pair weighted by the v0 weight of that death squared, numerator and denominator.",
   "source": "study office convention"
  },
  {
   "id": "F23",
   "text": "Calibration groups are the model cohort ranked by 10-year risk (ties by id) and cut into ten groups of near-equal size (group = floor(10 x rank / n) + 1, rank from 0). Observed risk of a group is the sum of the v0 weights of the people who died by 10 years over the group size. The calibration line is an OLS fit of the complementary log-log of observed risk on that of mean predicted risk over the ten groups; the recalibration applies it: risk' = 1 - exp(-exp(intercept + slope x cloglog(risk))).",
   "source": "study office convention"
  },
  {
   "id": "F24",
   "text": "Risk categories for reclassification are below 10%, 10% to below 25%, and 25% or more. The base risk is the 10-year risk of the age-and-sex model (m0) with its coefficients fixed and a Breslow baseline hazard fitted on the model cohort. Events are people who died by 10 years, non-events people followed past 10 years; each person counts with the v0 weight. NRI = (up - down among events) + (down - up among non-events).",
   "source": "study office convention"
  },
  {
   "id": "F25",
   "text": "Net benefit at threshold t is TP/n - FP/n x t/(1-t), where n is the size of the model cohort, TP the sum of v0 weights of people who died by 10 years with risk at or above t, and FP the sum of v0 weights of people followed past 10 years with risk at or above t. Treating everyone has net benefit prevalence - (1 - prevalence) x t/(1-t), prevalence the weighted share who died by 10 years.",
   "source": "study office convention"
  }
 ],
 "decisions": [
  {
   "id": "Q1",
   "question": "Which FLC decile groups does the analysis report: the published flc_group column, or deciles recomputed from the 7,874 records?",
   "answer": "The published groups (flc_group as distributed), so the tables compare with the original analysis.",
   "plausible_default": "Recompute deciles from the records in hand (cost if the default is taken: 209 of 7,874 people, 2.7%, change decile and 79 change tier).",
   "source": "study office decision, 2026-11-15 (recorded for this graph)",
   "convention": "The analysis uses the published FLC groups (flc_group) as distributed."
  },
  {
   "id": "Q2",
   "question": "Are the three records with zero follow-up kept in the analysis cohort?",
   "answer": "No. They have no time at risk and are excluded from the analysis cohort; the records stay counted in the total.",
   "plausible_default": "Keep all 7,874 records.",
   "source": "study office decision, 2026-11-15 (same convention as the Inspire flchain task)",
   "convention": "Records with zero follow-up are excluded from the analysis cohort; totals still count them."
  },
  {
   "id": "Q3",
   "question": "Missing creatinine: is the main analysis complete-case (people with creatinine recorded) or weighted for the missing?",
   "answer": "Complete-case is the main analysis: the model cohort is the analysis cohort with creatinine recorded. Weighting is used only in the sensitivity reruns.",
   "plausible_default": "Weight everyone (inverse-probability weights) in the main analysis.",
   "source": "study office decision, 2026-11-15",
   "convention": "The main analysis is complete-case: the model cohort is the analysis cohort with creatinine recorded; inverse-probability weights are used only in the sensitivity reruns."
  },
  {
   "id": "Q4",
   "question": "Which model gives the inverse-probability weights?",
   "answer": "A logistic regression of creatinine recorded (1) against not recorded (0) on age per 10 years, sex (male = 1), MGUS and sample-year indicators (1995 the reference), fitted on the analysis cohort. A person with creatinine recorded has weight 1 / P(recorded); a person without has none.",
   "plausible_default": "Include FLC sum or follow-up in the model, or stabilise the weights.",
   "source": "study office decision, 2026-11-15",
   "convention": "Weights for creatinine are 1 / P(recorded) from a logistic regression on age per 10 years, sex, MGUS and sample-year indicators (1995 the reference), fitted on the analysis cohort."
  },
  {
   "id": "Q5",
   "question": "How are the 10-year censoring weights defined?",
   "answer": "The Kaplan-Meier curve G of the censoring times (a censoring is the event, a death at the same time is still at risk). A person who died by 10 years has weight 1/G(T-) at their own time T; a person followed past 10 years has 1/G(10-); a person censored before 10 years has weight 0. G(t-) uses censorings strictly before t.",
   "plausible_default": "Weight by G(T) including censorings at the death time, or truncate the weights.",
   "source": "study office decision, 2026-11-15",
   "convention": "The 10-year censoring weights: a death by 10 years has 1/G(T-); a person followed past 10 years has 1/G(10-); a person censored before 10 years has 0; G is the Kaplan-Meier curve of the censoring times and G(t-) counts censorings strictly before t."
  },
  {
   "id": "Q6",
   "question": "Which terms of the final model are time-varying?",
   "answer": "Every column whose proportional-hazards test has p < 0.01 gets a separate coefficient before and after 5 years; no stratification. The FLC form is the one with the lowest AIC (m3).",
   "plausible_default": "Stratify on the failing terms, or leave the model as fitted.",
   "source": "study office decision, 2026-11-15",
   "convention": "Terms of the final model whose proportional-hazards test has p < 0.01 get a separate coefficient before and after 5 years (no stratification); the FLC form is the one with the lowest AIC."
  },
  {
   "id": "Q7",
   "question": "Into which risk categories is reclassification judged?",
   "answer": "Three categories: below 10%, 10% to below 25%, 25% or more.",
   "plausible_default": "Two categories at a single threshold.",
   "source": "study office decision, 2026-11-15",
   "convention": "Reclassification is judged in three 10-year risk categories: below 10%, 10% to below 25%, 25% or more."
  },
  {
   "id": "Q8",
   "question": "How is the shape of the FLC effect chosen?",
   "answer": "By AIC among five forms: log, linear, tier, decile and a three-knot spline.",
   "plausible_default": "Choose the form by the likelihood-ratio test, or keep the log form.",
   "source": "study office decision, 2026-11-15",
   "convention": "The shape of the FLC effect is the one with the lowest AIC among log, linear, tier, decile and a three-knot restricted cubic spline."
  },
  {
   "id": "Q9",
   "question": "Which five sensitivity reruns?",
   "answer": "Weighted instead of complete-case, dropping the first two years, dropping MGUS, tiers instead of the continuous form, and a competing-risks (Fine-Gray, circulatory death) version.",
   "plausible_default": "Rerun with other covariate sets.",
   "source": "study office decision, 2026-11-15",
   "convention": "The sensitivity reruns are: weighted, dropping the first two years, dropping MGUS, tiers, and competing risks (Fine-Gray for circulatory death)."
  },
  {
   "id": "Q10",
   "question": "How is the score recalibrated?",
   "answer": "On the complementary log-log scale with the intercept and slope of the OLS fit over the ten calibration groups.",
   "plausible_default": "Refit the model on the whole cohort, or a logistic recalibration.",
   "source": "study office decision, 2026-11-15",
   "convention": "The recalibrated risk is 1 - exp(-exp(intercept + slope x cloglog(risk))), with intercept and slope from the calibration fit over the ten risk groups."
  },
  {
   "id": "Q11",
   "question": "At which thresholds is net benefit reported?",
   "answer": "10%, 20% and 30% 10-year risk.",
   "plausible_default": "A range of thresholds from 5% to 50%.",
   "source": "study office decision, 2026-11-15",
   "convention": "Net benefit is reported at the thresholds 10%, 20% and 30% of 10-year risk."
  }
 ],
 "intro": "This is stage 1 of a prognostic-cohort study of the Olmsted County free light chain cohort. Read data/flchain.csv and docs/study_definitions.md, and write each deliverable below to its exact path.",
 "stages": [
  [
   1,
   3
  ],
  [
   4,
   6
  ],
  [
   7,
   9
  ],
  [
   10,
   11
  ]
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
python3 -I "$T/run.py" "$W" "$W" --stage 3
