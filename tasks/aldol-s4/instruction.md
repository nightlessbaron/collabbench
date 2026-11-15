# Enzyme aldol process: raw HPLC data to a process decision

A research group studied the enzymatic aldol synthesis of L-phenylserine from glycine and benzaldehyde with the enzyme L-threonine aldolase, in five reactor arrangements, and published every HPLC peak area as an open data set. `data/injections.csv` holds the raw peak areas of 79 experiments (649 injections), `data/experiments.csv` the conditions the lab's result files state for each experiment, and `docs/` the lab's own records and reporting protocol. Nothing in the data files has been converted: the deliverables below rebuild the study's quantities step by step.

## Sources

- **S1**, `data/injections.csv`: Every HPLC injection of the study, one row per injection: exp, sample (0 is the first injection of an experiment), t_h (hours since the start, as the lab's files give it), pa_anti and pa_syn (peak areas of L-anti- and L-syn-phenylserine, instrument units). Raw: nothing is converted to a concentration.
- **S2**, `data/experiments.csv`: The conditions each experiment's file states, one row per experiment: exp, series (which of the lab's result files the experiment is from), temp_c, gly_m (mol/L), dmso_pct (vol.%), flow_ul_min (microlitres per minute). Blank where the files do not state it.
- **S3**, `docs/lab_files.md`: The lab's own records: calibration, sample preparation, run sheet, instrument and materials.
- **S4**, `docs/reporting_protocol.md`: The group's rules for blanks, yields, ratios, end points, outliers, rates and fits.

The team's records are in `docs/notes.md`; read them before you start.

## What to produce

Stage 4 has 30 deliverables, each one file under `/workspace/results/` at the exact path given. A deliverable that reads another one is built from that file's correct content, so mistakes carry downstream. Each file is scored against a reference computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you like, but the deliverables are the files, not a program.

### k1: Experiment registry

79 experiments in five process modes: two-phase batch (12), membrane (39), one-phase batch (3), flow (21), recycle (4). Each has its sampling plan.

- Reads: S1 (`data/injections.csv`), S2 (`data/experiments.csv`), S3 (`docs/lab_files.md`)
- Writes: `/workspace/results/k1_registry.csv` (csv)
- Format: CSV with the header exp,mode,temp_c,gly_m,dmso_pct,flow_ul_min,n_samples,final_t_h and one row per experiment (79 rows). mode is one of batch2p (two-phase batch), membrane, batch1p (one-phase batch), flow, recycle. temp_c (deg C), gly_m (initial glycine, mol/L), dmso_pct (vol.%) and flow_ul_min (microlitres per minute) are the experiment's conditions, left empty where the experiment has none; n_samples is its number of injections and final_t_h the hours of its last injection.

### k2: Calibration

Which calibration converts each injection, and how.

- Reads: S3 (`docs/lab_files.md`)
- Writes: `/workspace/results/k2_calibration.csv` (csv)
- Format: CSV with the header exp,sample,anti_slope,anti_offset,syn_slope,syn_offset and one row per injection of injections.csv (649 rows). The calibration line that converts the injection's anti peak is PA = anti_slope x c + anti_offset, and the line for its syn peak PA = syn_slope x c + syn_offset, with c the injected concentration in mmol/L.

### k3: Dilution map

A dilution factor for every one of the 649 injections.

