# Script Entry Points

This page is a lightweight navigation guide for the current `scripts/` tree.
It is meant to answer: "which script should I start from?" without changing or
renaming the existing research workflow.

## High-Level Layout

```text
scripts/
├── shell/                 # SLURM submit/run/check helpers
├── julia_scripts/
│   ├── plotting/          # Julia plotting and figure-generation entry points
│   ├── data_collection/   # Aggregate results from finished runs
│   ├── analysis/          # Analysis / comparison utilities
│   ├── utilities/         # Diagnostics, scaling, tuning, misc helpers
│   └── archive/           # Historical scripts kept for reference
├── python_plots/          # Python-based paper figure assembly
├── gamma_tables/          # Versioned small lookup tables
└── __pycache__/           # Local cache only; ignored by git
```

## Main Entry Points

### Core optimization drivers

- `src/optim_inject.jl`
  Main optimization entry point. Keep CLI and batch-job assumptions stable.
- `src/threshold_sensitivity.jl`
  Threshold / calibration workflow entry point.

### Shell entry points in `scripts/shell/`

- `optim_inject_pace.sh`
  Main SLURM job entry point for array optimization runs on PACE.
- `submit_all.sh`
  Broad batch submission helper.
- `run_bootstrap_cdf.sh`
  Run the bootstrap CDF plotting pipeline on a compute node or interactive allocation.
- `submit_bootstrap_cdf.sh`
  SLURM wrapper for the bootstrap CDF plotting pipeline.
- `submit_video_generation.sh`
  Batch entry point for video-generation workflows.
- `submit_threshold_sensitivity.sh` style scripts do not currently exist in this tree.
  Use the scripts that are actually present under `scripts/shell/` instead of older doc names.

### Julia plotting entry points

- `scripts/julia_scripts/plotting/plot_bootstrap_panels.jl`
  Bootstrap histogram/CDF figures, including part-1 and grid modes.
- `scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl`
  POF vs CVaR threshold-sensitivity comparison figures.
- `scripts/julia_scripts/plotting/plot_perm_ensemble.jl`
  Julia version of permeability ensemble plotting.
- `scripts/julia_scripts/plotting/plot_fracture_comparison.jl`
  Forward-simulation comparison figure from Julia.
- `scripts/julia_scripts/plotting/generate_5case_videos.jl`
  Ground-truth forward videos for five control cases.
- `scripts/julia_scripts/plotting/generate_stat3case_videos.jl`
  Three-case statistical/video workflow.

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

- `submit_*`
  Job submission wrappers.
- `run_*`
  Direct execution wrappers for compute nodes or interactive sessions.
- `check_*`
  Progress, status, and verification helpers.
- `retry_*`, `rerun_*`, `cancel_*`
  Recovery and queue-management helpers.
- `move_*`
  File-placement helper scripts.

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
- `scripts/gamma_tables/*.jld2` is intentionally version-controlled; most other `.jld2` outputs are not.
- Python bytecode caches under `scripts/**/__pycache__/` are local artifacts and should remain ignored.

## Related Docs

- `docs/DIRECTORY_STRUCTURE.md`
- `docs/README.md`
- `docs/QUICK_START.md`
- `docs/SUBMIT_GUIDE.md`
