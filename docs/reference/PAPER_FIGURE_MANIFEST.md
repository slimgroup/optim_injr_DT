# Paper Figure Manifest

This manifest records the current paper-facing figure assets, their primary
generation scripts, and their input data. It is intentionally descriptive: do
not move or delete generated files solely because they appear here.

## Rules Of Thumb

- Keep final paper assets under `plots/paper_figures/`.
- Keep large `.jld2` inputs in place unless the user explicitly authorizes a
  cleanup or migration.
- If a figure uses a sensitivity experiment, keep that provenance visible in
  the script, file name, metadata, or caption text.
- Heavy forward simulations and animation rendering should run through
  `sbatch` or `salloc` on PACE.

## Figure Assets

| Output | Script | Primary inputs | Notes |
|--------|--------|----------------|-------|
| `plots/paper_figures/injection_schedule_over_four_steps.png` | `scripts/python_plots/plot_injection_schedule_over_four_steps.py` | `docs/injection_rate_arrays.md`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2` | Dual-axis schedule figure. No-control stops after the recorded severe-fracture day. |
| `plots/paper_figures/pressure_risk_trajectory_over_four_steps.png` | `scripts/python_plots/plot_pressure_risk_trajectory_over_four_steps.py` | `plots/paper_figures/forward_sim_four_steps_base_data.jld2`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2`, additional trajectory files used by the script | Pressure-load and fractured-cell trajectory figure. Check the script for exact plotted cases before manuscript use. |
| `plots/paper_figures/fracture_comparison_3x3_four_steps_base.png` | `scripts/python_plots/plot_real_fracture_comparison_day408.py` with default setting | `plots/paper_figures/controlled_day728_POF_eps0.jld2`, `plots/paper_figures/controlled_day728_CVaR_g01_a001.jld2`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2` | Script name is historical; current comparison day is controlled by `DAY` in the script. Figure labels use `PoF`; file names may still contain legacy `PoF` keys. |
| `plots/paper_figures/fracture_comparison_3x3_four_steps_cvar_sensitivity_1p22x.png` | `scripts/python_plots/plot_real_fracture_comparison_day408.py` with `CVAR_SENSITIVITY=1.22` | `plots/paper_figures/cvar_day728_sensitivity_1p22x.jld2`, controlled/no-control files | Sensitivity comparison. Preserve provenance when using this figure. |
| `plots/paper_figures/fracture_comparison_three_cases_full_campaign.mp4` | `scripts/python_plots/create_full_campaign_fracture_video.py` | `plots/paper_figures/full_campaign_video_*.jld2` | Full 1920-day campaign video. Metadata lives in `fracture_comparison_three_cases_full_campaign_metadata.json`. |
| `plots/paper_figures/perm_ensemble_statistics.png` | `scripts/python_plots/plot_perm_ensemble.py` | `data/geo/wise_perm_models_2000_new.jld2` | Permeability ensemble figure. Ground truth is the 2000th permeability slice unless explicitly changed. |
| `plots/paper_figures/statistical/` | `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl` | `data/DT_control/exp_name=step1/**/final.jld2` | Step-1 ECDF/bootstrap statistical figures copied from `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/`. See `FIGURE_INDEX.md` in that folder. |

## Forward-Export Scripts

| Script | Purpose | Typical submitter |
|--------|---------|-------------------|
| `scripts/julia_scripts/data_collection/forward_exports/run_forward_four_steps_base_export.jl` | Base four-step ground-truth forward export for schedule/risk figures | run through a Slurm allocation or wrapper |
| `scripts/julia_scripts/data_collection/forward_exports/run_controlled_day728_from_day720.jl` | Controlled day-728 forward states | `scripts/shell/submit/submit_controlled_day728.sh` |
| `scripts/julia_scripts/data_collection/forward_exports/run_no_control_delayed_fracture_sweep.jl` | No-control delayed ramp and severe-fracture shutdown day | `scripts/shell/submit/submit_no_control_delayed_fracture_sweep.sh` |
| `scripts/julia_scripts/data_collection/forward_exports/run_cvar_day728_sensitivity_sweep.jl` | CVaR day-728 sensitivity trajectory data | `scripts/shell/submit/submit_cvar_day728_sensitivity_sweep.sh` |
| `scripts/julia_scripts/data_collection/forward_exports/run_full_campaign_video_cases.jl` | Full-campaign video forward fields | `scripts/shell/submit/submit_full_campaign_video_forwards.sh` |

## Current Caveats

- `plot_real_fracture_comparison_day408.py` has a historical filename. Inspect
  `DAY` and input file names before citing its output.
- `plots/paper_figures/` intentionally contains both paper figures and large
  intermediate `.jld2` files. Do not clean this directory automatically.
- Several exploratory no-control and sensitivity sweep scripts may exist as
  local untracked files. Treat them as active research artifacts until the user
  explicitly decides whether to archive, commit, or discard them.
