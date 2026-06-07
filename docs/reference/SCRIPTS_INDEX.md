# Script Entry Points

This page is a lightweight navigation guide for the current `scripts/` tree.
It is meant to answer: "which script should I start from?" without changing or
renaming the existing research workflow.

## High-Level Layout

```text
scripts/
├── shell/                 # SLURM submit/run/check helpers
│   ├── submit/            # sbatch wrappers
│   ├── run/               # bash drivers
│   ├── check/             # progress & verification
│   ├── retry/             # reruns & queue cleanup
│   └── maintenance/       # organizers + layout tools
├── julia_scripts/
│   ├── plotting/          # Julia figures/videos (see plotting/README.md)
│   │   ├── posterior_stats/
│   │   ├── bootstrap_ecdf/
│   │   ├── videos/
│   │   ├── legacy_step1/
│   │   ├── diagnostics/
│   │   └── general/
│   ├── data_collection/   # Aggregate results from finished runs
│   ├── analysis/          # Analysis / comparison utilities
│   ├── utilities/         # Diagnostics, scaling, tuning, misc helpers
│   └── archive/           # Historical scripts kept for reference
├── python_plots/          # Python-based paper figure assembly
├── gamma_tables/          # Historical gamma tables from a deprecated comparison path
└── __pycache__/           # Local cache only; ignored by git
```

## Main Entry Points

### Core optimization drivers

- `src/optim_inject.jl`
  Main optimization entry point. Keep CLI and batch-job assumptions stable.
- `src/threshold_sensitivity.jl`
  Threshold / calibration workflow entry point.

### Shell entry points in `scripts/shell/`

Paths below are relative to `scripts/shell/`.

#### Common current entry points

- `run/optim_inject_pace.sh`
  Main SLURM job entry point for array optimization runs on PACE.
- `submit/submit_all.sh`
  Broad batch submission helper.
- `run/run_bootstrap_cdf.sh`
  Run the bootstrap CDF plotting pipeline on a compute node or interactive allocation.
- `submit/submit_bootstrap_cdf.sh`
  SLURM wrapper for the bootstrap CDF plotting pipeline.
- `run/run_plot_threshold_sensitivity.sh`
  Direct run helper for threshold-sensitivity plotting.
- `submit/submit_threshold_sensitivity.sh`
  Threshold-sensitivity submission wrapper that still exists in this tree.
- `submit/submit_video_generation.sh`
  Batch entry point for video-generation workflows.

#### Diagnostics and status checks

- `check/check_*`
  Queue status, sample completeness, verification, and progress helpers.
- `check/verify_logs_path.sh`, `check/verify_skip_from_log.sh`
  Log-path and skip-behavior checks.
- `check/test_ds_verification.sh`
  Verification-oriented test helper (runs `test/integration/test_ds_minimal.jl`).

#### Recovery and special-case reruns

- `retry/retry_failed_job.sh`, `retry/retry_step2_sample113.sh`
  Retry helpers for specific failed runs.
- `retry/rerun_7_missing_cvar_samples_fix.sh`
  Targeted rerun helper for missing CVaR samples.
- `retry/cancel_duplicate_pof_jobs.sh`
  Queue cleanup helper for duplicate POF jobs.
- `maintenance/move_iteration_files_to_scratch.sh`
  File-placement helper for iteration artifacts.

#### Historical or narrow-use submission scripts

- `submit/submit_11_cases_samples_1_128.sh`
- `submit/submit_11_cases_samples_2_64_smart.sh`
- `submit/submit_20_cases_samples_65_128_smart.sh`
- `submit/submit_128perm_only.sh`
- `submit/submit_cvar_2cases_alpha_0.02.sh`
- `submit/submit_cvar_4cases_alpha_0_0.01.sh`
- `submit/submit_cvar_g=0.2_a=0.01.sh`
- `submit/submit_cvar_gamma_0.1_0.2.sh`
- `submit/submit_cvar_gamma_0.4.sh`
- `submit/submit_missing_pof_samples.sh`
- `submit/submit_missing_pof_samples_fix.sh`
- `submit/submit_pof_cases_simple.sh`
- `submit/submit_pof_cases_smart.sh`
- `submit/submit_pof_sensitivity.sh`
- `submit/submit_step2_dual_prior_smoketest.sh`
- `run/optim_inject_cruyff.sh`, `run/optim_inject_cruyff_cpu.sh`, `run/optim_inject_pace_7cases_fix.sh`
  Case-specific or historical workflows kept for reference or reruns.

#### Deprecated gamma-table path

- `submit/submit_gamma_table_generation.sh`
  Historical helper for a deprecated gamma-table-based POF/CVaR comparison path.
  Keep for reproducibility only; do not treat as the recommended workflow.

