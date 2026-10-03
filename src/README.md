# src/

Core Julia modules invoked by optimization and threshold-sensitivity workflows.
Keep CLI interfaces stable — SLURM scripts call these directly.

## Active modules

| File | Role |
|------|------|
| `optim_inject.jl` | Main optimization entry point |
| `optim_case_config.jl` | Case key / step configuration |
| `optim_prior_state.jl` | Prior-state loading for step > 1 |
| `optim_output_paths.jl` | Output path assembly |
| `threshold_sensitivity.jl` | Threshold / calibration workflow |
| `utils.jl` | Shared helpers |
| `archive/optim_inject_7cases_fix.jl` | Historical 7-case fix driver (used by some rerun scripts) |

## archive/

Non-primary variants kept for reproducibility (`threshold_sensitivity_compact.jl`, `optim_inject_7cases_fix.jl`, etc.).

Plotting scripts live under `scripts/julia_scripts/plotting/` and `scripts/python_plots/`.
