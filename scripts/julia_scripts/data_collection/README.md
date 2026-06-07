# data_collection/

Julia scripts that export or aggregate data for downstream analysis and figures.

```text
data_collection/
├── collect_all_injection_rates.jl
├── collect_cvar_only.jl
├── collect_pof_32_injection_rates.jl
├── compute_inj_arrays_for_dt_training.jl
└── forward_exports/
    ├── run_forward_export.jl
    └── run_forward_four_steps_base_export.jl
```

`forward_exports/` contains Julia forward-simulation exporters that produce JLD2
inputs for Python figure scripts under `scripts/python_plots/`.