### Julia plotting entry points

- `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`
  Bootstrap histogram/CDF figures, including part-1 and grid modes.
- `scripts/julia_scripts/plotting/legacy_step1/plot_pof_vs_cvar.jl`
  POF vs CVaR threshold-sensitivity comparison figures.
- `scripts/julia_scripts/plotting/general/plot_perm_ensemble.jl`
  Julia version of permeability ensemble plotting.
- `scripts/julia_scripts/plotting/general/plot_fracture_comparison.jl`
  Forward-simulation comparison figure from Julia.
- `scripts/julia_scripts/plotting/videos/generate_5case_videos.jl`
  Ground-truth forward videos for five control cases.
- `scripts/julia_scripts/plotting/videos/generate_stat3case_videos.jl`
  Three-case statistical/video workflow.

### Python posterior-stats entry points

- `scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py`
- `scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py`
- `scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py`
  Paired-posterior histogram/CDF grids per monitoring step. Step 2 shell wrapper: `shell/run/run_step2_paired_posterior_stats.sh`.

### Python paper-figure entry points

- `scripts/python_plots/run_forward_export.jl`
  Produces `plots/paper_figures/forward_sim_data.jld2` for downstream Python figure scripts.
- `scripts/python_plots/plot_3row_comparison.py`
  Three-row paper figure using the forward-export file.
- `scripts/python_plots/plot_fracture_comparison.py`
  Frame-composition figure from existing forward/video outputs.
- `scripts/python_plots/plot_fracture_comparison_paper.py`
  Tighter paper-layout version of the fracture comparison figure.
- `scripts/python_plots/plot_perm_ensemble.py`
  Python paper figure for permeability ensemble statistics.
- `scripts/python_plots/submit_forward_and_plot.sh`
  Batch wrapper for forward export plus Python plotting.

## Script Groups By Purpose

### `scripts/shell/`

Subfolders: `submit/`, `run/`, `check/`, `retry/`, `maintenance/`. See `scripts/shell/README.md`.

- Common current entry points:
  `run/optim_inject_pace.sh`, `submit/submit_all.sh`, `run/run_bootstrap_cdf.sh`, `submit/submit_bootstrap_cdf.sh`, `run/run_plot_threshold_sensitivity.sh`, `submit/submit_threshold_sensitivity.sh`
- Diagnostics:
  `check/check_*`, `check/verify_*`, `check/test_ds_verification.sh`
- Recovery and queue management:
  `retry/retry_*`, `retry/rerun_*`, `retry/cancel_*`, `maintenance/move_*`
- Historical or narrow-use submit wrappers:
  case-specific `submit/submit_*` scripts retained for reproducibility
- Deprecated:
  `submit/submit_gamma_table_generation.sh` for the old gamma-table comparison route

### `scripts/julia_scripts/plotting/`

Subfolders: `posterior_stats/`, `bootstrap_ecdf/`, `videos/`, `legacy_step1/`, `diagnostics/`, `general/`. See `scripts/julia_scripts/plotting/README.md`.

### `scripts/python_plots/`

- `posterior_stats/` — step 2–4 injection-rate statistical grids
- Root scripts — forward comparison, posterior field summaries, video assembly

### `scripts/julia_scripts/data_collection/`

- `collect_all_injection_rates.jl`
  Aggregate injection-rate summaries across cases.
- `collect_cvar_only.jl`
  CVaR-only collection helper.
- `collect_pof_32_injection_rates.jl`
  POF-only collector for the 1..32 sample workflow.

### `scripts/julia_scripts/analysis/`

- Comparison and post-processing utilities for injection-rate and posterior analysis.
- Typical use: inspect or compare completed results, not submit fresh runs.

### `scripts/julia_scripts/utilities/`

- Diagnostics and one-off helpers for scaling, progress, gamma-table checks, and runtime inspection.

## Practical Conventions

- If a workflow writes large outputs, they should land under `data/`, `plots/`, or `logs/`, not in `scripts/`.
- `archive/` directories are historical reference material. Do not treat them as primary entry points.
- `scripts/gamma_tables/*.jld2` is a historical artifact from a deprecated POF/CVaR comparison route.
  Keep it only for reproducibility until the user explicitly authorizes cleanup.
- Python bytecode caches under `scripts/**/__pycache__/` are local artifacts and should remain ignored.

## Related Docs

- `docs/reference/DIRECTORY_STRUCTURE.md`
- `docs/README.md`
- `docs/historical/QUICK_START.md`
- `docs/workflow/SUBMIT_GUIDE.md`
