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
| `plots/paper_figures/fracture_comparison_3x3_four_steps.png` | `scripts/python_plots/plot_real_fracture_comparison_day408.py` with the Figure 1 command below | `plots/paper_figures/controlled_day728_POF_eps0.jld2`, `plots/paper_figures/cvar_day728_sensitivity_1p22x.jld2`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2` | CVaR sensitivity result: 97 pressure-exceeding cells, min(r)=-0.0040873, 2.84969 Mt; actual day-728 rate 0.1208532 m3/s. |
| `plots/paper_figures/fracture_comparison_3x3_four_steps_cvar_sensitivity_1p22x.png` | `scripts/python_plots/plot_real_fracture_comparison_day408.py` with `CVAR_SENSITIVITY=1.22` | `plots/paper_figures/cvar_day728_sensitivity_1p22x.jld2`, controlled/no-control files | Sensitivity comparison. Preserve provenance when using this figure. |
| `plots/paper_figures/fracture_comparison_three_cases_full_campaign.mp4` | `scripts/python_plots/create_full_campaign_fracture_video.py` | `plots/paper_figures/full_campaign_video_*.jld2` | Full 1920-day campaign video. Metadata lives in `fracture_comparison_three_cases_full_campaign_metadata.json`. |
| `plots/paper_figures/perm_ensemble_statistics.png` | `scripts/python_plots/plot_perm_ensemble.py` | `data/geo/wise_perm_models_2000_new.jld2` | Permeability ensemble figure. Ground truth is the 2000th permeability slice unless explicitly changed. |
| `plots/paper_figures/statistical/` | `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl` | `data/DT_control/exp_name=step1/**/final.jld2` | Step-1 ECDF/bootstrap statistical figures copied from `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/`. See `FIGURE_INDEX.md` in that folder. |

## Figure 1 reproduction

```bash
CVAR_SENSITIVITY=1.22 FIGURE_PNG_NAME=fracture_comparison_3x3_four_steps.png python scripts/python_plots/plot_real_fracture_comparison_day408.py
```

The CVaR panel matches the fields in the supplied old Figure 1: the saved
sensitivity simulation used 1.22 times the base CVaR schedule. At the author's
request, the annotation reports the base-schedule rate (0.09906 m3/s) and
base-schedule cumulative injected mass through day 728 (2.3358150144 Mt),
with the base-schedule explanation delegated to the manuscript caption at the
author's request (the in-panel heading has been removed). Field diagnostics
still refer to the sensitivity simulation (97 exceeding cells); its actual
rate and cumulative mass are 0.1208532 m3/s and 2.849694317568 Mt.
The global title is "Comparison Using Ground-Truth Permeability at Day 728".
The panel title contains only the CVaR risk parameters. The manuscript caption or methods
must identify this as a 22% increase over the base CVaR schedule, rather than
the unmodified optimized schedule. No simulation data were edited or rerun.
PoF and no-control inputs and all color normalization rules are unchanged.
Only PNG is exported; the supplied `_old.png` reference remains untouched.

The default configuration without environment overrides still uses the base
CVaR data (zero pressure-exceeding cells); use the command above to reproduce
the committed Figure 1.

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
