#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
T="$(mktemp -d)"
cat > "$T/graph.json" <<'GRAPH_JSON_EOF'
{
 "sources": [
  {
   "id": "S1",
   "title": "Injections",
   "what": "Every HPLC injection of the study, one row per injection: exp, sample (0 is the first injection of an experiment), t_h (hours since the start, as the lab's files give it), pa_anti and pa_syn (peak areas of L-anti- and L-syn-phenylserine, instrument units). Raw: nothing is converted to a concentration.",
   "files": [
    "data/injections.csv"
   ]
  },
  {
   "id": "S2",
   "title": "Conditions",
   "what": "The conditions each experiment's file states, one row per experiment: exp, series (which of the lab's result files the experiment is from), temp_c, gly_m (mol/L), dmso_pct (vol.%), flow_ul_min (microlitres per minute). Blank where the files do not state it.",
   "files": [
    "data/experiments.csv"
   ]
  },
  {
   "id": "S3",
   "title": "Lab files",
   "what": "The lab's own records: calibration, sample preparation, run sheet, instrument and materials.",
   "files": [
    "docs/lab_files.md"
   ]
  },
  {
   "id": "S4",
   "title": "Reporting protocol",
   "what": "The group's rules for blanks, yields, ratios, end points, outliers, rates and fits.",
   "files": [
    "docs/reporting_protocol.md"
   ]
  }
 ],
 "nodes": [
  {
   "id": "k1",
   "title": "Experiment registry",
   "what": "79 experiments in five process modes: two-phase batch (12), membrane (39), one-phase batch (3), flow (21), recycle (4). Each has its sampling plan.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "S2",
    "S3"
   ],
   "hard": [
    "Flow and recycle experiments have no glycine in the conditions file (blank), and no temperature or DMSO either; flow_ul_min is blank for all four recycle runs -> a9 (glycine 0.45 mol/L for flow and recycle)"
   ],
   "facts": [
    "a9"
   ],
   "decisions": [],
   "overlays": {
    "P": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/k1_registry.csv",
    "format": "csv",
    "columns": [
     "exp",
     "mode",
     "temp_c",
     "gly_m",
     "dmso_pct",
     "flow_ul_min",
     "n_samples",
     "final_t_h"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,mode,temp_c,gly_m,dmso_pct,flow_ul_min,n_samples,final_t_h and one row per experiment (79 rows). mode is one of batch2p (two-phase batch), membrane, batch1p (one-phase batch), flow, recycle. temp_c (deg C), gly_m (initial glycine, mol/L), dmso_pct (vol.%) and flow_ul_min (microlitres per minute) are the experiment's conditions, left empty where the experiment has none; n_samples is its number of injections and final_t_h the hours of its last injection."
   },
   "checks": {
    "count": 237,
    "families": [
     {
      "id": "mode",
      "what": "the process mode of each experiment",
      "count": 79,
      "select": "*/mode",
      "tolerance": "exact"
     },
     {
      "id": "conditions",
      "what": "temperature, glycine, DMSO and flow rate of each experiment, empty ones included",
      "count": 79,
      "select": "*",
      "fields": [
       "temp_c",
       "gly_m",
       "dmso_pct",
       "flow_ul_min"
      ],
      "tolerance": "abs 0.0001"
     },
     {
      "id": "sampling",
      "what": "the sampling plan: number of injections and last hour of each experiment",
      "count": 79,
      "select": "*",
      "fields": [
       "n_samples",
       "final_t_h"
      ],
      "tolerance": "abs 0.0001"
     }
    ]
   }
  },
  {
   "id": "k2",
   "title": "Calibration",
   "what": "Which calibration converts each injection, and how.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S3"
   ],
   "hard": [
    "Experiment 1 was evaluated with an earlier calibration, through the origin -> a5",
    "Only L-anti standards were run, so syn is quantified on the anti calibration -> a12"
   ],
   "facts": [
    "a1",
    "a5",
    "a12"
   ],
   "decisions": [],
   "overlays": {
    "P": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/k2_calibration.csv",
    "format": "csv",
    "columns": [
     "exp",
     "sample",
     "anti_slope",
     "anti_offset",
     "syn_slope",
     "syn_offset"
    ],
    "key": [
     "exp",
     "sample"
    ],
    "schema": "CSV with the header exp,sample,anti_slope,anti_offset,syn_slope,syn_offset and one row per injection of injections.csv (649 rows). The calibration line that converts the injection's anti peak is PA = anti_slope x c + anti_offset, and the line for its syn peak PA = syn_slope x c + syn_offset, with c the injected concentration in mmol/L."
   },
   "checks": {
    "count": 649,
    "families": [
     {
      "id": "calibration",
      "what": "the four calibration constants of each injection",
      "count": 649,
      "select": "*",
      "fields": [
       "anti_slope",
       "anti_offset",
       "syn_slope",
       "syn_offset"
      ],
      "tolerance": "abs 0.01"
     }
    ]
   }
  },
  {
   "id": "k3",
   "title": "Dilution map",
   "what": "A dilution factor for every one of the 649 injections.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "S3",
    "k1"
   ],
   "hard": [
    "Six regimes: 1. 1:5, the default. 2. 1:10 for two whole experiments. 3. 1:10 for two single 24-hour samples. 4. 1:5, then 1:2, in three flow runs. 5. Undiluted in four runs. 6. A switch after two samples in two more. -> a2 (default), a3, a4, a6, a7, a8"
   ],
   "facts": [
    "a2",
    "a3",
    "a4",
    "a6",
    "a7",
    "a8"
   ],
   "decisions": [],
   "overlays": {
    "P": "",
    "S": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/k3_dilution.csv",
    "format": "csv",
    "columns": [
     "exp",
     "sample",
     "dilution"
    ],
    "key": [
     "exp",
     "sample"
    ],
    "schema": "CSV with the header exp,sample,dilution and one row per injection of injections.csv (649 rows). dilution is the factor by which the injected sample was diluted relative to the reaction mixture (1 = injected neat). Leave it empty for sample 0, the first injection of each experiment."
   },
   "checks": {
    "count": 570,
    "families": [
     {
      "id": "default_dilution",
      "what": "samples on the usual 1:5 dilution",
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         23,
         24
        ]
       },
       {
        "exp": [
         21,
         22
        ],
        "sample": [
         8
        ]
       },
       {
        "exp": [
         59,
         60,
         61
        ]
       },
       {
        "exp": [
         62,
         63,
         64,
         67
        ]
       },
       {
        "exp": [
         65,
         66
        ]
       }
      ],
      "count": 498,
      "select": "*",
      "fields": [
       "dilution"
      ],
      "tolerance": "exact"
     },
     {
      "id": "tenfold_experiments",
      "what": "samples of the two experiments diluted 1:10 throughout",
      "where": {
       "exp": [
        23,
        24
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       }
      ],
      "count": 16,
      "select": "*",
      "fields": [
       "dilution"
      ],
      "tolerance": "exact"
     },
     {
      "id": "tenfold_24h",
      "what": "the two single 24-hour samples diluted 1:10",
      "where": {
       "exp": [
        21,
        22
       ],
       "sample": [
        8
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       }
      ],
      "count": 2,
      "select": "*",
      "fields": [
       "dilution"
      ],
      "tolerance": "exact"
     },
     {
      "id": "mixed_dilution",
      "what": "samples of the three runs diluted 1:5 then 1:2",
      "where": {
       "exp": [
        59,
        60,
        61
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       }
      ],
      "count": 18,
      "select": "*",
      "fields": [
       "dilution"
      ],
      "tolerance": "exact"
     },
     {
      "id": "undiluted",
      "what": "samples of the four undiluted runs",
      "where": {
       "exp": [
        62,
        63,
        64,
        67
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       }
      ],
      "count": 24,
      "select": "*",
      "fields": [
       "dilution"
      ],
      "tolerance": "exact"
     },
     {
      "id": "switch_dilution",
      "what": "samples of the two runs that switch dilution after two samples",
      "where": {
       "exp": [
        65,
        66
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       }
      ],
      "count": 12,
      "select": "*",
      "fields": [
       "dilution"
      ],
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "k4",
   "title": "Time base",
   "what": "Hours since the start for every sample.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "k1"
   ],
   "hard": [
    "The one-phase batch runs were sampled on a 10-minute grid, but the hours column is rounded -> a10"
   ],
   "facts": [
    "a10"
   ],
   "decisions": [],
   "overlays": {
    "P": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/k4_timebase.csv",
    "format": "csv",
    "columns": [
     "exp",
     "sample",
     "t_true_h"
    ],
    "key": [
     "exp",
     "sample"
    ],
    "schema": "CSV with the header exp,sample,t_true_h and one row per injection (649 rows): the true hours since the start of the experiment at which the sample was taken."
   },
   "checks": {
    "count": 649,
    "families": [
     {
      "id": "grid_series",
      "what": "the one-phase batch runs, whose hours column is rounded",
      "where": {
       "exp": [
        50,
        51,
        52
       ]
      },
      "count": 53,
      "select": "*",
      "fields": [
       "t_true_h"
      ],
      "tolerance": "abs 0.001"
     },
     {
      "id": "other_series",
      "what": "every other experiment",
      "where_not": {
       "exp": [
        50,
        51,
        52
       ]
      },
      "count": 596,
      "select": "*",
      "fields": [
       "t_true_h"
      ],
      "tolerance": "abs 0.001"
     }
    ]
   }
  },
  {
   "id": "k5",
   "title": "Concentrations",
   "what": "anti and syn concentration in mmol/L for every injection.",
   "kind": "work",
   "units": "×649",
   "inputs": [
    "k2",
    "k3",
    "k4"
   ],
   "hard": [
    "Dilution multiplies after inverting the calibration with its intercept, not before; the blank is set to zero, not computed -> a1, b1",
    "Experiment 1 is on the earlier calibration and its dilution still applies -> a5; any error in k2 to k4 lands here"
   ],
   "facts": [
    "a1",
    "a5",
    "a12",
    "b1"
   ],
   "decisions": [],
   "overlays": {
    "S": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/k5_concentrations.csv",
    "format": "csv",
    "columns": [
     "exp",
     "sample",
     "c_anti",
     "c_syn"
    ],
    "key": [
     "exp",
     "sample"
    ],
    "schema": "CSV with the header exp,sample,c_anti,c_syn and one row per injection (649 rows): the concentration of L-anti- and L-syn-phenylserine in the reaction mixture, in mmol/L."
   },
   "checks": {
    "count": 649,
    "families": [
     {
      "id": "blank_samples",
      "what": "the first injection of every experiment",
      "where": {
       "sample": [
        0
       ]
      },
      "count": 79,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "early_calibration",
      "what": "experiment 1's samples",
      "where": {
       "exp": [
        1
       ]
      },
      "where_not": {
       "sample": [
        0
       ]
      },
      "count": 6,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "default_dilution",
      "what": "samples on the usual 1:5 dilution",
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         1
        ]
       },
       {
        "exp": [
         23,
         24
        ]
       },
       {
        "exp": [
         21,
         22
        ],
        "sample": [
         8
        ]
       },
       {
        "exp": [
         59,
         60,
         61
        ]
       },
       {
        "exp": [
         62,
         63,
         64,
         67
        ]
       },
       {
        "exp": [
         65,
         66
        ]
       }
      ],
      "count": 492,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "tenfold_experiments",
      "what": "samples of the two experiments diluted 1:10 throughout",
      "where": {
       "exp": [
        23,
        24
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         1
        ]
       }
      ],
      "count": 16,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "tenfold_24h",
      "what": "the two single 24-hour samples diluted 1:10",
      "where": {
       "exp": [
        21,
        22
       ],
       "sample": [
        8
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         1
        ]
       }
      ],
      "count": 2,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "mixed_dilution",
      "what": "samples of the three runs diluted 1:5 then 1:2",
      "where": {
       "exp": [
        59,
        60,
        61
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         1
        ]
       }
      ],
      "count": 18,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "undiluted",
      "what": "samples of the four undiluted runs",
      "where": {
       "exp": [
        62,
        63,
        64,
        67
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         1
        ]
       }
      ],
      "count": 24,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     },
     {
      "id": "switch_dilution",
      "what": "samples of the two runs that switch dilution after two samples",
      "where": {
       "exp": [
        65,
        66
       ]
      },
      "where_not": [
       {
        "sample": [
         0
        ]
       },
       {
        "exp": [
         1
        ]
       }
      ],
      "count": 12,
      "select": "*",
      "fields": [
       "c_anti",
       "c_syn"
      ],
      "tolerance": "rel 1% or abs 0.001"
     }
    ]
   }
  },
  {
   "id": "k6",
   "title": "Outlier screen",
   "what": "An accepted or rejected flag per sample.",
   "kind": "work",
   "units": null,
   "inputs": [
    "S1",
    "S4",
    "k4"
   ],
   "hard": [
    "A sample at or before 6 h whose total peak area is below 95% of the highest earlier valid total is a sampling failure, not chemistry -> b6",
    "The rule is not applied to flow runs, whose early samples are start-up (applying it literally rejects 33 flow samples) -> Q4 (a convention of the reference, not stated in the data set)"
   ],
   "facts": [
    "b6"
   ],
   "decisions": [
    "Q4"
   ],
   "overlays": {
    "A": "",
    "V": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/k6_outliers.csv",
    "format": "csv",
    "columns": [
     "exp",
     "sample",
     "accepted"
    ],
    "key": [
     "exp",
     "sample"
    ],
    "schema": "CSV with the header exp,sample,accepted and one row per injection (649 rows): 1 when the sample is accepted, 0 when it is rejected as a sampling failure."
   },
   "checks": {
    "count": 649,
    "families": [
     {
      "id": "rejected",
      "what": "the samples the lab's rule rejects",
      "where": {
       "accepted": [
        0
       ]
      },
      "count": 4,
      "select": "*",
      "fields": [
       "accepted"
      ],
      "tolerance": "exact"
     },
     {
      "id": "accepted",
      "what": "the samples it accepts",
      "where": {
       "accepted": [
        1
       ]
      },
      "count": 645,
      "select": "*",
      "fields": [
       "accepted"
      ],
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "b1",
   "title": "Batch end points",
   "what": "Yield and syn/anti ratio at the end point of each two-phase batch run.",
   "kind": "work",
   "units": "×12",
   "inputs": [
    "k5",
    "k6",
    "S4",
    "k1",
    "k4"
   ],
   "hard": [
    "The end point is the last sample at or before 6 h, not the last sample. The ratio is of peak areas."
   ],
   "facts": [
    "b2",
    "b3",
    "b4"
   ],
   "decisions": [],
   "overlays": {
    "P": ""
   },
   "stage_built": 2,
   "output": {
    "path": "results/b1_batch_endpoints.csv",
    "format": "csv",
    "columns": [
     "exp",
     "end_sample",
     "end_t_h",
     "yield_pct",
     "ratio"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,end_sample,end_t_h,yield_pct,ratio and one row per two-phase batch (batch2p) experiment (12 rows): the sample index and the hours of the experiment's end point, the yield there in percent of the initial glycine, and the diastereomer ratio syn/anti (dimensionless)."
   },
   "checks": {
    "count": 48,
    "families": [
     {
      "id": "end_sample",
      "what": "which sample is the end point",
      "count": 12,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "end_sample"
      ]
     },
     {
      "id": "end_time",
      "what": "the end point's hours",
      "count": 12,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "end_t_h"
      ]
     },
     {
      "id": "yield",
      "what": "the yield at the end point",
      "count": 12,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "yield_pct"
      ]
     },
     {
      "id": "ratio",
      "what": "the syn/anti ratio at the end point",
      "count": 12,
      "select": "*",
      "tolerance": "rel 1%",
      "fields": [
       "ratio"
      ]
     }
    ]
   }
  },
  {
   "id": "b2",
   "title": "Batch rates",
   "what": "Initial rate and first-order rate constant for each two-phase batch run.",
   "kind": "work",
   "units": "×12",
   "inputs": [
    "k5",
    "k6",
    "k4",
    "k1"
   ],
   "hard": [
    "The t = 0 blank is a true zero and belongs in the fit."
   ],
   "facts": [
    "b1",
    "b7",
    "b8",
    "b12"
   ],
   "decisions": [],
   "overlays": {},
   "stage_built": 2,
   "output": {
    "path": "results/b2_batch_rates.csv",
    "format": "csv",
    "columns": [
     "exp",
     "fitted",
     "initial_rate",
     "c_inf",
     "k"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,fitted,initial_rate,c_inf,k and one row per two-phase batch (batch2p) experiment (12 rows). fitted is 1 when the experiment gets a rate and a fit, else 0 (then leave the other columns empty). initial_rate is in mmol/L per hour, c_inf in mmol/L and k in 1/h, for the total (anti + syn) concentration."
   },
   "checks": {
    "count": 39,
    "families": [
     {
      "id": "fitted",
      "what": "which experiments are fitted",
      "count": 12,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "fitted"
      ]
     },
     {
      "id": "initial_rate",
      "what": "the initial rate of each fitted experiment",
      "count": 9,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "where": {
       "fitted": [
        1
       ]
      },
      "fields": [
       "initial_rate"
      ]
     },
     {
      "id": "c_inf",
      "what": "the fitted plateau",
      "count": 9,
      "select": "*",
      "tolerance": "rel 2%",
      "where": {
       "fitted": [
        1
       ]
      },
      "fields": [
       "c_inf"
      ]
     },
     {
      "id": "k",
      "what": "the fitted rate constant",
      "count": 9,
      "select": "*",
      "tolerance": "rel 2%",
      "where": {
       "fitted": [
        1
       ]
      },
      "fields": [
       "k"
      ]
     }
    ]
   }
  },
  {
   "id": "m1",
   "title": "Membrane end points",
   "what": "Yield and ratio at the end point of each membrane run.",
   "kind": "work",
   "units": "×39",
   "inputs": [
    "k5",
    "k6",
    "S4",
    "k1",
    "k4"
   ],
   "hard": [],
   "facts": [
    "b2",
    "b3",
    "b4"
   ],
   "decisions": [],
   "overlays": {
    "S": ""
   },
   "stage_built": 2,
   "output": {
    "path": "results/m1_membrane_endpoints.csv",
    "format": "csv",
    "columns": [
     "exp",
     "end_sample",
     "end_t_h",
     "yield_pct",
     "ratio"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,end_sample,end_t_h,yield_pct,ratio and one row per membrane experiment (39 rows): the sample index and the hours of the experiment's end point, the yield there in percent of the initial glycine, and the diastereomer ratio syn/anti (dimensionless)."
   },
   "checks": {
    "count": 156,
    "families": [
     {
      "id": "end_sample",
      "what": "which sample is the end point",
      "count": 39,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "end_sample"
      ]
     },
     {
      "id": "end_time",
      "what": "the end point's hours",
      "count": 39,
      "select": "*",
      "tolerance": "abs 0.001",
      "fields": [
       "end_t_h"
      ]
     },
     {
      "id": "yield",
      "what": "the yield at the end point",
      "count": 39,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "yield_pct"
      ]
     },
     {
      "id": "ratio",
      "what": "the syn/anti ratio at the end point",
      "count": 39,
      "select": "*",
      "tolerance": "rel 1%",
      "fields": [
       "ratio"
      ]
     }
    ]
   }
  },
  {
   "id": "m2",
   "title": "Membrane rates",
   "what": "Initial rate and rate constant for each membrane run.",
   "kind": "work",
   "units": "×39",
   "inputs": [
    "k5",
    "k6",
    "k4",
    "k1"
   ],
   "hard": [],
   "facts": [
    "b7",
    "b8",
    "b12"
   ],
   "decisions": [],
   "overlays": {
    "S": ""
   },
   "stage_built": 2,
   "output": {
    "path": "results/m2_membrane_rates.csv",
    "format": "csv",
    "columns": [
     "exp",
     "fitted",
     "initial_rate",
     "c_inf",
     "k"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,fitted,initial_rate,c_inf,k and one row per membrane experiment (39 rows). fitted is 1 when the experiment gets a rate and a fit, else 0 (then leave the other columns empty). initial_rate is in mmol/L per hour, c_inf in mmol/L and k in 1/h, for the total (anti + syn) concentration."
   },
   "checks": {
    "count": 156,
    "families": [
     {
      "id": "fitted",
      "what": "which experiments are fitted",
      "count": 39,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "fitted"
      ]
     },
     {
      "id": "initial_rate",
      "what": "the initial rate of each fitted experiment",
      "count": 39,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "where": {
       "fitted": [
        1
       ]
      },
      "fields": [
       "initial_rate"
      ]
     },
     {
      "id": "c_inf",
      "what": "the fitted plateau",
      "count": 39,
      "select": "*",
      "tolerance": "rel 2%",
      "where": {
       "fitted": [
        1
       ]
      },
      "fields": [
       "c_inf"
      ]
     },
     {
      "id": "k",
      "what": "the fitted rate constant",
      "count": 39,
      "select": "*",
      "tolerance": "rel 2%",
      "where": {
       "fitted": [
        1
       ]
      },
      "fields": [
       "k"
      ]
     }
    ]
   }
  },
  {
   "id": "p1",
   "title": "One-phase batch",
   "what": "Yield against time on the corrected 10-minute grid, by glycine level.",
   "kind": "work",
   "units": "×3",
   "inputs": [
    "k5",
    "k4",
    "k1"
   ],
   "hard": [
    "The rounded hours shift early points enough to change the initial rate."
   ],
   "facts": [
    "a10"
   ],
   "decisions": [],
   "overlays": {},
   "stage_built": 2,
   "output": {
    "path": "results/p1_onephase.json",
    "format": "json",
    "schema": "JSON object {\"curve\": {\"<exp>|<sample>\": {\"t_h\": hours, \"yield_pct\": percent}}, \"initial_rate\": {\"<exp>\": mmol/L per hour}} for the three one-phase batch runs. The curve has an entry for every sample except sample 0 that the lab keeps; initial_rate is the initial rate of the total (anti + syn) concentration."
   },
   "checks": {
    "count": 53,
    "families": [
     {
      "id": "curve",
      "what": "yield against the corrected time at each sample",
      "count": 50,
      "select": "curve/*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "t_h",
       "yield_pct"
      ]
     },
     {
      "id": "initial_rate",
      "what": "the initial rate of each run",
      "count": 3,
      "select": "initial_rate/*",
      "tolerance": "rel 1% or abs 0.001"
     }
    ]
   }
  },
  {
   "id": "f1",
   "title": "Residence time",
   "what": "Residence time of each flow run.",
   "kind": "work",
   "units": "×21",
   "inputs": [
    "S2",
    "S3",
    "k1"
   ],
   "hard": [
    "Residence time is the channel volume (243 µL) over the flow rate; the flow rate is the only condition on file -> a11"
   ],
   "facts": [
    "a11"
   ],
   "decisions": [],
   "overlays": {
    "P": ""
   },
   "stage_built": 1,
   "output": {
    "path": "results/f1_residence.csv",
    "format": "csv",
    "columns": [
     "exp",
     "residence_h"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,residence_h and one row per flow experiment (21 rows): the residence time in the membrane module, in hours."
   },
   "checks": {
    "count": 21,
    "families": [
     {
      "id": "residence",
      "what": "the residence time of each flow run",
      "count": 21,
      "select": "*",
      "fields": [
       "residence_h"
      ],
      "tolerance": "rel 1%"
     }
    ]
   }
  },
  {
   "id": "f2",
   "title": "Steady state",
   "what": "Steady-state concentrations of each flow run.",
   "kind": "work",
   "units": "×21",
   "inputs": [
    "k5",
    "k6",
    "k1",
    "k4"
   ],
   "hard": [
    "The mean of samples 4 to 6. Earlier samples are start-up."
   ],
   "facts": [
    "b5"
   ],
   "decisions": [],
   "overlays": {
    "A": ""
   },
   "stage_built": 2,
   "output": {
    "path": "results/f2_steady_state.csv",
    "format": "csv",
    "columns": [
     "exp",
     "c_anti",
     "c_syn",
     "yield_pct",
     "ratio"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,c_anti,c_syn,yield_pct,ratio and one row per flow experiment (21 rows): the steady-state concentrations (mmol/L), the yield (percent of the initial glycine) and the syn/anti ratio."
   },
   "checks": {
    "count": 63,
    "families": [
     {
      "id": "concentrations",
      "what": "the steady-state concentrations",
      "count": 21,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "c_anti",
       "c_syn"
      ]
     },
     {
      "id": "yield",
      "what": "the steady-state yield",
      "count": 21,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "yield_pct"
      ]
     },
     {
      "id": "ratio",
      "what": "the steady-state ratio",
      "count": 21,
      "select": "*",
      "tolerance": "rel 1%",
      "fields": [
       "ratio"
      ]
     }
    ]
   }
  },
  {
   "id": "f3",
   "title": "Conversion vs τ",
   "what": "Conversion as a function of residence time, fitted across flow runs.",
   "kind": "work",
   "units": null,
   "inputs": [
    "f1",
    "f2"
   ],
   "hard": [],
   "facts": [],
   "decisions": [],
   "overlays": {},
   "stage_built": 2,
   "output": {
    "path": "results/f3_conversion.json",
    "format": "json",
    "schema": "JSON object {\"mean_conversion\": {\"<residence time in hours, 4 decimals>\": mean conversion (a fraction) of the flow runs at that residence time}, \"fit\": {\"x_inf\": plateau conversion, \"k_per_h\": rate constant in 1/h, \"rmse\": root-mean-square error of the fit over the runs}, \"n_runs\": number of flow runs}. The fit is conversion = x_inf (1 - exp(-k tau)) by least squares over all runs, conversion being the steady-state yield as a fraction."
   },
   "checks": {
    "count": 7,
    "families": [
     {
      "id": "mean_conversion",
      "what": "mean conversion at each residence time",
      "count": 3,
      "select": "mean_conversion/*",
      "tolerance": "rel 1%"
     },
     {
      "id": "fit",
      "what": "the fitted plateau, rate constant and error",
      "count": 3,
      "select": "fit/*",
      "tolerance": "rel 2%"
     },
     {
      "id": "n_runs",
      "what": "the number of runs",
      "count": 1,
      "select": "n_runs",
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "r1",
   "title": "Recycle passes",
   "what": "Per-pass and cumulative yield of each recycle run.",
   "kind": "work",
   "units": "×4",
   "inputs": [
    "k5",
    "k6",
    "k1",
    "k4"
   ],
   "hard": [],
   "facts": [
    "b11"
   ],
   "decisions": [],
   "overlays": {},
   "stage_built": 2,
   "output": {
    "path": "results/r1_recycle.csv",
    "format": "csv",
    "columns": [
     "exp",
     "sample",
     "t_true_h",
     "cumulative_yield_pct",
     "pass_yield_pct",
     "end_point"
    ],
    "key": [
     "exp",
     "sample"
    ],
    "schema": "CSV with the header exp,sample,t_true_h,cumulative_yield_pct,pass_yield_pct,end_point and one row per recycle sample except sample 0 (17 rows). cumulative_yield_pct is the yield in percent of the initial glycine at that sample; pass_yield_pct is its increase over the previous sample of the run (the first sample's increase is its whole yield); end_point is 1 on the sample that is the run's end point, else 0."
   },
   "checks": {
    "count": 51,
    "families": [
     {
      "id": "cumulative",
      "what": "the cumulative yield at each sample",
      "count": 17,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "cumulative_yield_pct"
      ]
     },
     {
      "id": "per_pass",
      "what": "the yield of each pass",
      "count": 17,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "pass_yield_pct"
      ]
     },
     {
      "id": "end_point",
      "what": "which sample is each run's end point",
      "count": 17,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "end_point"
      ]
     }
    ]
   }
  },
  {
   "id": "x1",
   "title": "Mode pairing",
   "what": "Batch and membrane runs matched on temperature, DMSO and glycine, with the difference per pair.",
   "kind": "work",
   "units": null,
   "inputs": [
    "b1",
    "m1",
    "S2"
   ],
   "hard": [
    "Decision: how repeated conditions are pooled before pairing."
   ],
   "facts": [],
   "decisions": [
    "Q1"
   ],
   "overlays": {
    "A": ""
   },
   "stage_built": 2,
   "output": {
    "path": "results/x1_mode_pairing.json",
    "format": "json",
    "schema": "JSON object {\"pairs\": {\"<temp_c>|<gly_m>|<dmso_pct>\": {\"batch_yield_pct\": ..., \"membrane_yield_pct\": ..., \"difference_pct\": membrane minus batch, \"n_batch\": number of batch runs at those conditions, \"n_membrane\": number of membrane runs at those conditions}}, \"n_pairs\": number of pairs}, one pair per condition set (written like 20|1|25, numbers without trailing zeros) that has both a two-phase batch and a membrane run."
   },
   "checks": {
    "count": 16,
    "families": [
     {
      "id": "difference",
      "what": "the yield difference of each pair",
      "count": 5,
      "select": "pairs/*",
      "tolerance": "rel 1% or abs 0.01",
      "fields": [
       "difference_pct"
      ]
     },
     {
      "id": "pair_yields",
      "what": "the batch and membrane yields of each pair",
      "count": 5,
      "select": "pairs/*",
      "tolerance": "rel 1% or abs 0.01",
      "fields": [
       "batch_yield_pct",
       "membrane_yield_pct"
      ]
     },
     {
      "id": "run_counts",
      "what": "how many runs each side has at the conditions",
      "count": 5,
      "select": "pairs/*",
      "tolerance": "exact",
      "fields": [
       "n_batch",
       "n_membrane"
      ]
     },
     {
      "id": "n_pairs",
      "what": "the number of pairs",
      "count": 1,
      "select": "n_pairs",
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "x2",
   "title": "Arrhenius",
   "what": "Activation energy from rate constants at 20, 30 and 40 °C.",
   "kind": "work",
   "units": null,
   "inputs": [
    "b2",
    "m2",
    "S2"
   ],
   "hard": [
    "Rate constants also move with DMSO and glycine. The temperature effect has to be taken at matched levels or inside a model."
   ],
   "facts": [
    "b9",
    "b10"
   ],
   "decisions": [],
   "overlays": {},
   "stage_built": 2,
   "output": {
    "path": "results/x2_arrhenius.json",
    "format": "json",
    "schema": "JSON object {\"membrane\": {\"k_mean_by_temp\": {\"20\": ..., \"30\": ..., \"40\": ...} (mean k in 1/h over the lab's reference group at that temperature), \"ea_kj_mol\": activation energy, \"group_size\": {\"20\": ..., \"30\": ..., \"40\": ...} (experiments in the group at each temperature)}, \"batch\": {\"k_by_temp\": {\"20\": ..., \"30\": ..., \"40\": ...} (k of the two-phase batch run at that temperature with the same glycine and DMSO as the group), \"ea_kj_mol\": activation energy}}."
   },
   "checks": {
    "count": 11,
    "families": [
     {
      "id": "membrane_k",
      "what": "mean k of the reference group at each temperature",
      "count": 3,
      "select": "membrane/k_mean_by_temp/*",
      "tolerance": "rel 2%"
     },
     {
      "id": "membrane_ea",
      "what": "the activation energy from the group",
      "count": 1,
      "select": "membrane/ea_kj_mol",
      "tolerance": "rel 2%"
     },
     {
      "id": "group_size",
      "what": "the group's size at each temperature",
      "count": 3,
      "select": "membrane/group_size/*",
      "tolerance": "exact"
     },
     {
      "id": "batch_k",
      "what": "k of the matched batch runs",
      "count": 3,
      "select": "batch/k_by_temp/*",
      "tolerance": "rel 2%"
     },
     {
      "id": "batch_ea",
      "what": "the activation energy from the batch runs",
      "count": 1,
      "select": "batch/ea_kj_mol",
      "tolerance": "rel 2%"
     }
    ]
   }
  },
  {
   "id": "x3",
   "title": "Response surface",
   "what": "Yield and rate as quadratic functions of temperature, DMSO and glycine, three levels each.",
   "kind": "work",
   "units": null,
   "inputs": [
    "b1",
    "b2",
    "m1",
    "m2",
    "S2"
   ],
   "hard": [
    "Batch and membrane runs cover the design differently, so pooling them needs a mode term."
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "I": ""
   },
   "stage_built": 2,
   "output": {
    "path": "results/x3_response_surface.json",
    "format": "json",
    "schema": "JSON object {\"yield\": {\"coef\": {...}, \"r2\": ..., \"n\": ...}, \"rate\": {\"coef\": {...}, \"r2\": ..., \"n\": ...}}: ordinary least squares of the end-point yield (percent; every two-phase batch and membrane experiment) and of the initial rate (mmol/L per hour; the experiments with a rate) on intercept, temp_c, dmso_pct, gly_m, their three squares (temp_c2, dmso_pct2, gly_m2) and membrane (1 for a membrane run, 0 for a batch run). coef has those eight names as keys, r2 is the coefficient of determination and n the number of experiments used."
   },
   "checks": {
    "count": 20,
    "families": [
     {
      "id": "yield_coef",
      "what": "the eight coefficients of the yield surface",
      "count": 8,
      "select": "yield/coef/*",
      "tolerance": "rel 2% or abs 1e-6"
     },
     {
      "id": "yield_fit",
      "what": "R squared and observation count of the yield surface",
      "count": 1,
      "select": "yield/r2",
      "tolerance": "rel 1%"
     },
     {
      "id": "yield_n",
      "what": "the number of experiments in the yield surface",
      "count": 1,
      "select": "yield/n",
      "tolerance": "exact"
     },
     {
      "id": "rate_coef",
      "what": "the eight coefficients of the rate surface",
      "count": 8,
      "select": "rate/coef/*",
      "tolerance": "rel 2% or abs 1e-6"
     },
     {
      "id": "rate_fit",
      "what": "R squared and observation count of the rate surface",
      "count": 1,
      "select": "rate/r2",
      "tolerance": "rel 1%"
     },
     {
      "id": "rate_n",
      "what": "the number of experiments in the rate surface",
      "count": 1,
      "select": "rate/n",
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "x4",
   "title": "Kinetic model",
   "what": "One mechanistic model fitted jointly to every batch and membrane time course.",
   "kind": "work",
   "units": null,
   "inputs": [
    "k5",
    "k6",
    "k4",
    "x2"
   ],
   "hard": [
    "Which mechanism to fit: irreversible, reversible aldol, or with enzyme decay; the choice changes every rate constant downstream -> Q2 (reversible aldol has the lowest joint SSE; decay is within 1.7 %)"
   ],
   "facts": [
    "b8",
    "b9"
   ],
   "decisions": [
    "Q2"
   ],
   "overlays": {
    "A": "",
    "H": ""
   },
   "stage_built": 3,
   "output": {
    "path": "results/x4_kinetic_model.json",
    "format": "json",
    "schema": "JSON object {\"mechanism\": \"reversible\", \"ea_fixed_kj_mol\": ..., \"params\": {\"batch2p\": {\"kf30\", \"k2\", \"dmso_exp\"}, \"membrane\": {...}}, \"sse\": {\"batch2p\", \"membrane\", \"total\"}, \"rmse\": sqrt(total sse / total points), \"n_points\": {\"batch2p\", \"membrane\"}}. mechanism is the mechanism you fitted: one of irreversible, reversible, decay. The model: p(t) = kf G0 / (kf + k2) (1 - exp(-(kf + k2) t)) for the total phenylserine concentration p (mmol/L), G0 = 1000 x the glycine concentration in mol/L, kf = kf30 exp(-Ea/R (1/T - 1/303.15)) exp(dmso_exp (DMSO - 25)/25) with T in kelvin, DMSO in vol.%, R = 8.314 J/(mol K) and Ea the membrane activation energy of x2, held fixed; kf30 (1/h), k2 (1/h) and dmso_exp are fitted separately for the two modes batch2p and membrane, by least squares on every accepted, non-blank sample of every two-phase batch and membrane experiment."
   },
   "checks": {
    "count": 14,
    "families": [
     {
      "id": "mechanism",
      "what": "the mechanism fitted",
      "count": 1,
      "select": "mechanism",
      "tolerance": "exact"
     },
     {
      "id": "ea_fixed",
      "what": "the fixed activation energy",
      "count": 1,
      "select": "ea_fixed_kj_mol",
      "tolerance": "rel 2%"
     },
     {
      "id": "params",
      "what": "the six fitted parameters",
      "count": 6,
      "select": "params/*/*",
      "tolerance": "rel 5% or abs 0.02"
     },
     {
      "id": "sse",
      "what": "the residual sums of squares",
      "count": 3,
      "select": "sse/*",
      "tolerance": "rel 2%"
     },
     {
      "id": "rmse",
      "what": "the root-mean-square residual",
      "count": 1,
      "select": "rmse",
      "tolerance": "rel 2%"
     },
     {
      "id": "n_points",
      "what": "the points fitted in each mode",
      "count": 2,
      "select": "n_points/*",
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "x5",
   "title": "Residual review",
   "what": "The runs whose residuals in x4 are systematic, each with its cause traced upstream.",
   "kind": "work",
   "units": null,
   "inputs": [
    "x4",
    "k3",
    "k6",
    "k5",
    "k4"
   ],
   "hard": [
    "On this data the page's expectation does not hold: 33 of the 51 runs have systematic residuals under the joint model, and none of them is explained by a single dilution or outlier call (best cuts under 80 %, and never leaving the run non-systematic); the misfit is the model's (DMSO and membrane effects), not an upstream error -> reference finding, see the rulings"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "V": ""
   },
   "stage_built": 3,
   "output": {
    "path": "results/x5_residual_review.csv",
    "format": "csv",
    "columns": [
     "exp",
     "systematic",
     "mean_residual",
     "best_cut",
     "accepted"
    ],
    "key": [
     "exp"
    ],
    "schema": "CSV with the header exp,systematic,mean_residual,best_cut,accepted and one row per two-phase batch and membrane experiment (51 rows), reviewing the fit of x4. Residual = measured minus modelled total concentration over the experiment's accepted non-blank samples. systematic is 1 when the absolute mean residual exceeds half the fit's rmse, else 0. For a systematic run only: mean_residual (mmol/L); best_cut, the largest fractional reduction of the run's sum of squared residuals (model parameters held fixed) achievable by ONE correction to one sample, either restoring a rejected sample or changing its dilution factor to one of 1, 2, 5 or 10 (concentration rescaled by new/old); accepted is 1 when that correction cuts the run's sum of squares by at least 75 % AND leaves the run non-systematic, else 0. Leave mean_residual and best_cut empty for runs that are not systematic."
   },
   "checks": {
    "count": 168,
    "families": [
     {
      "id": "systematic",
      "what": "which runs are systematic",
      "count": 51,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "systematic"
      ]
     },
     {
      "id": "mean_residual",
      "what": "the mean residual of each systematic run",
      "count": 33,
      "select": "*",
      "tolerance": "rel 5% or abs 0.05",
      "where": {
       "systematic": [
        1
       ]
      },
      "fields": [
       "mean_residual"
      ]
     },
     {
      "id": "best_cut",
      "what": "the best single correction's reduction in each systematic run",
      "count": 33,
      "select": "*",
      "tolerance": "abs 0.03",
      "where": {
       "systematic": [
        1
       ]
      },
      "fields": [
       "best_cut"
      ]
     },
     {
      "id": "accepted",
      "what": "which corrections are accepted",
      "count": 51,
      "select": "*",
      "tolerance": "exact",
      "fields": [
       "accepted"
      ]
     }
    ]
   }
  },
  {
   "id": "x6",
   "title": "Refit, round 2",
   "what": "x4 refitted after the corrections from x5.",
   "kind": "rework",
   "units": null,
   "inputs": [
    "x5",
    "x4",
    "k5",
    "k3",
    "k4",
    "k6"
   ],
   "hard": [
    "A correction has to flow back through concentrations and end points, not only through the fit; none is accepted on this data, so the refit equals x4's fit -> reference finding (x5 accepts no correction)"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {},
   "stage_built": 3,
   "output": {
    "path": "results/x6_refit.json",
    "format": "json",
    "schema": "The same JSON object as x4 plus \"corrections_applied\" (the number of corrections x5 accepted, applied before refitting: a restored sample counts, and a changed dilution rescales that sample's concentration), for the refit of the same model after those corrections."
   },
   "checks": {
    "count": 15,
    "families": [
     {
      "id": "corrections",
      "what": "how many corrections were applied",
      "count": 1,
      "select": "corrections_applied",
      "tolerance": "exact"
     },
     {
      "id": "refit_mechanism",
      "what": "the mechanism fitted",
      "count": 1,
      "select": "mechanism",
      "tolerance": "exact"
     },
     {
      "id": "refit_ea_fixed",
      "what": "the fixed activation energy",
      "count": 1,
      "select": "ea_fixed_kj_mol",
      "tolerance": "rel 2%"
     },
     {
      "id": "refit_params",
      "what": "the six fitted parameters",
      "count": 6,
      "select": "params/*/*",
      "tolerance": "rel 5% or abs 0.02"
     },
     {
      "id": "refit_sse",
      "what": "the residual sums of squares",
      "count": 3,
      "select": "sse/*",
      "tolerance": "rel 2%"
     },
     {
      "id": "refit_rmse",
      "what": "the root-mean-square residual",
      "count": 1,
      "select": "rmse",
      "tolerance": "rel 2%"
     },
     {
      "id": "refit_n_points",
      "what": "the points fitted in each mode",
      "count": 2,
      "select": "n_points/*",
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "x7",
   "title": "Identifiability",
   "what": "Which kinetic parameters the data actually pin down, with profile intervals.",
   "kind": "work",
   "units": null,
   "inputs": [
    "x6",
    "k5",
    "k6",
    "k4"
   ],
   "hard": [
    "Which kinetic parameters the data pin down, by 95 % profile intervals; with all six parameters identifiable here the node's value is in the interval widths"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "I": ""
   },
   "stage_built": 3,
   "output": {
    "path": "results/x7_identifiability.json",
    "format": "json",
    "schema": "JSON object {\"batch2p\": {\"kf30\": {\"lo\", \"hi\", \"identifiable\"}, \"k2\": {...}, \"dmso_exp\": {...}}, \"membrane\": {...}}: the 95 % profile interval of each parameter of the refit (x6). For one parameter fixed at a trial value, the other two of that mode are re-optimised; the interval is the set of trial values whose sum of squares stays below SSE_mode x (1 + 3.84 / (n_mode - 3)). Search at most 6 e-folds from the estimate for kf30 and k2 (24 units for dmso_exp); a bound not found is null and identifiable is 0, else 1."
   },
   "checks": {
    "count": 12,
    "families": [
     {
      "id": "bounds",
      "what": "the profile bounds of each parameter",
      "count": 6,
      "select": "*/*",
      "tolerance": "rel 10% or abs 0.05",
      "fields": [
       "lo",
       "hi"
      ]
     },
     {
      "id": "identifiable",
      "what": "which parameters the data pin down",
      "count": 6,
      "select": "*/*",
      "tolerance": "exact",
      "fields": [
       "identifiable"
      ]
     }
    ]
   }
  },
  {
   "id": "y1",
   "title": "Flow from batch",
   "what": "Flow conversion predicted from the batch model and residence time, against the measurements.",
   "kind": "work",
   "units": null,
   "inputs": [
    "x6",
    "f3",
    "k1"
   ],
   "hard": [
    "The flow runs have no temperature (or DMSO) on file; the batch model predicts about one seventh of the measured conversion at any assumed temperature -> Q3"
   ],
   "facts": [],
   "decisions": [
    "Q3"
   ],
   "overlays": {
    "A": ""
   },
   "stage_built": 3,
   "output": {
    "path": "results/y1_flow_from_batch.json",
    "format": "json",
    "schema": "JSON object {\"assumed\": {\"temp_c\", \"dmso_pct\"}, \"by_tau\": {\"<residence time in hours, 4 decimals>\": {\"predicted\", \"measured\", \"ratio\"}}, \"rmse\"}: the conversion (a fraction of the initial glycine) that the refitted membrane model (x6) predicts after the residence time of the flow runs (a plug-flow reactor with the flow runs' glycine), at the temperature and DMSO content assumed for the flow runs, against the measured mean conversion of f3; ratio = predicted / measured; rmse over the residence times."
   },
   "checks": {
    "count": 5,
    "families": [
     {
      "id": "assumed",
      "what": "the temperature and DMSO assumed",
      "count": 1,
      "select": "assumed",
      "tolerance": "exact",
      "fields": [
       "temp_c",
       "dmso_pct"
      ]
     },
     {
      "id": "prediction",
      "what": "the predicted conversion and its ratio to the measurement",
      "count": 3,
      "select": "by_tau/*",
      "tolerance": "rel 5% or abs 0.0005",
      "fields": [
       "predicted",
       "ratio"
      ]
     },
     {
      "id": "rmse",
      "what": "the prediction error",
      "count": 1,
      "select": "rmse",
      "tolerance": "rel 5%"
     }
    ]
   }
  },
  {
   "id": "y2",
   "title": "Productivity",
   "what": "Space-time yield for each process mode.",
   "kind": "work",
   "units": null,
   "inputs": [
    "b1",
    "m1",
    "f2",
    "f1",
    "r1",
    "p1",
    "k1"
   ],
   "hard": [],
   "facts": [],
   "decisions": [],
   "overlays": {},
   "stage_built": 2,
   "output": {
    "path": "results/y2_productivity.json",
    "format": "json",
    "schema": "JSON object {\"sty\": {\"<mode>\": {\"mean\": ..., \"max\": ...}}} for the five modes batch2p, membrane, batch1p, flow, recycle: the space-time yield in mmol/L per hour of the mode's runs (the end-point, or steady-state, total concentration divided by the hours it took; for flow the residence time), mean and maximum over the mode's runs."
   },
   "checks": {
    "count": 10,
    "families": [
     {
      "id": "mean_sty",
      "what": "the mean space-time yield of each mode",
      "count": 5,
      "select": "sty/*/mean",
      "tolerance": "rel 1%"
     },
     {
      "id": "max_sty",
      "what": "the best run's space-time yield in each mode",
      "count": 5,
      "select": "sty/*/max",
      "tolerance": "rel 1%"
     }
    ]
   }
  },
  {
   "id": "z1",
   "title": "Operating window",
   "what": "Conditions that maximise yield within the selectivity and time limits.",
   "kind": "work",
   "units": null,
   "inputs": [
    "x3",
    "x6",
    "x7"
   ],
   "hard": [
    "The unconstrained optimum sits outside the tested range: the DMSO term peaks at 29 vol.% (tested up to 25) and the temperature and glycine terms are convex, so the best conditions are at the ends of the tested range -> reference finding"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "A": ""
   },
   "stage_built": 4,
   "output": {
    "path": "results/z1_operating_window.json",
    "format": "json",
    "schema": "JSON object {\"optimum\": {\"temp_c\", \"dmso_pct\", \"gly_m\"}, \"yield_pct\", \"rate_at_optimum\", \"model_yield_6h_pct\", \"window_points\", \"kinetic_parameters_identifiable\", \"unconstrained\": {\"dmso_pct_vertex\", \"inside_range\"}}. The optimum is the membrane-run conditions of the highest end-point yield on x3's yield surface inside the tested range (the lowest to the highest level of temperature, DMSO and glycine in the conditions file) and, since yields are end points, the 6 h limit; yield_pct is the surface's yield there and rate_at_optimum the rate surface's value; model_yield_6h_pct is the yield after 6 h that the refitted membrane model (x6) predicts at the optimum's temperature, DMSO and glycine, in percent of the glycine; window_points is the number of the design's 27 condition sets (every combination of the factors' three tested levels) whose surface yield is at least 90 % of the optimum yield; kinetic_parameters_identifiable is the number of x7's parameters that are identifiable; dmso_pct_vertex is the DMSO value at which the yield surface's DMSO term peaks when unconstrained, and inside_range is 1 when the whole unconstrained optimum (all three factors) lies inside the tested range, else 0."
   },
   "checks": {
    "count": 8,
    "families": [
     {
      "id": "optimum",
      "what": "the optimum conditions",
      "count": 1,
      "select": "optimum",
      "tolerance": "abs 0.01",
      "fields": [
       "temp_c",
       "dmso_pct",
       "gly_m"
      ]
     },
     {
      "id": "yield",
      "what": "the yield at the optimum",
      "count": 1,
      "select": "yield_pct",
      "tolerance": "rel 1%"
     },
     {
      "id": "rate",
      "what": "the rate at the optimum",
      "count": 1,
      "select": "rate_at_optimum",
      "tolerance": "rel 1%"
     },
     {
      "id": "model_yield",
      "what": "the kinetic model's 6 h yield at the optimum",
      "count": 1,
      "select": "model_yield_6h_pct",
      "tolerance": "rel 5%"
     },
     {
      "id": "window",
      "what": "how many design points are near the optimum",
      "count": 1,
      "select": "window_points",
      "tolerance": "exact"
     },
     {
      "id": "identifiable",
      "what": "how many kinetic parameters are identifiable",
      "count": 1,
      "select": "kinetic_parameters_identifiable",
      "tolerance": "exact"
     },
     {
      "id": "unconstrained_vertex",
      "what": "the unconstrained DMSO peak",
      "count": 1,
      "select": "unconstrained/dmso_pct_vertex",
      "tolerance": "rel 1%"
     },
     {
      "id": "unconstrained_inside",
      "what": "whether the unconstrained optimum is in range",
      "count": 1,
      "select": "unconstrained/inside_range",
      "tolerance": "exact"
     }
    ]
   }
  },
  {
   "id": "z2",
   "title": "Robustness",
   "what": "The optimum re-solved over a fixed bootstrap of experiments.",
   "kind": "work",
   "units": null,
   "inputs": [
    "z1",
    "x7",
    "b1",
    "m1"
   ],
   "hard": [
    "The bootstrap is only comparable if the resampling is exactly the stated one: numpy RandomState(20261115), 200 draws of 51 -> definition in the schema"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {},
   "stage_built": 4,
   "output": {
    "path": "results/z2_robustness.json",
    "format": "json",
    "schema": "JSON object {\"n_boot\": 200, \"n_degenerate\", \"factor_choice\": {\"temp_c\": {\"lo\", \"hi\", \"interior\"}, \"dmso_pct\": {...}, \"gly_m\": {...}}, \"same_corner_share\", \"yield_ci\": {\"lo\", \"hi\"}}. Resample the 51 two-phase batch and membrane experiments with replacement 200 times: for b in range(200), idx = numpy.random.RandomState(20261115).randint(0, 51, 51) drawn in sequence from one generator created once, the experiments taken in increasing experiment number. On each resample refit x3's yield surface (the same eight terms, ordinary least squares, numpy.linalg.lstsq) and re-solve z1's optimum with the same rules; a resample whose design matrix has rank below 8 is counted in n_degenerate and skipped. factor_choice gives, per factor, the share of the usable resamples whose optimum is at the lowest tested level (lo), the highest (hi), or strictly between (interior); same_corner_share is the share whose three choices equal z1's; yield_ci is the 2.5 and 97.5 percentiles (numpy.percentile) of the optimum yield over the usable resamples."
   },
   "checks": {
    "count": 14,
    "families": [
     {
      "id": "n_boot",
      "what": "the bootstrap size",
      "count": 1,
      "select": "n_boot",
      "tolerance": "exact"
     },
     {
      "id": "n_degenerate",
      "what": "the degenerate resamples",
      "count": 1,
      "select": "n_degenerate",
      "tolerance": "exact"
     },
     {
      "id": "factor_choice",
      "what": "how often each factor's optimum is at an end",
      "count": 9,
      "select": "factor_choice/*/*",
      "tolerance": "abs 0.006"
     },
     {
      "id": "same_corner",
      "what": "how often the optimum is z1's",
      "count": 1,
      "select": "same_corner_share",
      "tolerance": "abs 0.006"
     },
     {
      "id": "yield_ci",
      "what": "the interval of the optimum yield",
      "count": 2,
      "select": "yield_ci/*",
      "tolerance": "rel 2%"
     }
    ]
   }
  },
  {
   "id": "z3",
   "title": "Mode decision",
   "what": "The recommended process mode, with its numbers.",
   "kind": "work",
   "units": null,
   "inputs": [
    "y1",
    "y2",
    "z2",
    "x1"
   ],
   "hard": [
    "The mode with the highest space-time yield (flow) is the one the batch model cannot predict (flow_transfer_ratio about 0.14) and has the lowest per-pass conversion (at most 6 %); the recommendation rule is the stated one, not a judgement of fitness -> ruling"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "A": ""
   },
   "stage_built": 4,
   "output": {
    "path": "results/z3_mode_decision.json",
    "format": "json",
    "schema": "JSON object {\"recommended_mode\", \"runner_up\", \"mean_sty\": {\"batch2p\", \"membrane\", \"batch1p\", \"flow\", \"recycle\"}, \"sty_margin\", \"membrane_wins\", \"flow_transfer_ratio\", \"optimum_share\"}: the recommended mode is the one with the highest mean space-time yield of y2, runner_up the next; mean_sty is y2's mean per mode; sty_margin the recommended mode's mean divided by the runner-up's; membrane_wins the number of x1's pairs whose membrane yield is above the batch yield; flow_transfer_ratio the mean of y1's predicted/measured ratios; optimum_share z2's same_corner_share."
   },
   "checks": {
    "count": 11,
    "families": [
     {
      "id": "recommended",
      "what": "the recommended mode",
      "count": 1,
      "select": "recommended_mode",
      "tolerance": "exact"
     },
     {
      "id": "runner_up",
      "what": "the runner-up",
      "count": 1,
      "select": "runner_up",
      "tolerance": "exact"
     },
     {
      "id": "mean_sty",
      "what": "the mean space-time yield of each mode",
      "count": 5,
      "select": "mean_sty/*",
      "tolerance": "rel 1%"
     },
     {
      "id": "margin",
      "what": "the margin of the recommendation",
      "count": 1,
      "select": "sty_margin",
      "tolerance": "rel 1%"
     },
     {
      "id": "membrane_wins",
      "what": "how many pairs the membrane wins",
      "count": 1,
      "select": "membrane_wins",
      "tolerance": "exact"
     },
     {
      "id": "flow_transfer",
      "what": "how well batch predicts flow",
      "count": 1,
      "select": "flow_transfer_ratio",
      "tolerance": "rel 5%"
     },
     {
      "id": "stability",
      "what": "how stable the operating point is",
      "count": 1,
      "select": "optimum_share",
      "tolerance": "abs 0.006"
     }
    ]
   }
  },
  {
   "id": "R1",
   "title": "Dossier tables",
   "what": "Every headline number with its interval.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "z3",
    "z1",
    "x2",
    "x3",
    "y2",
    "x6",
    "x7",
    "z2"
   ],
   "hard": [
    "With three temperatures the Arrhenius slope has one degree of freedom, so the activation-energy intervals span zero (membrane -60 to 100 kJ/mol): the data cannot pin Ea down -> reference finding"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "H": ""
   },
   "stage_built": 4,
   "output": {
    "path": "results/R1_dossier.csv",
    "format": "csv",
    "columns": [
     "key",
     "value",
     "lo",
     "hi"
    ],
    "key": [
     "key"
    ],
    "schema": "CSV with the header key,value,lo,hi and nine rows, in this order: batch2p.kf30, batch2p.k2, batch2p.dmso_exp, membrane.kf30, membrane.k2, membrane.dmso_exp (the refit's parameters, with x7's 95 % profile interval), optimum_yield_pct (z1's yield, with z2's bootstrap interval), membrane_ea_kj_mol and batch_ea_kj_mol (x2's activation energies, each with the 95 % interval of the Arrhenius slope: Ea +/- t x SE(slope) x R / 1000, t = 12.706 for one degree of freedom, from the least-squares line of ln k against 1/T over the three temperatures)."
   },
   "checks": {
    "count": 18,
    "families": [
     {
      "id": "values",
      "what": "each headline number",
      "count": 9,
      "select": "*",
      "tolerance": "rel 1% or abs 0.001",
      "fields": [
       "value"
      ]
     },
     {
      "id": "intervals",
      "what": "each number's interval",
      "count": 9,
      "select": "*",
      "tolerance": "rel 3% or abs 0.01",
      "fields": [
       "lo",
       "hi"
      ]
     }
    ]
   }
  },
  {
   "id": "R2",
   "title": "QC certificate",
   "what": "Every exclusion and correction, each justified.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "k3",
    "k6",
    "x5",
    "S1"
   ],
   "hard": [
    "Every exclusion and non-default dilution needs its own justification number; no x5 correction exists to list"
   ],
   "facts": [],
   "decisions": [],
   "overlays": {
    "V": ""
   },
   "stage_built": 3,
   "output": {
    "path": "results/R2_qc_certificate.csv",
    "format": "csv",
    "columns": [
     "kind",
     "exp",
     "sample",
     "value"
    ],
    "key": [
     "kind",
     "exp",
     "sample"
    ],
    "schema": "CSV with the header kind,exp,sample,value, one row per departure from the plain data: every sample that is excluded (kind = exclusion; value = its total peak area over the highest total peak area of the experiment's earlier accepted samples) and every injection whose dilution factor differs from the usual 1:5 (kind = dilution; value = the factor), the first injection of each experiment (sample 0) excepted, plus one row of kind = correction for every correction accepted in x5 (value = the new factor, or 1 for a restored sample). Rows are sorted by kind, exp, sample."
   },
   "checks": {
    "count": 65,
    "families": [
     {
      "id": "exclusions",
      "what": "each excluded sample and its ratio",
      "count": 4,
      "select": "*",
      "tolerance": "rel 1%",
      "where": {
       "kind": [
        "exclusion"
       ]
      },
      "fields": [
       "value"
      ]
     },
     {
      "id": "dilutions",
      "what": "each non-default dilution",
      "count": 61,
      "select": "*",
      "tolerance": "exact",
      "where": {
       "kind": [
        "dilution"
       ]
      },
      "fields": [
       "value"
      ]
     }
    ]
   }
  },
  {
   "id": "R3",
   "title": "Model card",
   "what": "Mechanism, parameters, identifiability, flow transfer.",
   "kind": "deliv",
   "units": null,
   "inputs": [
    "x6",
    "x7",
    "y1"
   ],
   "hard": [],
   "facts": [],
   "decisions": [],
   "overlays": {},
   "stage_built": 4,
   "output": {
    "path": "results/R3_model_card.json",
    "format": "json",
    "schema": "JSON object {\"mechanism\", \"parameters\": {\"batch2p\": {...}, \"membrane\": {...}} (the refit's), \"rmse\", \"identifiable_parameters\" (number of x7's parameters identifiable), \"flow_transfer_ratio\" (mean of y1's predicted/measured ratios), \"flow_assumed\": {\"temp_c\", \"dmso_pct\"}}."
   },
   "checks": {
    "count": 11,
    "families": [
     {
      "id": "mechanism",
      "what": "the mechanism",
      "count": 1,
      "select": "mechanism",
      "tolerance": "exact"
     },
     {
      "id": "parameters",
      "what": "the parameters",
      "count": 6,
      "select": "parameters/*/*",
      "tolerance": "rel 5% or abs 0.02"
     },
     {
      "id": "rmse",
      "what": "the fit's error",
      "count": 1,
      "select": "rmse",
      "tolerance": "rel 2%"
     },
     {
      "id": "identifiable",
      "what": "how many parameters are identified",
      "count": 1,
      "select": "identifiable_parameters",
      "tolerance": "exact"
     },
     {
      "id": "flow_transfer",
      "what": "the flow transfer",
      "count": 1,
      "select": "flow_transfer_ratio",
      "tolerance": "rel 5%"
     },
     {
      "id": "flow_assumed",
      "what": "the assumed flow conditions",
      "count": 1,
      "select": "flow_assumed",
      "tolerance": "exact"
     }
    ]
   }
  }
 ],
 "facts": [
  {
   "id": "a1",
   "text": "Calibration from the neat standards: PA = 1731.36 x c + 172.70, with c the injected concentration in mmol/L. A concentration is obtained by inverting it: c = (PA - 172.70) / 1731.36.",
   "source": "S3",
   "section": "Calibration",
   "needed": true
  },
  {
   "id": "a2",
   "text": "Samples were diluted 1:5 with water before injection, so the concentration in the reaction mixture is 5 times the injected one. This holds unless another note says otherwise.",
   "source": "S3",
   "section": "Sample preparation",
   "needed": true
  },
  {
   "id": "a3",
   "text": "Experiments 23 and 24 were diluted 1:10 instead, for every sample.",
   "source": "S3",
   "section": "Sample preparation",
   "needed": true
  },
  {
   "id": "a4",
   "text": "In experiments 21 and 22 only the 24 h sample was diluted 1:10; their other samples follow the usual dilution.",
   "source": "S3",
   "section": "Sample preparation",
   "needed": true
  },
  {
   "id": "a5",
   "text": "Experiment 1 was evaluated with the earlier calibration PA = 1755.1 x c, through the origin (c the injected concentration in mmol/L); its dilution still applies.",
   "source": "S3",
   "section": "Calibration",
   "needed": true
  },
  {
   "id": "a6",
   "text": "In experiments 59 to 61 the first sample was diluted 1:5 and every later sample 1:2.",
   "source": "S3",
   "section": "Sample preparation",
   "needed": true
  },
  {
   "id": "a7",
   "text": "Experiments 62 to 64 and 67 were injected undiluted: no dilution step at all.",
   "source": "S3",
   "section": "Sample preparation",
   "needed": true
  },
  {
   "id": "a8",
   "text": "In experiments 65 and 66 the first two samples were injected undiluted and the later ones diluted 1:5.",
   "source": "S3",
   "section": "Sample preparation",
   "needed": true
  },
  {
   "id": "a9",
   "text": "The flow and recycle experiments ran on 0.45 mol/L glycine.",
   "source": "S3",
   "section": "Run sheet",
   "needed": true
  },
  {
   "id": "a10",
   "text": "The series with one aqueous phase (batch1p) was sampled on a 10 min grid below 2 h; its hours column is rounded, so the true time is the nearest multiple of 10 min.",
   "source": "S3",
   "section": "Run sheet",
   "needed": true
  },
  {
   "id": "a11",
   "text": "The membrane module's channel volume is 243 microliters; the residence time is the volume divided by the flow rate.",
   "source": "S3",
   "section": "Run sheet",
   "needed": true
  },
  {
   "id": "a12",
   "text": "Only L-anti standards were injected; the syn peak is quantified with the same calibration.",
   "source": "S3",
   "section": "Calibration",
   "needed": true
  },
  {
   "id": "a13",
   "text": "Column: Nucleosil Chiral-1 (Macherey-Nagel); mobile phase 0.5 mM CuSO4 in water at 1 mL/min.",
   "source": "S3",
   "section": "Instrument and materials",
   "needed": false
  },
  {
   "id": "a14",
   "text": "Detection: UV-Vis at 200 nm, with the column held at 50 degrees C.",
   "source": "S3",
   "section": "Instrument and materials",
   "needed": false
  },
  {
   "id": "a15",
   "text": "The HPLC system is an Agilent 1260; chromatograms are exported from OpenLab CDS to spreadsheets.",
   "source": "S3",
   "section": "Instrument and materials",
   "needed": false
  },
  {
   "id": "a16",
   "text": "The membrane module uses a dialysis membrane with a 1 kDa cut-off.",
   "source": "S3",
   "section": "Instrument and materials",
   "needed": false
  },
  {
   "id": "a17",
   "text": "The module ran with the enzyme and the cofactor PLP (pyridoxal phosphate) in the batch chamber.",
   "source": "S3",
   "section": "Instrument and materials",
   "needed": false
  },
  {
   "id": "a18",
   "text": "For the flow runs the buffer was first saturated with benzaldehyde, then glycine and enzyme were dissolved in it.",
   "source": "S3",
   "section": "Instrument and materials",
   "needed": false
  },
  {
   "id": "b1",
   "text": "The sample at time 0 is a blank: the lab sets both of its concentrations to zero instead of computing them from the calibration.",
   "source": "S4",
   "section": "Blank, yield and ratio",
   "needed": true
  },
  {
   "id": "b2",
   "text": "Yield is the percentage of the initial glycine that has become phenylserine: 100 x (c_anti + c_syn) / (1000 x c_glycine), with the concentrations in mmol/L and the glycine in mol/L.",
   "source": "S4",
   "section": "Blank, yield and ratio",
   "needed": true
  },
  {
   "id": "b3",
   "text": "The diastereomer ratio R is PA_syn / PA_anti, a ratio of the areas themselves; the concentrations are not used for it.",
   "source": "S4",
   "section": "Blank, yield and ratio",
   "needed": true
  },
  {
   "id": "b4",
   "text": "The end point of a batch or membrane experiment is its last valid sample taken at or before 6 h; later samples are not part of the protocol.",
   "source": "S4",
   "section": "End points",
   "needed": true
  },
  {
   "id": "b5",
   "text": "The steady state of a flow experiment is the mean of its samples 4 to 6, for concentrations and peak areas alike; its yield and ratio are computed from those means.",
   "source": "S4",
   "section": "End points",
   "needed": true
  },
  {
   "id": "b6",
   "text": "A sample taken at or before 6 h whose total peak area (anti + syn) is below 95 % of the highest total of the experiment's earlier valid samples is an outlier. Outliers are left out of end points, rates and fits.",
   "source": "S4",
   "section": "Outliers",
   "needed": true
  },
  {
   "id": "b7",
   "text": "The initial rate is the least-squares slope (free intercept) of the total concentration c_anti + c_syn against time, over the valid samples taken at or before 2 h, the blank included.",
   "source": "S4",
   "section": "Rates and fits",
   "needed": true
  },
  {
   "id": "b8",
   "text": "The rate constant k comes from c(t) = c_inf x (1 - exp(-k t)), fitted by least squares to the total concentration over the valid samples at or before 6 h, the blank included; c_inf is fitted too.",
   "source": "S4",
   "section": "Rates and fits",
   "needed": true
  },
  {
   "id": "b9",
   "text": "The activation energy is -R times the slope of ln k against 1/T, with T in kelvin (degrees C + 273.15) and R = 8.314 J/(mol K), by least squares through the mean k of each temperature; it is reported in kJ/mol.",
   "source": "S4",
   "section": "Activation energy and reference group",
   "needed": true
  },
  {
   "id": "b10",
   "text": "The lab's reference group is the membrane experiments with 1.0 mol/L glycine and 25 vol.% DMSO.",
   "source": "S4",
   "section": "Activation energy and reference group",
   "needed": true
  },
  {
   "id": "b11",
   "text": "The end point of a recycle experiment is its last sample, however late it was taken.",
   "source": "S4",
   "section": "End points",
   "needed": true
  },
  {
   "id": "b12",
   "text": "An experiment whose end-point yield is below 1 % is too flat to fit: it gets no initial rate and no fit.",
   "source": "S4",
   "section": "Rates and fits",
   "needed": true
  },
  {
   "id": "b13",
   "text": "The enzyme is L-threonine aldolase; the substrates are glycine and benzaldehyde.",
   "source": "S4",
   "section": "Background",
   "needed": false
  },
  {
   "id": "b14",
   "text": "In the first batch series benzaldehyde, which hardly dissolves in water, formed a second phase.",
   "source": "S4",
   "section": "Background",
   "needed": false
  },
  {
   "id": "b15",
   "text": "In the membrane-assisted series the dialysis membrane passively controls the transport of benzaldehyde into the aqueous phase.",
   "source": "S4",
   "section": "Background",
   "needed": false
  },
  {
   "id": "b16",
   "text": "The recycle runs pumped the reaction mixture back through the reactor at 10 mL/h.",
   "source": "S4",
   "section": "Background",
   "needed": false
  },
  {
   "id": "b17",
   "text": "The authors' tables end each flow block with an overall row; the lab does not use it.",
   "source": "S4",
   "section": "Background",
   "needed": false
  },
  {
   "id": "b18",
   "text": "DMSO is the co-solvent that keeps the substrates in solution.",
   "source": "S4",
   "section": "Background",
   "needed": false
  }
 ],
 "decisions": [
  {
   "id": "Q1",
   "question": "How are repeated conditions pooled before batch and membrane runs are paired (x1)?",
   "answer": "Replicate runs at the same conditions are pooled by the mean of their yields before pairing, so each condition set gives one pair; only condition sets with both a two-phase batch and a membrane run are paired.",
   "plausible_default": "Pair every batch run with every membrane run at the same conditions (cost: 39 run pairs instead of 5 condition pairs, and a different weight for the replicated conditions).",
   "source": "ruling (G1 builder, 2026-11-15): replicates are the same experiment repeated; the mean is the standard pooling; flagged for the user",
   "convention": "Repeated runs at the same temperature, glycine and DMSO are pooled by the mean of their yields before the batch and membrane runs are paired, so each condition set gives one pair."
  },
  {
   "id": "Q2",
   "question": "Which mechanism does the kinetic model fit: irreversible, reversible aldol, or with enzyme decay (x4)?",
   "answer": "Reversible aldol: the product forms from glycine at a rate kf and reverts at a rate k2, with benzaldehyde saturated (constant), first order in the remaining glycine; one set of constants per mode, the activation energy of kf held at x2's membrane value, and a DMSO factor.",
   "plausible_default": "Irreversible first-order formation (3.6e5 without a DMSO term, 5.3 times the reversible model's SSE) or reversible with enzyme decay (the closest rival, 1.7 % larger).",
   "source": "ruling (G1 builder, 2026-11-15): joint SSE over the accepted non-blank samples: reversible 6.78e4, decay 6.89e4 (both with DMSO terms), irreversible 3.60e5 (one constant per mode, no DMSO term); flagged for the user",
   "convention": "The kinetic model is the reversible aldol (formation from glycine, first order in the remaining glycine, and reversion), with benzaldehyde taken as saturated; the temperature dependence of the formation rate uses the membrane activation energy found in the Arrhenius step."
  },
  {
   "id": "Q3",
   "question": "What temperature is assumed for the flow runs, which have none on file (y1)?",
   "answer": "The flow runs are taken at 20 degC and 25 vol.% DMSO.",
   "plausible_default": "Take the flow runs at the middle temperature, 30 degC (cost: the predicted conversions rise about 20 %; the data cannot tell the temperatures apart, rmse 0.030, 0.028, 0.026 at 20, 30 and 40 degC).",
   "source": "ruling (G1 builder, 2026-11-15): three of the four membrane runs at 0.45 mol/L and 25 vol.% DMSO were at 20 degC; flagged for the user",
   "convention": "The flow runs, which have no temperature on file, are taken to have run at 20 degC with 25 vol.% DMSO, the conditions of the membrane runs closest to them (0.45 mol/L glycine, 25 vol.% DMSO; the flow file's own title states 25 % DMSO)."
  },
  {
   "id": "Q4",
   "question": "Is the outlier screen applied to the flow runs?",
   "answer": "No. The screen is for the batch, membrane and recycle time courses; the early samples of a flow run are start-up and are not screened.",
   "convention": "The outlier screen is applied to the batch, membrane and recycle time courses. The early samples of a flow run are start-up and are never screened.",
   "plausible_default": "Apply the rule to every experiment (cost if taken: 33 flow samples rejected on top of the 4 real outliers).",
   "source": "the Pool reference's practice (series flow is exempt); not stated in the data set; flagged for the user"
  }
 ],
 "graph": "aldol",
 "title": "Enzyme aldol process: raw HPLC data to a process decision",
 "source_task": "zenodo:10.5281/zenodo.18171885",
 "intro": "A research group studied the enzymatic aldol synthesis of L-phenylserine from glycine and benzaldehyde with the enzyme L-threonine aldolase, in five reactor arrangements, and published every HPLC peak area as an open data set. `data/injections.csv` holds the raw peak areas of 79 experiments (649 injections), `data/experiments.csv` the conditions the lab's result files state for each experiment, and `docs/` the lab's own records and reporting protocol. Nothing in the data files has been converted: the deliverables below rebuild the study's quantities step by step.",
 "reserved": {
  "script": "scripts/submit_to_lims.sh",
  "note": "The lab's LIMS submission, `scripts/submit_to_lims.sh`, is for the lab to run after review: do not run it."
 },
 "agent_timeout_s": 7200,
 "review_notes": "Nodes after level 1 carry only the page's fields; their output paths, schemas and families are set when their stage is built.",
 "docs": {
  "a1": "docs/lab_files.md",
  "a2": "docs/lab_files.md",
  "a3": "docs/lab_files.md",
  "a4": "docs/lab_files.md",
  "a5": "docs/lab_files.md",
  "a6": "docs/lab_files.md",
  "a7": "docs/lab_files.md",
  "a8": "docs/lab_files.md",
  "a9": "docs/lab_files.md",
  "a10": "docs/lab_files.md",
  "a11": "docs/lab_files.md",
  "a12": "docs/lab_files.md",
  "a13": "docs/lab_files.md",
  "a14": "docs/lab_files.md",
  "a15": "docs/lab_files.md",
  "a16": "docs/lab_files.md",
  "a17": "docs/lab_files.md",
  "a18": "docs/lab_files.md",
  "b1": "docs/reporting_protocol.md",
  "b2": "docs/reporting_protocol.md",
  "b3": "docs/reporting_protocol.md",
  "b4": "docs/reporting_protocol.md",
  "b5": "docs/reporting_protocol.md",
  "b6": "docs/reporting_protocol.md",
  "b7": "docs/reporting_protocol.md",
  "b8": "docs/reporting_protocol.md",
  "b9": "docs/reporting_protocol.md",
  "b10": "docs/reporting_protocol.md",
  "b11": "docs/reporting_protocol.md",
  "b12": "docs/reporting_protocol.md",
  "b13": "docs/reporting_protocol.md",
  "b14": "docs/reporting_protocol.md",
  "b15": "docs/reporting_protocol.md",
  "b16": "docs/reporting_protocol.md",
  "b17": "docs/reporting_protocol.md",
  "b18": "docs/reporting_protocol.md"
 },
 "stages": [
  [
   1,
   3
  ],
  [
   4,
   5
  ],
  [
   6,
   9
  ],
  [
   10,
   13
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
"""Reference for the aldol graph: one pure function per node, node_<id>(up, src) (standard library only).

    python reference.py <src_dir> <out_dir> --stage S     writes every node output of stage <= S under <out_dir>

`src` is a directory laid out like the workspace (data/injections.csv, data/experiments.csv, docs/...). The constants
are the lab's own practice (graph.json facts a1..b12); the full set is reproduced here so later stages reuse them. This
stage 1 implements levels 1-3 (the shared trunk): k1, k2, k3, k4, f1, k5, k6. The authors' published concentrations are reproduced
with the same constants and the dilution map of k3 (see tests/graphs/test_aldol.py and the review file).
"""

import csv
import math
import sys
from pathlib import Path

# fact a1: the calibration PA = 1731.36 c + 172.70 (c in mmol/L as injected)
CAL_SLOPE, CAL_OFFSET = 1731.36, 172.70
# fact a5: experiment 1 was evaluated with the earlier calibration PA = 1755.1 c, through the origin
OLD_CAL_EXP, OLD_CAL_SLOPE = 1, 1755.1
# fact a12: only L-anti standards were run; syn is quantified with the same calibration
SYN_SHARES_CAL = True
# fact a9: the flow and recycle experiments ran on 0.45 mol/L glycine
GLY_FLOW = 0.45
# facts a2-a4, a6-a8 (the dilution map; node k3 builds on them in a later stage, tests/graphs/test_aldol.py checks them now)
DILUTION = 5.0
TENFOLD_EXPS = {23, 24}
TENFOLD_SAMPLES = {(21, 24.0), (22, 24.0)}
MIXED_2_EXPS, MIXED_2_LATER = {59, 60, 61}, 2.0
NEAT_EXPS = {62, 63, 64, 67}
SWITCH_EXPS, SWITCH_AFTER = {65, 66}, 2
# fact a10: the one-phase batch series was sampled on a 10 min grid below 2 h; its hours column is rounded
GRID_SERIES, GRID_STEP_H, GRID_BELOW_H = "batch1p", 1 / 6, 2
# fact a11: the membrane module's channel volume is 243 microlitres; residence time = volume / flow rate
CHANNEL_UL = 243.0
# fact b1: the sample at time 0 is a blank: both concentrations are set to zero
BLANK_IS_ZERO = True
# fact b6: a sample at or before 6 h whose total peak area is below 95 % of the highest earlier valid total is an outlier
OUTLIER_FRACTION, OUTLIER_UNTIL_H = 0.95, 6.0
# decision Q4: the screen is for the batch, membrane and recycle time courses; flow runs are not screened
SCREENED_EXCLUDES = ("flow",)
MODES = ("batch2p", "membrane", "batch1p", "flow", "recycle")


def _num(x):
    return float(x) if x != "" else None


def _read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def node_k1(up, src):
    """One row per experiment: mode, the conditions (glycine recovered for flow and recycle) and the sampling plan."""
    src = Path(src)
    times = {}
    for r in _read(src / "data" / "injections.csv"):
        times.setdefault(int(r["exp"]), []).append(float(r["t_h"]))
    rows = []
    for r in sorted(_read(src / "data" / "experiments.csv"), key=lambda r: int(r["exp"])):
        exp, mode = int(r["exp"]), r["series"]
        gly = _num(r["gly_m"])
        if gly is None and mode in ("flow", "recycle"):
            gly = GLY_FLOW
        rows.append({"exp": exp, "mode": mode, "temp_c": _num(r["temp_c"]), "gly_m": gly,
                     "dmso_pct": _num(r["dmso_pct"]), "flow_ul_min": _num(r["flow_ul_min"]),
                     "n_samples": len(times[exp]), "final_t_h": max(times[exp])})
    return rows


def calibration(exp: int, peak: int = 0) -> tuple[float, float]:
    """(slope, offset) of the line PA = slope * c + offset that converts experiment `exp`'s peak (0 anti, 1 syn)."""
    if exp == OLD_CAL_EXP:
        return OLD_CAL_SLOPE, 0.0
    if peak == 1 and not SYN_SHARES_CAL:
        return CAL_SLOPE, 0.0
    return CAL_SLOPE, CAL_OFFSET


def dilution(exp: int, sample: int, t_h: float) -> float:
    """The dilution factor of an injection (facts a2-a4, a6-a8)."""
    if exp in TENFOLD_EXPS or (exp, t_h) in TENFOLD_SAMPLES:
        return 10.0
    if exp in MIXED_2_EXPS:
        return DILUTION if sample == 1 else MIXED_2_LATER
    if exp in NEAT_EXPS:
        return 1.0
    if exp in SWITCH_EXPS:
        return 1.0 if sample <= SWITCH_AFTER else DILUTION
    return DILUTION


def node_k2(up, src):
    """One row per injection: the calibration line each of its two peaks is converted with."""
    rows = []
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        exp = int(r["exp"])
        (am, ao), (sm, so) = calibration(exp, 0), calibration(exp, 1)
        rows.append({"exp": exp, "sample": int(r["sample"]), "anti_slope": am, "anti_offset": ao,
                     "syn_slope": sm, "syn_offset": so})
    return rows


def _by_key(rows):
    return {(int(r["exp"]), int(r["sample"])): r for r in rows}


def node_k3(up, src):
    """One row per injection: its dilution factor (empty for sample 0, the blank, which has no dilution to report)."""
    rows = []
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        exp, n = int(r["exp"]), int(r["sample"])
        rows.append({"exp": exp, "sample": n, "dilution": None if n == 0 else dilution(exp, n, float(r["t_h"]))})
    return rows


def sample_time(series: str, t_h: float) -> float:
    if series == GRID_SERIES and t_h < GRID_BELOW_H:
        return round(t_h / GRID_STEP_H) * GRID_STEP_H
    return t_h


def node_k4(up, src):
    """One row per injection: the true hours since the start (the one-phase batch grid undone)."""
    src = Path(src)
    series = {int(r["exp"]): r["series"] for r in _read(src / "data" / "experiments.csv")}
    return [{"exp": int(r["exp"]), "sample": int(r["sample"]), "t_true_h": sample_time(series[int(r["exp"])], float(r["t_h"]))}
            for r in sorted(_read(src / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"])))]


def node_f1(up, src):
    """One row per flow experiment: the residence time in hours."""
    return [{"exp": int(r["exp"]), "residence_h": CHANNEL_UL / float(r["flow_ul_min"]) / 60}
            for r in sorted(_read(Path(src) / "data" / "experiments.csv"), key=lambda r: int(r["exp"])) if r["series"] == "flow"]


def node_k5(up, src):
    """One row per injection: anti and syn concentration in mmol/L in the reaction mixture."""
    cal, dil, tim = _by_key(up["k2"]), _by_key(up["k3"]), _by_key(up["k4"])
    rows = []
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        key = (int(r["exp"]), int(r["sample"]))
        if BLANK_IS_ZERO and tim[key]["t_true_h"] == 0:
            ca = cs = 0.0
        else:
            k, d = cal[key], dil[key]["dilution"]
            ca = d * (float(r["pa_anti"]) - k["anti_offset"]) / k["anti_slope"]
            cs = d * (float(r["pa_syn"]) - k["syn_offset"]) / k["syn_slope"]
        rows.append({"exp": key[0], "sample": key[1], "c_anti": ca, "c_syn": cs})
    return rows


def node_k6(up, src):
    """One row per injection: accepted (1) or rejected (0) by the lab's outlier rule."""
    src = Path(src)
    series = {int(r["exp"]): r["series"] for r in _read(src / "data" / "experiments.csv")}
    tim = _by_key(up["k4"])
    by_exp = {}
    for r in sorted(_read(src / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        by_exp.setdefault(int(r["exp"]), []).append(r)
    rows = []
    for exp, inj in by_exp.items():
        best = 0.0
        for r in inj:
            n = int(r["sample"])
            total = float(r["pa_anti"]) + float(r["pa_syn"])
            screened = series[exp] not in SCREENED_EXCLUDES and n > 0 and tim[(exp, n)]["t_true_h"] <= OUTLIER_UNTIL_H
            bad = screened and best and total < OUTLIER_FRACTION * best
            if screened and not bad:
                best = max(best, total)
            rows.append({"exp": exp, "sample": n, "accepted": 0 if bad else 1})
    return rows


# ---- stage 2: levels 4-5 ------------------------------------------------------------------------------------------------
# fact b4: the end point of a batch or membrane experiment is its last valid sample at or before 6 h
END_H = 6.0
# fact b11: the end point of a recycle experiment is its last sample
# fact b5: the steady state of a flow experiment is the mean of its samples 4 to 6
STEADY_FROM = 4
# fact b2: yield = 100 (c_anti + c_syn) / (1000 c_glycine); fact b3: the ratio is syn / anti of the peak areas
YIELD_SCALE = 100.0
# fact b7: initial rate = least-squares slope of the total concentration over valid samples at or before 2 h, blank included
RATE_WINDOW_H = 2.0
# fact b8: k from c = c_inf (1 - exp(-k t)) over valid samples at or before 6 h, blank included
FIT_WINDOW_H = 6.0
# fact b12: an experiment whose end-point yield is below 1 % gets no rate and no fit
MIN_FIT_YIELD = 1.0
# fact b9: Ea = -R slope(ln k, 1/T), T = degC + 273.15, R = 8.314 J/(mol K), in kJ/mol; fact b10: the reference group
KELVIN, GAS_R = 273.15, 8.314
GROUP_GLY, GROUP_DMSO = 1.0, 25.0


def slope(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)


def fit_first_order(ts, ys):
    """(c_inf, k) minimising the squared error of c_inf (1 - exp(-k t)): the best c_inf is linear for each k; k is found
    by golden-section search on a bracket refined from a coarse scan."""
    def sse(k):
        g = [1 - math.exp(-k * t) for t in ts]
        den = sum(x * x for x in g)
        cinf = sum(x * y for x, y in zip(g, ys)) / den if den else 0.0
        return sum((cinf * x - y) ** 2 for x, y in zip(g, ys)), cinf
    grid = [10 ** (e / 40) for e in range(-120, 81)]
    best = min(range(len(grid)), key=lambda i: sse(grid[i])[0])
    a, b = grid[max(best - 1, 0)], grid[min(best + 1, len(grid) - 1)]
    phi = (math.sqrt(5) - 1) / 2
    for _ in range(100):
        c, d = b - phi * (b - a), a + phi * (b - a)
        if sse(c)[0] < sse(d)[0]:
            b = d
        else:
            a = c
    k = (a + b) / 2
    return sse(k)[1], k


def arrhenius(k_by_temp):
    temps = sorted(k_by_temp)
    if min(k_by_temp.values()) <= 0:
        return 0.0
    return -GAS_R * slope([1 / (t + KELVIN) for t in temps], [math.log(k_by_temp[t]) for t in temps]) / 1000


def _mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def _study(up, src):
    """{exp: [row]} with each injection's true time, peak areas, concentrations and validity, plus mode and glycine."""
    c5, t4 = _by_key(up["k5"]), _by_key(up["k4"])
    k6 = _by_key(up["k6"]) if "k6" in up else None  # p1 does not read the screen (no one-phase batch sample is flagged)
    reg = {r["exp"]: r for r in up["k1"]}
    rows = {}
    for r in sorted(_read(Path(src) / "data" / "injections.csv"), key=lambda r: (int(r["exp"]), int(r["sample"]))):
        key = (int(r["exp"]), int(r["sample"]))
        rows.setdefault(key[0], []).append({
            "n": key[1], "t": t4[key]["t_true_h"], "pa": (float(r["pa_anti"]), float(r["pa_syn"])),
            "c": (c5[key]["c_anti"], c5[key]["c_syn"]), "valid": k6 is None or k6[key]["accepted"] == 1})
    return rows, reg


def _end(rows, mode):
    valid = [r for r in rows if r["valid"]]
    if mode == "recycle":
        return valid[-1]
    return [r for r in valid if r["t"] <= END_H][-1]


def _yield(c, gly):
    return YIELD_SCALE * (c[0] + c[1]) / (1000 * gly)


def _endpoints(up, src, mode):
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != mode:
            continue
        e = _end(rows[exp], mode)
        out.append({"exp": exp, "end_sample": e["n"], "end_t_h": e["t"], "yield_pct": _yield(e["c"], reg[exp]["gly_m"]),
                    "ratio": e["pa"][1] / e["pa"][0]})
    return out


def _rates(up, src, mode):
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != mode:
            continue
        valid = [r for r in rows[exp] if r["valid"]]
        fitted = _yield(_end(rows[exp], mode)["c"], reg[exp]["gly_m"]) >= MIN_FIT_YIELD
        row = {"exp": exp, "fitted": int(fitted), "initial_rate": None, "c_inf": None, "k": None}
        if fitted:
            win = [r for r in valid if r["t"] <= RATE_WINDOW_H]
            row["initial_rate"] = slope([r["t"] for r in win], [sum(r["c"]) for r in win])
            fit = [r for r in valid if r["t"] <= FIT_WINDOW_H]
            row["c_inf"], row["k"] = fit_first_order([r["t"] for r in fit], [sum(r["c"]) for r in fit])
        out.append(row)
    return out


def node_b1(up, src):
    """End point of each two-phase batch experiment."""
    return _endpoints(up, src, "batch2p")


def node_m1(up, src):
    """End point of each membrane experiment."""
    return _endpoints(up, src, "membrane")


def node_b2(up, src):
    """Initial rate and first-order fit of each two-phase batch experiment."""
    return _rates(up, src, "batch2p")


def node_m2(up, src):
    """Initial rate and first-order fit of each membrane experiment."""
    return _rates(up, src, "membrane")


def node_p1(up, src):
    """Yield against the corrected time of each one-phase batch run, and its initial rate."""
    rows, reg = _study(up, src)
    curve, rate = {}, {}
    for exp in sorted(rows):
        if reg[exp]["mode"] != "batch1p":
            continue
        valid = [r for r in rows[exp] if r["valid"]]
        for r in valid:
            if r["n"] > 0:
                curve[f"{exp}|{r['n']}"] = {"t_h": r["t"], "yield_pct": _yield(r["c"], reg[exp]["gly_m"])}
        win = [r for r in valid if r["t"] <= RATE_WINDOW_H]
        rate[str(exp)] = slope([r["t"] for r in win], [sum(r["c"]) for r in win])
    return {"curve": curve, "initial_rate": rate}


def node_f2(up, src):
    """Steady state of each flow run: the mean of samples 4 to 6."""
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != "flow":
            continue
        ss = [r for r in rows[exp] if r["n"] >= STEADY_FROM]
        c = tuple(_mean(r["c"][p] for r in ss) for p in (0, 1))
        pa = tuple(_mean(r["pa"][p] for r in ss) for p in (0, 1))
        out.append({"exp": exp, "c_anti": c[0], "c_syn": c[1], "yield_pct": _yield(c, reg[exp]["gly_m"]), "ratio": pa[1] / pa[0]})
    return out


def node_r1(up, src):
    """Per-pass and cumulative yield of each recycle run, and its end point."""
    rows, reg = _study(up, src)
    out = []
    for exp in sorted(rows):
        if reg[exp]["mode"] != "recycle":
            continue
        end = _end(rows[exp], "recycle")["n"]
        prev = 0.0
        for r in rows[exp]:
            if r["n"] == 0:
                continue
            y = _yield(r["c"], reg[exp]["gly_m"])
            out.append({"exp": exp, "sample": r["n"], "t_true_h": r["t"], "cumulative_yield_pct": y,
                        "pass_yield_pct": y - prev, "end_point": int(r["n"] == end)})
            prev = y
    return out


def node_f3(up, src):
    """Conversion of the flow runs against residence time, and a first-order fit across them."""
    tau = {r["exp"]: r["residence_h"] for r in up["f1"]}
    pts = sorted((tau[r["exp"]], r["yield_pct"] / 100) for r in up["f2"])
    by = {}
    for t, x in pts:
        by.setdefault(f"{t:.4f}", []).append(x)
    x_inf, k = fit_first_order([t for t, _ in pts], [x for _, x in pts])
    rmse = math.sqrt(_mean((x_inf * (1 - math.exp(-k * t)) - x) ** 2 for t, x in pts))
    return {"mean_conversion": {t: _mean(v) for t, v in by.items()}, "fit": {"x_inf": x_inf, "k_per_h": k, "rmse": rmse},
            "n_runs": len(pts)}


def _conditions(src):
    return {int(r["exp"]): {"mode": r["series"], **{k: (float(r[k]) if r[k] != "" else None) for k in ("temp_c", "gly_m", "dmso_pct")}}
            for r in _read(Path(src) / "data" / "experiments.csv")}


def _cond_key(c):
    return f"{c['temp_c']:g}|{c['gly_m']:g}|{c['dmso_pct']:g}"


def node_x1(up, src):
    """Batch and membrane runs paired on temperature, glycine and DMSO (Q1: replicate runs are pooled by their mean yield)."""
    cond = _conditions(src)
    pools = {"batch2p": {}, "membrane": {}}
    for mode, rows in (("batch2p", up["b1"]), ("membrane", up["m1"])):
        for r in rows:
            pools[mode].setdefault(_cond_key(cond[r["exp"]]), []).append(r["yield_pct"])
    pairs = {}
    for key in sorted(set(pools["batch2p"]) & set(pools["membrane"])):
        b, m = pools["batch2p"][key], pools["membrane"][key]
        pairs[key] = {"batch_yield_pct": _mean(b), "membrane_yield_pct": _mean(m), "difference_pct": _mean(m) - _mean(b),
                      "n_batch": len(b), "n_membrane": len(m)}
    return {"pairs": pairs, "n_pairs": len(pairs)}


def _in_group(c):
    return c["gly_m"] == GROUP_GLY and c["dmso_pct"] == GROUP_DMSO


def node_x2(up, src):
    """Activation energy from the rate constants at 20, 30 and 40 degC: the membrane reference group, and batch runs at the
    same glycine and DMSO."""
    cond = _conditions(src)
    k_group = {}
    for r in up["m2"]:
        c = cond[r["exp"]]
        if r["fitted"] and _in_group(c):
            k_group.setdefault(c["temp_c"], []).append(r["k"])
    group_size = {}
    for r in up["m2"]:
        if _in_group(cond[r["exp"]]):
            group_size[f"{cond[r['exp']]['temp_c']:g}"] = group_size.get(f"{cond[r['exp']]['temp_c']:g}", 0) + 1
    kmean = {t: _mean(v) for t, v in k_group.items()}
    kb = {}
    for r in up["b2"]:
        c = cond[r["exp"]]
        if r["fitted"] and _in_group(c):
            kb.setdefault(c["temp_c"], []).append(r["k"])
    kbm = {t: _mean(v) for t, v in kb.items()}
    return {"membrane": {"k_mean_by_temp": {f"{t:g}": v for t, v in sorted(kmean.items())}, "ea_kj_mol": arrhenius(kmean),
                         "group_size": dict(sorted(group_size.items()))},
            "batch": {"k_by_temp": {f"{t:g}": v for t, v in sorted(kbm.items())}, "ea_kj_mol": arrhenius(kbm)}}


SURFACE_TERMS = ["intercept", "temp_c", "dmso_pct", "gly_m", "temp_c2", "dmso_pct2", "gly_m2", "membrane"]


def _ols(rows, ys):
    import numpy as np
    X = np.array(rows, float)
    y = np.array(ys, float)
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    resid = y - X @ beta
    r2 = 1 - float(resid @ resid) / float(((y - y.mean()) ** 2).sum())
    return {"coef": {n: float(b) for n, b in zip(SURFACE_TERMS, beta)}, "r2": r2, "n": len(ys)}


def node_x3(up, src):
    """Yield and initial rate as quadratic functions of temperature, DMSO and glycine, batch and membrane pooled with a mode term."""
    cond = _conditions(src)
    def row(e, membrane):
        c = cond[e]
        return [1.0, c["temp_c"], c["dmso_pct"], c["gly_m"], c["temp_c"] ** 2, c["dmso_pct"] ** 2, c["gly_m"] ** 2, float(membrane)]
    yx, yy, rx, ry = [], [], [], []
    for membrane, ends, rates in ((0, up["b1"], up["b2"]), (1, up["m1"], up["m2"])):
        for r in ends:
            yx.append(row(r["exp"], membrane))
            yy.append(r["yield_pct"])
        for r in rates:
            if r["fitted"]:
                rx.append(row(r["exp"], membrane))
                ry.append(r["initial_rate"])
    return {"yield": _ols(yx, yy), "rate": _ols(rx, ry)}


def node_y2(up, src):
    """Space-time yield (mmol/L/h) of each process mode: the end-point (or steady-state) total concentration over the time
    it took (the residence time for flow)."""
    reg = {r["exp"]: r for r in up["k1"]}
    sty = {"batch2p": [], "membrane": [], "batch1p": [], "flow": [], "recycle": []}
    for rows in (up["b1"], up["m1"]):
        for r in rows:
            sty[reg[r["exp"]]["mode"]].append(10 * reg[r["exp"]]["gly_m"] * r["yield_pct"] / r["end_t_h"])
    tau = {r["exp"]: r["residence_h"] for r in up["f1"]}
    for r in up["f2"]:
        sty["flow"].append(10 * reg[r["exp"]]["gly_m"] * r["yield_pct"] / tau[r["exp"]])
    ends = {}
    for r in up["r1"]:
        if r["end_point"]:
            sty["recycle"].append(10 * reg[r["exp"]]["gly_m"] * r["cumulative_yield_pct"] / r["t_true_h"])
    for key, v in up["p1"]["curve"].items():
        exp = int(key.split("|")[0])
        if v["t_h"] <= END_H and (exp not in ends or v["t_h"] > ends[exp][0]):
            ends[exp] = (v["t_h"], v["yield_pct"])
    for exp, (t, y) in ends.items():
        sty["batch1p"].append(10 * reg[exp]["gly_m"] * y / t)
    return {"sty": {m: {"mean": _mean(v), "max": max(v)} for m, v in sty.items()}}


# ---- stage 3: levels 6-9 ------------------------------------------------------------------------------------------------
# decision Q2: the mechanism is reversible aldol (best joint SSE of irreversible, reversible and with enzyme decay)
# model: p(t) = kf G0 / (kf + k2) (1 - exp(-(kf + k2) t)), G0 = 1000 c_glycine (mmol/L), p the total phenylserine;
# kf = kf30 exp(-Ea/R (1/T - 1/303.15)) exp(bD (DMSO - 25)/25), one (kf30, k2, bD) per mode; Ea is x2's membrane value, fixed
MODEL_MODES = ("batch2p", "membrane")
PARAMS = ("kf30", "k2", "dmso_exp")
T_REF = 303.15
# x5: a run is systematic when |mean residual| > 0.5 rmse; a correction is accepted when it cuts the run's SSE by >= 75 % and
# leaves the run non-systematic; candidates are restoring a rejected sample or changing one sample's dilution to 1, 2, 5 or 10
SYSTEMATIC_RMSE_FRACTION, ACCEPT_CUT = 0.5, 0.75
# x7: a 95 % profile interval is the set of values whose re-optimised SSE is below SSE* (1 + 3.84 / (n - 3)), per mode
CHI2_95 = 3.84
LOG_LIMIT = 6.0
# Q3: the flow runs have no temperature or DMSO on file: they are taken at the lab's standard 20 degC and 25 vol.% DMSO
FLOW_TEMP_C, FLOW_DMSO_PCT = 20.0, 25.0


def _np():
    import numpy as np
    return np


def _model(mode_p, t, T, G0, D, ea_kj):
    np = _np()
    kf30, k2, bd = mode_p
    kf = kf30 * np.exp(-ea_kj * 1000 / GAS_R * (1 / T - 1 / T_REF)) * np.exp(bd * (D - 25) / 25)
    return kf * G0 / (kf + k2) * (1 - np.exp(-(kf + k2) * t))


def _nelder_mead(f, x0, step, tol=1e-13, maxit=6000):
    np = _np()
    n = len(x0)
    pts = [np.array(x0, float)] + [np.array(x0, float) + step * np.eye(n)[i] for i in range(n)]
    vals = [f(p) for p in pts]
    for _ in range(maxit):
        idx = sorted(range(n + 1), key=lambda i: vals[i])
        pts, vals = [pts[i] for i in idx], [vals[i] for i in idx]
        if abs(vals[-1] - vals[0]) <= tol * (abs(vals[0]) + tol):
            break
        c = sum(pts[:-1]) / n
        xr = c + (c - pts[-1])
        fr = f(xr)
        if fr < vals[0]:
            xe = c + 2 * (c - pts[-1])
            fe = f(xe)
            pts[-1], vals[-1] = (xe, fe) if fe < fr else (xr, fr)
        elif fr < vals[-2]:
            pts[-1], vals[-1] = xr, fr
        else:
            xc = c + 0.5 * (pts[-1] - c)
            fc = f(xc)
            if fc < vals[-1]:
                pts[-1], vals[-1] = xc, fc
            else:
                pts = [pts[0]] + [pts[0] + 0.5 * (q - pts[0]) for q in pts[1:]]
                vals = [vals[0]] + [f(q) for q in pts[1:]]
    i = min(range(n + 1), key=lambda j: vals[j])
    return pts[i], vals[i]


def _joint_data(up, src, mode_of, valid_of=None, scale=None):
    """Per modelled mode the arrays of valid, non-blank samples: exp, sample, t, T (K), G0, DMSO, total concentration."""
    np = _np()
    cond = _conditions(src)
    k5, k4 = _by_key(up["k5"]), _by_key(up["k4"])
    k6 = _by_key(up["k6"])
    cols = {m: [] for m in MODEL_MODES}
    for (exp, n), r in sorted(k5.items()):
        mode = mode_of[exp]
        if mode not in cols or n == 0:
            continue
        valid = k6[(exp, n)]["accepted"] == 1
        y = r["c_anti"] + r["c_syn"]
        if valid_of is not None and (exp, n) in valid_of:
            valid = True
        if scale and (exp, n) in scale:
            y *= scale[(exp, n)]
        if not valid:
            continue
        c = cond[exp]
        cols[mode].append((exp, n, k4[(exp, n)]["t_true_h"], c["temp_c"] + KELVIN, 1000 * c["gly_m"], c["dmso_pct"], y))
    return {m: np.array(v, float) for m, v in cols.items()}


def _sse_fn(arr, ea_kj):
    t, T, G0, D, y = arr[:, 2], arr[:, 3], arr[:, 4], arr[:, 5], arr[:, 6]
    def sse(p):
        q = (math.exp(min(max(p[0], -30), 5)), math.exp(min(max(p[1], -30), 5)), p[2])
        return float(((_model(q, t, T, G0, D, ea_kj) - y) ** 2).sum())
    return sse


def _fit_mode(arr, ea_kj):
    f = _sse_fn(arr, ea_kj)
    best = None
    for x0 in ([-3.5, -1.0, 0.5], [-3.0, -2.0, 0.0], [-4.5, -1.0, 1.0]):
        x, v = _nelder_mead(f, x0, 0.4)
        x, v = _nelder_mead(f, x, 0.05)
        if best is None or v < best[1]:
            best = (x, v)
    x, v = best
    return (math.exp(x[0]), math.exp(x[1]), float(x[2])), v


def _fit_result(up, src, mode_of, ea_kj, **kw):
    data = _joint_data(up, src, mode_of, **kw)
    params, sse, n = {}, {}, {}
    for m in MODEL_MODES:
        p, v = _fit_mode(data[m], ea_kj)
        params[m], sse[m], n[m] = dict(zip(PARAMS, p)), v, len(data[m])
    sse["total"] = sse["batch2p"] + sse["membrane"]
    return {"params": params, "sse": sse, "rmse": math.sqrt(sse["total"] / (n["batch2p"] + n["membrane"])), "n_points": n}


def node_x4(up, src):
    """The kinetic model (Q2: reversible aldol) fitted jointly to every two-phase batch and membrane time course."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    ea = up["x2"]["membrane"]["ea_kj_mol"]
    return {"mechanism": "reversible", "ea_fixed_kj_mol": ea, **_fit_result(up, src, mode_of, ea)}


def _run_residuals(arr_rows, p, ea):
    np = _np()
    return arr_rows[:, 6] - _model(p, arr_rows[:, 2], arr_rows[:, 3], arr_rows[:, 4], arr_rows[:, 5], ea)


def _run_stats(up, src, fit):
    """{exp: dict} residual statistics of every modelled run under the fit."""
    np = _np()
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    ea, rmse = fit["ea_fixed_kj_mol"], fit["rmse"]
    data = _joint_data(up, src, mode_of)
    out = {}
    for m in MODEL_MODES:
        p = tuple(fit["params"][m][k] for k in PARAMS)
        arr = data[m]
        res = _run_residuals(arr, p, ea)
        for exp in sorted({int(e) for e in arr[:, 0]}):
            sel = arr[:, 0] == exp
            mean = float(res[sel].mean())
            out[exp] = {"mode": m, "mean": mean, "systematic": int(abs(mean) > SYSTEMATIC_RMSE_FRACTION * rmse),
                        "sse": float((res[sel] ** 2).sum()), "p": p}
    return out, data


def _best_correction(up, src, fit, exp, stat, mode_of):
    """The single-sample upstream correction that most reduces the run's SSE: (cut, kind, sample, value, mean_after)."""
    np = _np()
    ea, rmse = fit["ea_fixed_kj_mol"], fit["rmse"]
    cond = _conditions(src)[exp]
    k5, k4, k6, k3 = _by_key(up["k5"]), _by_key(up["k4"]), _by_key(up["k6"]), _by_key(up["k3"])
    samples = sorted(n for (e, n) in k5 if e == exp and n > 0)
    def run_sse(change):
        res = []
        for n in samples:
            valid = k6[(exp, n)]["accepted"] == 1
            y = k5[(exp, n)]["c_anti"] + k5[(exp, n)]["c_syn"]
            if change and change[0] == n:
                if change[1] == "restore":
                    valid = True
                else:
                    y *= change[2] / k3[(exp, n)]["dilution"]
            if valid:
                res.append(y - float(_model(stat["p"], k4[(exp, n)]["t_true_h"], cond["temp_c"] + KELVIN, 1000 * cond["gly_m"],
                                            cond["dmso_pct"], ea)))
        return sum(v * v for v in res), sum(res) / len(res)
    best = None
    for n in samples:
        if k6[(exp, n)]["accepted"] == 0:
            trials = [(n, "restore", None)]
        else:
            trials = [(n, "dilution", d) for d in (1.0, 2.0, 5.0, 10.0) if d != k3[(exp, n)]["dilution"]]
        for tr in trials:
            sse, mean = run_sse(tr)
            cut = 1 - sse / stat["sse"]
            if best is None or cut > best[0]:
                best = (cut, tr[1], n, tr[2], mean)
    return best


def node_x5(up, src):
    """Residual review of the joint fit: which runs are systematic, and whether any single upstream correction explains them."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    fit = up["x4"]
    stats, _ = _run_stats(up, src, fit)
    rows = []
    for exp in sorted(stats):
        st = stats[exp]
        row = {"exp": exp, "systematic": st["systematic"], "mean_residual": None, "best_cut": None, "accepted": 0}
        if st["systematic"]:
            cut, kind, n, value, mean_after = _best_correction(up, src, fit, exp, st, mode_of)
            row["mean_residual"], row["best_cut"] = st["mean"], max(cut, 0.0)
            row["accepted"] = int(cut >= ACCEPT_CUT and abs(mean_after) <= SYSTEMATIC_RMSE_FRACTION * fit["rmse"])
        rows.append(row)
    return rows


def _accepted_corrections(up, src, fit, review):
    """The (restore set, dilution scale) of the review's accepted corrections."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    stats, _ = _run_stats(up, src, fit)
    restore, scale = set(), {}
    k3 = _by_key(up["k3"])
    for r in review:
        if r["accepted"]:
            cut, kind, n, value, _m = _best_correction(up, src, fit, r["exp"], stats[r["exp"]], mode_of)
            if kind == "restore":
                restore.add((r["exp"], n))
            else:
                scale[(r["exp"], n)] = value / k3[(r["exp"], n)]["dilution"]
    return restore, scale


def node_x6(up, src):
    """x4 refitted after the corrections x5 accepted (they flow back through the concentrations); none are accepted on this data."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    fit4 = up["x4"]
    restore, scale = _accepted_corrections(up, src, fit4, up["x5"])
    res = _fit_result(up, src, mode_of, fit4["ea_fixed_kj_mol"], valid_of=restore, scale=scale)
    return {"mechanism": "reversible", "ea_fixed_kj_mol": fit4["ea_fixed_kj_mol"], "corrections_applied": len(restore) + len(scale), **res}


def node_x7(up, src):
    """Which parameters the data pin down: 95 % profile intervals per mode."""
    mode_of = {e: c["mode"] for e, c in _conditions(src).items()}
    fit = up["x6"]
    ea = fit["ea_fixed_kj_mol"]
    data = _joint_data(up, src, mode_of)
    out = {}
    for m in MODEL_MODES:
        arr = data[m]
        f = _sse_fn(arr, ea)
        base = [math.log(fit["params"][m]["kf30"]), math.log(fit["params"][m]["k2"]), fit["params"][m]["dmso_exp"]]
        sse0 = f(base)
        thr = sse0 * (1 + CHI2_95 / (len(arr) - 3))
        out[m] = {}
        for j, name in enumerate(PARAMS):
            def prof(v):
                free = [i for i in range(3) if i != j]
                def g(q):
                    x = list(base)
                    x[j] = v
                    x[free[0]], x[free[1]] = q[0], q[1]
                    return f(x)
                return _nelder_mead(g, [base[i] for i in free], 0.2, tol=1e-12, maxit=800)
            bounds = []
            for sign in (-1, 1):
                lo, hi, step, found = 0.0, None, 0.05, False
                while step <= LOG_LIMIT * (1 if j < 2 else 4):
                    x, v = prof(base[j] + sign * step)
                    if v > thr:
                        hi, found = step, True
                        break
                    lo = step
                    step *= 1.6
                if not found:
                    bounds.append(None)
                    continue
                for _ in range(30):
                    mid = (lo + hi) / 2
                    x, v = prof(base[j] + sign * mid)
                    lo, hi = (mid, hi) if v <= thr else (lo, mid)
                bounds.append(base[j] + sign * (lo + hi) / 2)
            conv = (lambda v: None if v is None else math.exp(v)) if j < 2 else (lambda v: v)
            out[m][name] = {"lo": conv(bounds[0]), "hi": conv(bounds[1]), "identifiable": int(None not in bounds)}
    return out


def node_y1(up, src):
    """Flow conversion predicted by the membrane batch model at each residence time, against the measurements (Q3)."""
    gly = next(r["gly_m"] for r in up["k1"] if r["mode"] == "flow")
    p = tuple(up["x6"]["params"]["membrane"][k] for k in PARAMS)
    ea = up["x6"]["ea_fixed_kj_mol"]
    np = _np()
    by, errs = {}, []
    for tau, measured in sorted(up["f3"]["mean_conversion"].items()):
        pred = float(_model(p, float(tau), FLOW_TEMP_C + KELVIN, 1000 * gly, FLOW_DMSO_PCT, ea)) / (1000 * gly)
        by[tau] = {"predicted": pred, "measured": measured, "ratio": pred / measured}
        errs.append((pred - measured) ** 2)
    return {"assumed": {"temp_c": FLOW_TEMP_C, "dmso_pct": FLOW_DMSO_PCT}, "by_tau": by, "rmse": math.sqrt(_mean(errs))}


def node_R2(up, src):
    """The QC certificate: every sample the lab excludes and every dilution that departs from the usual 1:5, each with its
    justification number (the exclusion ratio or the dilution factor)."""
    k6, k3 = _by_key(up["k6"]), _by_key(up["k3"])
    rows = [_read(Path(src) / "data" / "injections.csv")][0]
    total = {(int(r["exp"]), int(r["sample"])): float(r["pa_anti"]) + float(r["pa_syn"]) for r in rows}
    out = []
    best = {}
    for (exp, n) in sorted(k6):
        if n == 0:
            continue
        if k6[(exp, n)]["accepted"] == 1:
            best[exp] = max(best.get(exp, 0.0), total[(exp, n)])
        else:
            out.append({"kind": "exclusion", "exp": exp, "sample": n, "value": total[(exp, n)] / best[exp]})
    for (exp, n), r in sorted(k3.items()):
        if n > 0 and r["dilution"] != DILUTION:
            out.append({"kind": "dilution", "exp": exp, "sample": n, "value": r["dilution"]})
    return out


# ---- stage 4: levels 10-13 ----------------------------------------------------------------------------------------------
# z1: the operating window is the tested range of x3's factors (the lowest and highest level of S2) and the 6 h end point
# z2: B = 200 bootstrap resamples of the 51 experiments, numpy.random.RandomState(20261115).randint(0, 51, 51) each, in
#     experiment order; degenerate (rank < 8) resamples are counted and skipped
BOOT_N, BOOT_SEED = 200, 20261115
WINDOW_FRACTION = 0.9
T_975_DF1 = 12.706204736432095  # Student t, 97.5 %, one degree of freedom (three temperatures, two fitted terms)


def _surface_optimum(coef, ranges):
    """The maximiser of the separable quadratic surface over the box (membrane runs): per factor, the best of its two
    ends and, for a concave term, its vertex when inside the range; and the unconstrained vertex of each factor."""
    best, vertex = {}, {}
    for var, sq in (("temp_c", "temp_c2"), ("dmso_pct", "dmso_pct2"), ("gly_m", "gly_m2")):
        lo, hi = ranges[var]
        b1, b2 = coef[var], coef[sq]
        f = lambda x: b1 * x + b2 * x * x  # noqa: E731
        cands = [lo, hi]
        vertex[var] = -b1 / (2 * b2) if b2 else None
        if b2 < 0 and lo < vertex[var] < hi:
            cands.append(vertex[var])
        best[var] = max(cands, key=f)
    return best, vertex


def _surface_value(coef, x, membrane=1.0):
    return (coef["intercept"] + coef["temp_c"] * x["temp_c"] + coef["dmso_pct"] * x["dmso_pct"] + coef["gly_m"] * x["gly_m"]
            + coef["temp_c2"] * x["temp_c"] ** 2 + coef["dmso_pct2"] * x["dmso_pct"] ** 2 + coef["gly_m2"] * x["gly_m"] ** 2
            + coef["membrane"] * membrane)


def _ranges(src):
    cond = [c for c in _conditions(src).values() if c["mode"] in MODEL_MODES]
    return {v: (min(c[v] for c in cond), max(c[v] for c in cond)) for v in ("temp_c", "dmso_pct", "gly_m")}


def node_z1(up, src):
    """The operating window: the conditions of the highest predicted yield inside the tested range and the 6 h end point."""
    ranges = _ranges(src)
    cy, cr = up["x3"]["yield"]["coef"], up["x3"]["rate"]["coef"]
    opt, vertex = _surface_optimum(cy, ranges)
    levels = {v: sorted({c[v] for c in _conditions(src).values() if c["mode"] in MODEL_MODES}) for v in ranges}
    best = _surface_value(cy, opt)
    window = sum(1 for t in levels["temp_c"] for d in levels["dmso_pct"] for g in levels["gly_m"]
                 if _surface_value(cy, {"temp_c": t, "dmso_pct": d, "gly_m": g}) >= WINDOW_FRACTION * best)
    p = tuple(up["x6"]["params"]["membrane"][k] for k in PARAMS)
    model6 = float(_model(p, 6.0, opt["temp_c"] + KELVIN, 1000 * opt["gly_m"], opt["dmso_pct"], up["x6"]["ea_fixed_kj_mol"])) / (10 * opt["gly_m"])
    return {"optimum": opt, "yield_pct": best, "rate_at_optimum": _surface_value(cr, opt),
            "model_yield_6h_pct": model6, "window_points": window,
            "kinetic_parameters_identifiable": sum(q["identifiable"] for m in up["x7"].values() for q in m.values()),
            "unconstrained": {"dmso_pct_vertex": vertex["dmso_pct"], "inside_range": int(all(
                ranges[v][0] <= vertex[v] <= ranges[v][1] and cy[sq] < 0 for v, sq in (("temp_c", "temp_c2"), ("dmso_pct", "dmso_pct2"),
                                                                                        ("gly_m", "gly_m2"))))}}


def node_z2(up, src):
    """The optimum of z1 re-solved over a fixed bootstrap of the experiments."""
    np = _np()
    cond = _conditions(src)
    rows = []
    for mode, ends in (("batch2p", up["b1"]), ("membrane", up["m1"])):
        for r in ends:
            c = cond[r["exp"]]
            rows.append((r["exp"], [1.0, c["temp_c"], c["dmso_pct"], c["gly_m"], c["temp_c"] ** 2, c["dmso_pct"] ** 2, c["gly_m"] ** 2,
                                    float(mode == "membrane")], r["yield_pct"]))
    rows.sort()
    X = np.array([r[1] for r in rows])
    y = np.array([r[2] for r in rows])
    ranges = _ranges(src)
    rs = np.random.RandomState(BOOT_SEED)
    choice = {v: {"lo": 0, "hi": 0, "interior": 0} for v in ranges}
    yields, picks, degenerate = [], [], 0
    for _ in range(BOOT_N):
        idx = rs.randint(0, len(rows), len(rows))
        if np.linalg.matrix_rank(X[idx]) < 8:
            degenerate += 1
            continue
        beta, *_ = np.linalg.lstsq(X[idx], y[idx], rcond=None)
        coef = dict(zip(SURFACE_TERMS, (float(b) for b in beta)))
        opt, _v = _surface_optimum(coef, ranges)
        pick = {}
        for v in ranges:
            lo, hi = ranges[v]
            pick[v] = "lo" if abs(opt[v] - lo) < 1e-9 else "hi" if abs(opt[v] - hi) < 1e-9 else "interior"
            choice[v][pick[v]] += 1
        picks.append(tuple(pick[v] for v in ranges))
        yields.append(_surface_value(coef, opt))
    n = len(yields)
    lo, hi = np.percentile(yields, [2.5, 97.5])
    ref_pick = []
    for v in ranges:
        o = up["z1"]["optimum"][v]
        ref_pick.append("lo" if abs(o - ranges[v][0]) < 1e-9 else "hi" if abs(o - ranges[v][1]) < 1e-9 else "interior")
    return {"n_boot": BOOT_N, "n_degenerate": degenerate,
            "factor_choice": {v: {k: c / n for k, c in cnt.items()} for v, cnt in choice.items()},
            "same_corner_share": sum(1 for p in picks if p == tuple(ref_pick)) / n,
            "yield_ci": {"lo": float(lo), "hi": float(hi)}}


def node_z3(up, src):
    """The recommended process mode: the highest mean space-time yield, with the evidence behind it."""
    sty = {m: v["mean"] for m, v in up["y2"]["sty"].items()}
    ranked = sorted(sty, key=lambda m: -sty[m])
    ratios = [v["ratio"] for v in up["y1"]["by_tau"].values()]
    return {"recommended_mode": ranked[0], "runner_up": ranked[1], "mean_sty": sty, "sty_margin": sty[ranked[0]] / sty[ranked[1]],
            "membrane_wins": sum(1 for p in up["x1"]["pairs"].values() if p["difference_pct"] > 0),
            "flow_transfer_ratio": _mean(ratios), "optimum_share": up["z2"]["same_corner_share"]}


def _ea_interval(k_by_temp, ea):
    xs = [1 / (float(t) + KELVIN) for t in k_by_temp]
    ys = [math.log(v) for v in k_by_temp.values()]
    n = len(xs)
    b = slope(xs, ys)
    mx, my = _mean(xs), _mean(ys)
    resid = [y - (my + b * (x - mx)) for x, y in zip(xs, ys)]
    se = math.sqrt(sum(r * r for r in resid) / (n - 2) / sum((x - mx) ** 2 for x in xs))
    half = T_975_DF1 * se * GAS_R / 1000
    return ea - half, ea + half


def node_R1(up, src):
    """Every headline number with its interval: the six kinetic parameters (profile intervals), the optimum yield (bootstrap
    interval) and the two activation energies (95 % t-interval of the Arrhenius slope over the three temperatures)."""
    rows = []
    for m in MODEL_MODES:
        for name in PARAMS:
            b = up["x7"][m][name]
            rows.append({"key": f"{m}.{name}", "value": up["x6"]["params"][m][name], "lo": b["lo"], "hi": b["hi"]})
    rows.append({"key": "optimum_yield_pct", "value": up["z1"]["yield_pct"], "lo": up["z2"]["yield_ci"]["lo"], "hi": up["z2"]["yield_ci"]["hi"]})
    for key, blk, kk in (("membrane_ea_kj_mol", up["x2"]["membrane"], "k_mean_by_temp"), ("batch_ea_kj_mol", up["x2"]["batch"], "k_by_temp")):
        lo, hi = _ea_interval(blk[kk], blk["ea_kj_mol"])
        rows.append({"key": key, "value": blk["ea_kj_mol"], "lo": lo, "hi": hi})
    return rows


def node_R3(up, src):
    """The model card: the mechanism, the parameters, what the data pin down and how the model transfers to flow."""
    ident = sum(p["identifiable"] for m in up["x7"].values() for p in m.values())
    return {"mechanism": up["x6"]["mechanism"], "parameters": up["x6"]["params"], "rmse": up["x6"]["rmse"],
            "identifiable_parameters": ident, "flow_transfer_ratio": _mean(v["ratio"] for v in up["y1"]["by_tau"].values()),
            "flow_assumed": up["y1"]["assumed"]}


def main(argv=None):
    here = Path(__file__).resolve().parent
    for p in (here, here.parent / "kit"):  # shipped next to taskgraph.py; in the repo it is under ../kit
        sys.path.insert(0, str(p))
    import taskgraph
    taskgraph.reference_cli(sys.modules[__name__], here / "graph.json", argv)


if __name__ == "__main__":
    main()
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
