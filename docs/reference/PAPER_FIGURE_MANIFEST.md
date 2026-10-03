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

The eight posterior maps and three Appendix E statistical grids now have a
separate, explicitly historical export workflow:
`sbatch scripts/shell/submit/submit_posterior_appendix_e_export.sh`.
The canonical names are `plots/paper_figures/posterior/posterior_mean_step{k}.png`
and `posterior_std_step{k}.png` for steps 1–4, and
`plots/paper_figures/statistical/injection_rate_hist_ecdf_step{k}.png` for steps
2–4. The handoff includes original manuscript-name copies under `paper_compat/`;
paper QMD paths and all historical source assets remain unchanged. Exact source
mapping, scientific conventions and consumer audit are documented in
[the re-export note](../analysis/POSTERIOR_APPENDIX_E_REEXPORT_2026-09-08.md).
Each generated handoff contains a checksum manifest and numeric validation.
The latest user requirement restores concise global titles identifying the
quantity/statistic and monitoring step `k`. These titles occupy an added header
above the unchanged panel canvas; the canonical filenames remain the same.
The 2026-09-09 revision removes only the histogram quantile-interval shading and
its legend entry from the three statistical grids. ECDF uncertainty remains
visible; historical numerics and the eight posterior figures remain unchanged.

| Output | Script | Primary inputs | Notes |
|--------|--------|----------------|-------|
| `plots/paper_figures/injection_schedule_over_four_steps.png` | `scripts/python_plots/plot_injection_schedule_over_four_steps.py` | `docs/injection_rate_arrays.md`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2` | Dual-axis schedule figure. No-control stops after the recorded severe-fracture day. |
| `plots/paper_figures/pressure_risk_trajectory_over_four_steps.png` | `scripts/python_plots/plot_pressure_risk_trajectory_over_four_steps.py` | `plots/paper_figures/forward_sim_four_steps_base_data.jld2`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2`, additional trajectory files used by the script | Pressure-load and fractured-cell trajectory figure. Check the script for exact plotted cases before manuscript use. |
| `plots/paper_figures/fracture_comparison_3x3_four_steps.png` | `scripts/python_plots/plot_real_fracture_comparison_day408.py` with the Figure 1 command below | `plots/paper_figures/controlled_day728_POF_eps0.jld2`, `plots/paper_figures/cvar_day728_sensitivity_1p22x.jld2`, `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2` | CVaR sensitivity result: 97 pressure-exceeding cells, min(r)=-0.0040873, 2.84969 Mt; actual day-728 rate 0.1208532 m3/s. |
| `plots/paper_figures/fracture_comparison_3x3_four_steps_cvar_sensitivity_1p22x.png` | `scripts/python_plots/plot_real_fracture_comparison_day408.py` with `CVAR_SENSITIVITY=1.22` | `plots/paper_figures/cvar_day728_sensitivity_1p22x.jld2`, controlled/no-control files | Sensitivity comparison. Preserve provenance when using this figure. |
| `plots/paper_figures/fracture_comparison_three_cases_full_campaign.mp4` | `scripts/python_plots/create_full_campaign_fracture_video.py` | `plots/paper_figures/full_campaign_video_*.jld2` | Full 1920-day campaign video. Metadata lives in `fracture_comparison_three_cases_full_campaign_metadata.json`. |
| `plots/paper_figures/perm_ensemble_statistics.png` | `scripts/python_plots/plot_perm_ensemble.py` | `data/geo/wise_perm_models_2000_new.jld2` | Permeability ensemble figure. Ground truth is the 2000th permeability slice unless explicitly changed. |
| `plots/paper_figures/perm_pressure_saturation_ensemble_statistics_64.png` | `scripts/python_plots/plot_joint_permeability_statistics.py` | `data/forward_comparisons/joint_perm_day1920_64_20260915T062645Z/`, `data/forward_comparisons/joint_perm_ground_truth_day1920_20261002/`, `data/geo/wise_perm_models_2000_new.jld2` | Day-1920 3×3: permeability / pressure difference / CO₂ saturation by ground truth / ensemble mean / population std. All three rows use the same 64 preselected first-step permeability samples. Reference ID 2000 uses identical initial conditions, well and unscaled selected PoF schedule. Response panels have 20% permeability overlays; mean/std use the 64-member mean geology. Original 2000-member permeability-only PNG is preserved. Companion JSON records inputs and validation; TXT contains the caption. |
| `plots/paper_figures/perm_pressure_saturation_ensemble_statistics_128.png` | `scripts/python_plots/plot_joint_permeability_statistics.py` | `data/forward_comparisons/joint_perm_day1920_128_20261002/`, the existing 64-member run and identical ground-truth reference above | All 128 first-monitoring-step permeability samples, in `idx_t1` array order; 125 distinct fields with three repeated draws retained at their original weights. Adds 61 distinct forwards. Same Day-1920 conditions, 3×3 layout, fonts and overlays as the approved 64 version; its color limits are retained whenever they cover the new statistics. The original 64-sample figure is preserved. |
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