- Reads: S1 (`data/injections.csv`), S3 (`docs/lab_files.md`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/k3_dilution.csv` (csv)
- Format: CSV with the header exp,sample,dilution and one row per injection of injections.csv (649 rows). dilution is the factor by which the injected sample was diluted relative to the reaction mixture (1 = injected neat). Leave it empty for sample 0, the first injection of each experiment.

### k4: Time base

Hours since the start for every sample.

- Reads: S1 (`data/injections.csv`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/k4_timebase.csv` (csv)
- Format: CSV with the header exp,sample,t_true_h and one row per injection (649 rows): the true hours since the start of the experiment at which the sample was taken.

### k5: Concentrations (×649 units, graded separately inside the file)

anti and syn concentration in mmol/L for every injection.

- Reads: k2 (`results/k2_calibration.csv`), k3 (`results/k3_dilution.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/k5_concentrations.csv` (csv)
- Format: CSV with the header exp,sample,c_anti,c_syn and one row per injection (649 rows): the concentration of L-anti- and L-syn-phenylserine in the reaction mixture, in mmol/L.

### k6: Outlier screen

An accepted or rejected flag per sample.

- Reads: S1 (`data/injections.csv`), S4 (`docs/reporting_protocol.md`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/k6_outliers.csv` (csv)
- Format: CSV with the header exp,sample,accepted and one row per injection (649 rows): 1 when the sample is accepted, 0 when it is rejected as a sampling failure.

### b1: Batch end points (×12 units, graded separately inside the file)

Yield and syn/anti ratio at the end point of each two-phase batch run.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), S4 (`docs/reporting_protocol.md`), k1 (`results/k1_registry.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/b1_batch_endpoints.csv` (csv)
- Format: CSV with the header exp,end_sample,end_t_h,yield_pct,ratio and one row per two-phase batch (batch2p) experiment (12 rows): the sample index and the hours of the experiment's end point, the yield there in percent of the initial glycine, and the diastereomer ratio syn/anti (dimensionless).

### b2: Batch rates (×12 units, graded separately inside the file)

Initial rate and first-order rate constant for each two-phase batch run.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), k4 (`results/k4_timebase.csv`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/b2_batch_rates.csv` (csv)
- Format: CSV with the header exp,fitted,initial_rate,c_inf,k and one row per two-phase batch (batch2p) experiment (12 rows). fitted is 1 when the experiment gets a rate and a fit, else 0 (then leave the other columns empty). initial_rate is in mmol/L per hour, c_inf in mmol/L and k in 1/h, for the total (anti + syn) concentration.

### m1: Membrane end points (×39 units, graded separately inside the file)

Yield and ratio at the end point of each membrane run.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), S4 (`docs/reporting_protocol.md`), k1 (`results/k1_registry.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/m1_membrane_endpoints.csv` (csv)
- Format: CSV with the header exp,end_sample,end_t_h,yield_pct,ratio and one row per membrane experiment (39 rows): the sample index and the hours of the experiment's end point, the yield there in percent of the initial glycine, and the diastereomer ratio syn/anti (dimensionless).

### m2: Membrane rates (×39 units, graded separately inside the file)

Initial rate and rate constant for each membrane run.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), k4 (`results/k4_timebase.csv`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/m2_membrane_rates.csv` (csv)
- Format: CSV with the header exp,fitted,initial_rate,c_inf,k and one row per membrane experiment (39 rows). fitted is 1 when the experiment gets a rate and a fit, else 0 (then leave the other columns empty). initial_rate is in mmol/L per hour, c_inf in mmol/L and k in 1/h, for the total (anti + syn) concentration.

### p1: One-phase batch (×3 units, graded separately inside the file)

Yield against time on the corrected 10-minute grid, by glycine level.

- Reads: k5 (`results/k5_concentrations.csv`), k4 (`results/k4_timebase.csv`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/p1_onephase.json` (json)
- Format: JSON object {"curve": {"<exp>|<sample>": {"t_h": hours, "yield_pct": percent}}, "initial_rate": {"<exp>": mmol/L per hour}} for the three one-phase batch runs. The curve has an entry for every sample except sample 0 that the lab keeps; initial_rate is the initial rate of the total (anti + syn) concentration.

### f1: Residence time (×21 units, graded separately inside the file)

Residence time of each flow run.

- Reads: S2 (`data/experiments.csv`), S3 (`docs/lab_files.md`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/f1_residence.csv` (csv)
- Format: CSV with the header exp,residence_h and one row per flow experiment (21 rows): the residence time in the membrane module, in hours.

### f2: Steady state (×21 units, graded separately inside the file)

Steady-state concentrations of each flow run.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), k1 (`results/k1_registry.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/f2_steady_state.csv` (csv)
- Format: CSV with the header exp,c_anti,c_syn,yield_pct,ratio and one row per flow experiment (21 rows): the steady-state concentrations (mmol/L), the yield (percent of the initial glycine) and the syn/anti ratio.

### f3: Conversion vs τ

Conversion as a function of residence time, fitted across flow runs.

- Reads: f1 (`results/f1_residence.csv`), f2 (`results/f2_steady_state.csv`)
- Writes: `/workspace/results/f3_conversion.json` (json)
- Format: JSON object {"mean_conversion": {"<residence time in hours, 4 decimals>": mean conversion (a fraction) of the flow runs at that residence time}, "fit": {"x_inf": plateau conversion, "k_per_h": rate constant in 1/h, "rmse": root-mean-square error of the fit over the runs}, "n_runs": number of flow runs}. The fit is conversion = x_inf (1 - exp(-k tau)) by least squares over all runs, conversion being the steady-state yield as a fraction.

### r1: Recycle passes (×4 units, graded separately inside the file)

Per-pass and cumulative yield of each recycle run.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), k1 (`results/k1_registry.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/r1_recycle.csv` (csv)
- Format: CSV with the header exp,sample,t_true_h,cumulative_yield_pct,pass_yield_pct,end_point and one row per recycle sample except sample 0 (17 rows). cumulative_yield_pct is the yield in percent of the initial glycine at that sample; pass_yield_pct is its increase over the previous sample of the run (the first sample's increase is its whole yield); end_point is 1 on the sample that is the run's end point, else 0.

### x1: Mode pairing

Batch and membrane runs matched on temperature, DMSO and glycine, with the difference per pair.

- Reads: b1 (`results/b1_batch_endpoints.csv`), m1 (`results/m1_membrane_endpoints.csv`), S2 (`data/experiments.csv`)
- Writes: `/workspace/results/x1_mode_pairing.json` (json)
- Format: JSON object {"pairs": {"<temp_c>|<gly_m>|<dmso_pct>": {"batch_yield_pct": ..., "membrane_yield_pct": ..., "difference_pct": membrane minus batch, "n_batch": number of batch runs at those conditions, "n_membrane": number of membrane runs at those conditions}}, "n_pairs": number of pairs}, one pair per condition set (written like 20|1|25, numbers without trailing zeros) that has both a two-phase batch and a membrane run.

### x2: Arrhenius

Activation energy from rate constants at 20, 30 and 40 °C.

- Reads: b2 (`results/b2_batch_rates.csv`), m2 (`results/m2_membrane_rates.csv`), S2 (`data/experiments.csv`)
- Writes: `/workspace/results/x2_arrhenius.json` (json)
- Format: JSON object {"membrane": {"k_mean_by_temp": {"20": ..., "30": ..., "40": ...} (mean k in 1/h over the lab's reference group at that temperature), "ea_kj_mol": activation energy, "group_size": {"20": ..., "30": ..., "40": ...} (experiments in the group at each temperature)}, "batch": {"k_by_temp": {"20": ..., "30": ..., "40": ...} (k of the two-phase batch run at that temperature with the same glycine and DMSO as the group), "ea_kj_mol": activation energy}}.

### x3: Response surface

Yield and rate as quadratic functions of temperature, DMSO and glycine, three levels each.

- Reads: b1 (`results/b1_batch_endpoints.csv`), b2 (`results/b2_batch_rates.csv`), m1 (`results/m1_membrane_endpoints.csv`), m2 (`results/m2_membrane_rates.csv`), S2 (`data/experiments.csv`)
- Writes: `/workspace/results/x3_response_surface.json` (json)
- Format: JSON object {"yield": {"coef": {...}, "r2": ..., "n": ...}, "rate": {"coef": {...}, "r2": ..., "n": ...}}: ordinary least squares of the end-point yield (percent; every two-phase batch and membrane experiment) and of the initial rate (mmol/L per hour; the experiments with a rate) on intercept, temp_c, dmso_pct, gly_m, their three squares (temp_c2, dmso_pct2, gly_m2) and membrane (1 for a membrane run, 0 for a batch run). coef has those eight names as keys, r2 is the coefficient of determination and n the number of experiments used.

### x4: Kinetic model

One mechanistic model fitted jointly to every batch and membrane time course.

- Reads: k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), k4 (`results/k4_timebase.csv`), x2 (`results/x2_arrhenius.json`)
- Writes: `/workspace/results/x4_kinetic_model.json` (json)
- Format: JSON object {"mechanism": "reversible", "ea_fixed_kj_mol": ..., "params": {"batch2p": {"kf30", "k2", "dmso_exp"}, "membrane": {...}}, "sse": {"batch2p", "membrane", "total"}, "rmse": sqrt(total sse / total points), "n_points": {"batch2p", "membrane"}}. mechanism is the mechanism you fitted: one of irreversible, reversible, decay. The model: p(t) = kf G0 / (kf + k2) (1 - exp(-(kf + k2) t)) for the total phenylserine concentration p (mmol/L), G0 = 1000 x the glycine concentration in mol/L, kf = kf30 exp(-Ea/R (1/T - 1/303.15)) exp(dmso_exp (DMSO - 25)/25) with T in kelvin, DMSO in vol.%, R = 8.314 J/(mol K) and Ea the membrane activation energy of x2, held fixed; kf30 (1/h), k2 (1/h) and dmso_exp are fitted separately for the two modes batch2p and membrane, by least squares on every accepted, non-blank sample of every two-phase batch and membrane experiment.

### x5: Residual review

The runs whose residuals in x4 are systematic, each with its cause traced upstream.

- Reads: x4 (`results/x4_kinetic_model.json`), k3 (`results/k3_dilution.csv`), k6 (`results/k6_outliers.csv`), k5 (`results/k5_concentrations.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/x5_residual_review.csv` (csv)
- Format: CSV with the header exp,systematic,mean_residual,best_cut,accepted and one row per two-phase batch and membrane experiment (51 rows), reviewing the fit of x4. Residual = measured minus modelled total concentration over the experiment's accepted non-blank samples. systematic is 1 when the absolute mean residual exceeds half the fit's rmse, else 0. For a systematic run only: mean_residual (mmol/L); best_cut, the largest fractional reduction of the run's sum of squared residuals (model parameters held fixed) achievable by ONE correction to one sample, either restoring a rejected sample or changing its dilution factor to one of 1, 2, 5 or 10 (concentration rescaled by new/old); accepted is 1 when that correction cuts the run's sum of squares by at least 75 % AND leaves the run non-systematic, else 0. Leave mean_residual and best_cut empty for runs that are not systematic.

### x6: Refit, round 2

x4 refitted after the corrections from x5.

- Reads: x5 (`results/x5_residual_review.csv`), x4 (`results/x4_kinetic_model.json`), k5 (`results/k5_concentrations.csv`), k3 (`results/k3_dilution.csv`), k4 (`results/k4_timebase.csv`), k6 (`results/k6_outliers.csv`)
- Writes: `/workspace/results/x6_refit.json` (json)
- Format: The same JSON object as x4 plus "corrections_applied" (the number of corrections x5 accepted, applied before refitting: a restored sample counts, and a changed dilution rescales that sample's concentration), for the refit of the same model after those corrections.

### x7: Identifiability

Which kinetic parameters the data actually pin down, with profile intervals.

- Reads: x6 (`results/x6_refit.json`), k5 (`results/k5_concentrations.csv`), k6 (`results/k6_outliers.csv`), k4 (`results/k4_timebase.csv`)
- Writes: `/workspace/results/x7_identifiability.json` (json)
- Format: JSON object {"batch2p": {"kf30": {"lo", "hi", "identifiable"}, "k2": {...}, "dmso_exp": {...}}, "membrane": {...}}: the 95 % profile interval of each parameter of the refit (x6). For one parameter fixed at a trial value, the other two of that mode are re-optimised; the interval is the set of trial values whose sum of squares stays below SSE_mode x (1 + 3.84 / (n_mode - 3)). Search at most 6 e-folds from the estimate for kf30 and k2 (24 units for dmso_exp); a bound not found is null and identifiable is 0, else 1.

### y1: Flow from batch

Flow conversion predicted from the batch model and residence time, against the measurements.

- Reads: x6 (`results/x6_refit.json`), f3 (`results/f3_conversion.json`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/y1_flow_from_batch.json` (json)
- Format: JSON object {"assumed": {"temp_c", "dmso_pct"}, "by_tau": {"<residence time in hours, 4 decimals>": {"predicted", "measured", "ratio"}}, "rmse"}: the conversion (a fraction of the initial glycine) that the refitted membrane model (x6) predicts after the residence time of the flow runs (a plug-flow reactor with the flow runs' glycine), at the temperature and DMSO content assumed for the flow runs, against the measured mean conversion of f3; ratio = predicted / measured; rmse over the residence times.

### y2: Productivity

Space-time yield for each process mode.

- Reads: b1 (`results/b1_batch_endpoints.csv`), m1 (`results/m1_membrane_endpoints.csv`), f2 (`results/f2_steady_state.csv`), f1 (`results/f1_residence.csv`), r1 (`results/r1_recycle.csv`), p1 (`results/p1_onephase.json`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/y2_productivity.json` (json)
- Format: JSON object {"sty": {"<mode>": {"mean": ..., "max": ...}}} for the five modes batch2p, membrane, batch1p, flow, recycle: the space-time yield in mmol/L per hour of the mode's runs (the end-point, or steady-state, total concentration divided by the hours it took; for flow the residence time), mean and maximum over the mode's runs.

### z1: Operating window

Conditions that maximise yield within the selectivity and time limits.

- Reads: x3 (`results/x3_response_surface.json`), x6 (`results/x6_refit.json`), x7 (`results/x7_identifiability.json`)
- Writes: `/workspace/results/z1_operating_window.json` (json)
- Format: JSON object {"optimum": {"temp_c", "dmso_pct", "gly_m"}, "yield_pct", "rate_at_optimum", "model_yield_6h_pct", "window_points", "kinetic_parameters_identifiable", "unconstrained": {"dmso_pct_vertex", "inside_range"}}. The optimum is the membrane-run conditions of the highest end-point yield on x3's yield surface inside the tested range (the lowest to the highest level of temperature, DMSO and glycine in the conditions file) and, since yields are end points, the 6 h limit; yield_pct is the surface's yield there and rate_at_optimum the rate surface's value; model_yield_6h_pct is the yield after 6 h that the refitted membrane model (x6) predicts at the optimum's temperature, DMSO and glycine, in percent of the glycine; window_points is the number of the design's 27 condition sets (every combination of the factors' three tested levels) whose surface yield is at least 90 % of the optimum yield; kinetic_parameters_identifiable is the number of x7's parameters that are identifiable; dmso_pct_vertex is the DMSO value at which the yield surface's DMSO term peaks when unconstrained, and inside_range is 1 when the whole unconstrained optimum (all three factors) lies inside the tested range, else 0.

### z2: Robustness

The optimum re-solved over a fixed bootstrap of experiments.

- Reads: z1 (`results/z1_operating_window.json`), x7 (`results/x7_identifiability.json`), b1 (`results/b1_batch_endpoints.csv`), m1 (`results/m1_membrane_endpoints.csv`)
- Writes: `/workspace/results/z2_robustness.json` (json)
- Format: JSON object {"n_boot": 200, "n_degenerate", "factor_choice": {"temp_c": {"lo", "hi", "interior"}, "dmso_pct": {...}, "gly_m": {...}}, "same_corner_share", "yield_ci": {"lo", "hi"}}. Resample the 51 two-phase batch and membrane experiments with replacement 200 times: for b in range(200), idx = numpy.random.RandomState(20261115).randint(0, 51, 51) drawn in sequence from one generator created once, the experiments taken in increasing experiment number. On each resample refit x3's yield surface (the same eight terms, ordinary least squares, numpy.linalg.lstsq) and re-solve z1's optimum with the same rules; a resample whose design matrix has rank below 8 is counted in n_degenerate and skipped. factor_choice gives, per factor, the share of the usable resamples whose optimum is at the lowest tested level (lo), the highest (hi), or strictly between (interior); same_corner_share is the share whose three choices equal z1's; yield_ci is the 2.5 and 97.5 percentiles (numpy.percentile) of the optimum yield over the usable resamples.

### z3: Mode decision

The recommended process mode, with its numbers.

- Reads: y1 (`results/y1_flow_from_batch.json`), y2 (`results/y2_productivity.json`), z2 (`results/z2_robustness.json`), x1 (`results/x1_mode_pairing.json`)
- Writes: `/workspace/results/z3_mode_decision.json` (json)
- Format: JSON object {"recommended_mode", "runner_up", "mean_sty": {"batch2p", "membrane", "batch1p", "flow", "recycle"}, "sty_margin", "membrane_wins", "flow_transfer_ratio", "optimum_share"}: the recommended mode is the one with the highest mean space-time yield of y2, runner_up the next; mean_sty is y2's mean per mode; sty_margin the recommended mode's mean divided by the runner-up's; membrane_wins the number of x1's pairs whose membrane yield is above the batch yield; flow_transfer_ratio the mean of y1's predicted/measured ratios; optimum_share z2's same_corner_share.

### R1: Dossier tables

Every headline number with its interval.

- Reads: z3 (`results/z3_mode_decision.json`), z1 (`results/z1_operating_window.json`), x2 (`results/x2_arrhenius.json`), x3 (`results/x3_response_surface.json`), y2 (`results/y2_productivity.json`), x6 (`results/x6_refit.json`), x7 (`results/x7_identifiability.json`), z2 (`results/z2_robustness.json`)
- Writes: `/workspace/results/R1_dossier.csv` (csv)
- Format: CSV with the header key,value,lo,hi and nine rows, in this order: batch2p.kf30, batch2p.k2, batch2p.dmso_exp, membrane.kf30, membrane.k2, membrane.dmso_exp (the refit's parameters, with x7's 95 % profile interval), optimum_yield_pct (z1's yield, with z2's bootstrap interval), membrane_ea_kj_mol and batch_ea_kj_mol (x2's activation energies, each with the 95 % interval of the Arrhenius slope: Ea +/- t x SE(slope) x R / 1000, t = 12.706 for one degree of freedom, from the least-squares line of ln k against 1/T over the three temperatures).

### R2: QC certificate

Every exclusion and correction, each justified.

- Reads: k3 (`results/k3_dilution.csv`), k6 (`results/k6_outliers.csv`), x5 (`results/x5_residual_review.csv`), S1 (`data/injections.csv`)
- Writes: `/workspace/results/R2_qc_certificate.csv` (csv)
- Format: CSV with the header kind,exp,sample,value, one row per departure from the plain data: every sample that is excluded (kind = exclusion; value = its total peak area over the highest total peak area of the experiment's earlier accepted samples) and every injection whose dilution factor differs from the usual 1:5 (kind = dilution; value = the factor), the first injection of each experiment (sample 0) excepted, plus one row of kind = correction for every correction accepted in x5 (value = the new factor, or 1 for a restored sample). Rows are sorted by kind, exp, sample.

### R3: Model card

Mechanism, parameters, identifiability, flow transfer.

- Reads: x6 (`results/x6_refit.json`), x7 (`results/x7_identifiability.json`), y1 (`results/y1_flow_from_batch.json`)
- Writes: `/workspace/results/R3_model_card.json` (json)
- Format: JSON object {"mechanism", "parameters": {"batch2p": {...}, "membrane": {...}} (the refit's), "rmse", "identifiable_parameters" (number of x7's parameters identifiable), "flow_transfer_ratio" (mean of y1's predicted/measured ratios), "flow_assumed": {"temp_c", "dmso_pct"}}.

The lab's LIMS submission, `scripts/submit_to_lims.sh`, is for the lab to run after review: do not run it.
