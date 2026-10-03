# src/

Core Julia modules invoked by the optimization workflows.
Keep CLI interfaces stable — SLURM scripts call these directly.

## Active modules

| File | Role |
|------|------|
| `optim_inject.jl` | Main optimization entry point |
| `optim_case_config.jl` | Case key / step configuration |
| `optim_prior_state.jl` | Prior-state loading for step > 1 |
| `optim_output_paths.jl` | Output path assembly |
| `utils.jl` | Shared helpers |
| `archive/optim_inject_7cases_fix.jl` | Historical 7-case fix driver (used by some rerun scripts) |

## archive/

Non-primary variants with retained callers, including `optim_inject_7cases_fix.jl`.
The deprecated gamma-table/threshold workflow was retired with user approval;
see [the deletion record](../docs/reference/DELETION_REVIEW_2026-10-03.md).

Plotting scripts live under `scripts/julia_scripts/plotting/` and `scripts/python_plots/`.
