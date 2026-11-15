# Reporting protocol

The lab's rules for how results are worked out and reported.

## Blank, yield and ratio

- The sample at time 0 is a blank: the lab sets both of its concentrations to zero instead of computing them from the calibration.
- Yield is the percentage of the initial glycine that has become phenylserine: 100 x (c_anti + c_syn) / (1000 x c_glycine), with the concentrations in mmol/L and the glycine in mol/L.
- The diastereomer ratio R is PA_syn / PA_anti, a ratio of the areas themselves; the concentrations are not used for it.

## End points

- The end point of a batch or membrane experiment is its last valid sample taken at or before 6 h; later samples are not part of the protocol.
- The steady state of a flow experiment is the mean of its samples 4 to 6, for concentrations and peak areas alike; its yield and ratio are computed from those means.
- The end point of a recycle experiment is its last sample, however late it was taken.

## Outliers

- A sample taken at or before 6 h whose total peak area (anti + syn) is below 95 % of the highest total of the experiment's earlier valid samples is an outlier. Outliers are left out of end points, rates and fits.

## Rates and fits

- The initial rate is the least-squares slope (free intercept) of the total concentration c_anti + c_syn against time, over the valid samples taken at or before 2 h, the blank included.
- The rate constant k comes from c(t) = c_inf x (1 - exp(-k t)), fitted by least squares to the total concentration over the valid samples at or before 6 h, the blank included; c_inf is fitted too.
- An experiment whose end-point yield is below 1 % is too flat to fit: it gets no initial rate and no fit.

## Activation energy and reference group

- The activation energy is -R times the slope of ln k against 1/T, with T in kelvin (degrees C + 273.15) and R = 8.314 J/(mol K), by least squares through the mean k of each temperature; it is reported in kJ/mol.
- The lab's reference group is the membrane experiments with 1.0 mol/L glycine and 25 vol.% DMSO.

## Background

- The enzyme is L-threonine aldolase; the substrates are glycine and benzaldehyde.
- In the first batch series benzaldehyde, which hardly dissolves in water, formed a second phase.
- In the membrane-assisted series the dialysis membrane passively controls the transport of benzaldehyde into the aqueous phase.
- The recycle runs pumped the reaction mixture back through the reactor at 10 mL/h.
- The authors' tables end each flow block with an overall row; the lab does not use it.
- DMSO is the co-solvent that keeps the substrates in solution.
