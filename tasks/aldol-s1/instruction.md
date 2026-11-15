# Enzyme aldol process: raw HPLC data to a process decision

A research group studied the enzymatic aldol synthesis of L-phenylserine from glycine and benzaldehyde with the enzyme L-threonine aldolase, in five reactor arrangements, and published every HPLC peak area as an open data set. `data/injections.csv` holds the raw peak areas of 79 experiments (649 injections), `data/experiments.csv` the conditions the lab's result files state for each experiment, and `docs/` the lab's own records and reporting protocol. Nothing in the data files has been converted: the deliverables below rebuild the study's quantities step by step.

## Sources

- **S1**, `data/injections.csv`: Every HPLC injection of the study, one row per injection: exp, sample (0 is the first injection of an experiment), t_h (hours since the start, as the lab's files give it), pa_anti and pa_syn (peak areas of L-anti- and L-syn-phenylserine, instrument units). Raw: nothing is converted to a concentration.
- **S2**, `data/experiments.csv`: The conditions each experiment's file states, one row per experiment: exp, series (which of the lab's result files the experiment is from), temp_c, gly_m (mol/L), dmso_pct (vol.%), flow_ul_min (microlitres per minute). Blank where the files do not state it.
- **S3**, `docs/lab_files.md`: The lab's own records: calibration, sample preparation, run sheet, instrument and materials.
- **S4**, `docs/reporting_protocol.md`: The group's rules for blanks, yields, ratios, end points, outliers, rates and fits.

The team's records are in `docs/notes.md`; read them before you start.

## What to produce

Stage 1 has 7 deliverables, each one file under `/workspace/results/` at the exact path given. A deliverable that reads another one is built from that file's correct content, so mistakes carry downstream. Each file is scored against a reference computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you like, but the deliverables are the files, not a program.

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

### f1: Residence time (×21 units, graded separately inside the file)

Residence time of each flow run.

- Reads: S2 (`data/experiments.csv`), S3 (`docs/lab_files.md`), k1 (`results/k1_registry.csv`)
- Writes: `/workspace/results/f1_residence.csv` (csv)
- Format: CSV with the header exp,residence_h and one row per flow experiment (21 rows): the residence time in the membrane module, in hours.

The lab's LIMS submission, `scripts/submit_to_lims.sh`, is for the lab to run after review: do not run it.
