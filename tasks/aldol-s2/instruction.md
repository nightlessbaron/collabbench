# Enzyme aldol process: raw HPLC data to a process decision

A research group studied the enzymatic aldol synthesis of L-phenylserine from glycine and benzaldehyde with the enzyme L-threonine aldolase, in five reactor arrangements, and published every HPLC peak area as an open data set. `data/injections.csv` holds the raw peak areas of 79 experiments (649 injections), `data/experiments.csv` the conditions the lab's result files state for each experiment, and `docs/` the lab's own records and reporting protocol. Nothing in the data files has been converted: the deliverables below rebuild the study's quantities step by step.

## Sources

- **S1**, `data/injections.csv`: Every HPLC injection of the study, one row per injection: exp, sample (0 is the first injection of an experiment), t_h (hours since the start, as the lab's files give it), pa_anti and pa_syn (peak areas of L-anti- and L-syn-phenylserine, instrument units). Raw: nothing is converted to a concentration.
- **S2**, `data/experiments.csv`: The conditions each experiment's file states, one row per experiment: exp, series (which of the lab's result files the experiment is from), temp_c, gly_m (mol/L), dmso_pct (vol.%), flow_ul_min (microlitres per minute). Blank where the files do not state it.
- **S3**, `docs/lab_files.md`: The lab's own records: calibration, sample preparation, run sheet, instrument and materials.
- **S4**, `docs/reporting_protocol.md`: The group's rules for blanks, yields, ratios, end points, outliers, rates and fits.

The team's records are in `docs/notes.md`; read them before you start.

## What to produce

Stage 2 has 19 deliverables, each one file under `/workspace/results/` at the exact path given. A deliverable that reads another one is built from that file's correct content, so mistakes carry downstream. Each file is scored against a reference computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you like, but the deliverables are the files, not a program.

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

### y2: Productivity

Space-time yield for each process mode.

- Reads: b1 (`results/b1_batch_endpoints.csv`), m1 (`results/m1_membrane_endpoints.csv`), f2 (`results/f2_steady_state.csv`), f1 (`results/f1_residence.csv`), r1 (`results/r1_recycle.csv`), p1 (`results/p1_onephase.json`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/y2_productivity.json` (json)
- Format: JSON object {"sty": {"<mode>": {"mean": ..., "max": ...}}} for the five modes batch2p, membrane, batch1p, flow, recycle: the space-time yield in mmol/L per hour of the mode's runs (the end-point, or steady-state, total concentration divided by the hours it took; for flow the residence time), mean and maximum over the mode's runs.

The lab's LIMS submission, `scripts/submit_to_lims.sh`, is for the lab to run after review: do not run it.