### Joint permeability uncertainty figure

The 64-member version reuses the presentation's completed Day-1920 controlled
permeability ensemble. It does not combine posterior-state uncertainty with
permeability uncertainty. Historical ground-truth response exports use different
initial saturation and well geometry, so the reference is computed separately
using permeability realization 2000 and the exact common inputs of the ensemble.
Reference ID 2000 is not added to the 64-member mean/std calculations.

The prescribed injection schedule is the historical, unscaled **PoF ε=0.01**
four-stage sequence saved as
`plots/paper_figures/forward_sim_four_steps_base_data.jld2::POF_eps0p01_rates`.
All 64/128 ensemble members and the ground-truth reference use these same 24
piecewise-constant rates, each held for 80 days (1920 days total):

| Time interval [days] | Six consecutive 80-day injection rates [m³/s] |
|----------------------|-----------------------------------------------|
| 0–480 | 0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530 |
| 480–960 | 0.04530, 0.05087, 0.05645, 0.06203, 0.06760, 0.07317 |
| 960–1440 | 0.07317, 0.07458, 0.07599, 0.07741, 0.07882, 0.08023 |
| 1440–1920 | 0.08023, 0.08041, 0.08059, 0.08078, 0.08096, 0.08114 |

The first-monitoring-step designation identifies the permeability sample source;
the prescribed controls span all four monitoring intervals. This experiment
replays the previously selected schedule with common initial pressure,
saturation, porosity and well geometry, varying only permeability. It performs
no sample-specific optimization or posterior-state updates at the interval
boundaries. These are the rounded historical controls that produced the saved
results, not a retroactive substitution of revised statistical selections.
The multiplier is 1.0; the PoF ×1.65 sensitivity schedule used in some other
figures is not used here. The source dataset, run protocol and saved inputs
agree exactly; the Float64 schedule SHA-256 is
`a0d934c7000fb36691d5a1ea6d2c047468e69fb64f2adcf00bc85b7b896943ad`.

Permeability statistics follow the original figure: mean and population standard
deviation of `log10(K [mD])`. Its mean is displayed on the logarithmic mD color
scale, corresponding to geometric mean permeability. Pressure difference is
`(p - p0)/1e6` MPa; saturation is dimensionless. Their means/stds are computed
in physical units, before the contextual permeability overlay. Both response
statistics use the same mean-log-permeability overlay; the ground-truth response
uses its own permeability. The full grid is displayed at equal physical aspect.

To reproduce, supply **new** paths for each output; the scripts refuse to replace
existing artifacts. These commands use separate Slurm allocations:

```bash
sbatch scripts/shell/submit/submit_joint_permeability_ground_truth.sh \
  data/forward_comparisons/joint_perm_day1920_64_20260915T062645Z \
  data/forward_comparisons/NEW_ground_truth_day1920

sbatch scripts/shell/submit/submit_joint_permeability_statistics.sh \
  --prepare-only --cache data/forward_comparisons/NEW_joint_statistics/ensemble_statistics.npz

# Run after the reference simulation and statistics preparation finish.
sbatch scripts/shell/submit/submit_joint_permeability_statistics.sh \
  --cache data/forward_comparisons/NEW_joint_statistics/ensemble_statistics.npz \
  --reference-dir data/forward_comparisons/NEW_ground_truth_day1920 \
  --output plots/paper_figures/NEW_perm_pressure_saturation_statistics_64.png
```

For another layout export, reuse the completed reference and cache paths with
a new PNG path. Only the single-figure render is needed in that case.

The full-ensemble revision uses `data/state/new/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2::idx_t1`
for all 128 positions. These are the indices consumed by `load_step_context(1, s, BroadK)`;
the old and new step-1 index exports also agree. The original 64 members are a
predeclared subset of these positions. Repeated geological IDs are 734 at
positions 62/69, 1011 at 72/83, and 960 at 101/115. The full statistics retain
all 128 sample positions with weight 1/128, rather than deduplicating the
ensemble to 125 equally weighted fields. Because all other forward inputs are
identical, repeated permeability fields reuse their existing response fields.
The run's `approval.json::member_sources` records every position's actual source.

The expansion reuses the exact original forward source (SHA-256
`9b6261c51b014d518eeb351d753608432a35f8543ca24f387813712a931468c9`), existing
64 results, and ground-truth response. It submits only the remaining 61 distinct
permeabilities, without changing the initial state, well, rate schedule, grid,
or model-library versions. Slurm array `13819682` produces these responses;
jobs `13819705` and `13819706` depend on their successful completion and compute
the full statistics and PNG. The full-ensemble caption explicitly identifies
the first-monitoring-step sample source and repeated draws. This comparison
isolates permeability variation using common initial states; it does not reuse
the sample-dependent initial states or controls of the original optimization.

The expansion completed successfully: all 61 additional forwards and both
statistics/rendering jobs exited `0:0`, using 58.4589 allocated core-hours.
The final PNG is 5400×3779 at 300 dpi. All three ground-truth map interiors
are pixel-identical to the 64-sample figure; the mean/std color limits,
map and colorbar positions, fonts and overlay opacity are unchanged. Independent
direct reductions at 54 fixed cells across all 128 positions reproduced the
means/stds within 1.8e-15. There were no omitted or failed selected samples.

The numerical change from 64 to 128, measured as
`norm(field64 - field128) / norm(field128)` over the full grid, is:

| Field | Mean change | Population std change |
|-------|-------------|-----------------------|
| `log10(K [mD])` | 1.55% | 7.18% |
| Pressure difference [MPa] | 1.59% | 5.15% |
| CO₂ saturation | 5.84% | 8.63% |

These values quantify sensitivity to this ensemble expansion; they are not a
proof of convergence. The original 64 samples capture the broad spatial
patterns, while the full 128 also preserve the entire first-step empirical
ensemble. Detailed checks and resource records are saved in the full run's
`comparison_64_128_validation.json`, `execution_resources.csv`, and
`resource_summary.json`.

To re-render the full ensemble after its cache is available, use a new output name:

```bash
sbatch scripts/shell/submit/submit_joint_permeability_statistics.sh \
  --cache data/forward_comparisons/joint_perm_day1920_128_20261002/ensemble_statistics.npz \
  --reference-dir data/forward_comparisons/joint_perm_ground_truth_day1920_20261002 \
  --limits-from plots/paper_figures/perm_pressure_saturation_ensemble_statistics_64.json \
  --output plots/paper_figures/NEW_perm_pressure_saturation_statistics_128.png
```

### Existing forward exports

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
