# Project Directory Structure

## Current Top-Level Layout

```text
optim_injr_DT/
├── src/                        # Core Julia entry points and modules
├── scripts/                    # Operational scripts, plotting, and utilities
├── docs/                       # Project documentation
├── test/                       # Julia test suite
├── data/                       # Generated optimization outputs and analysis artifacts
├── plots/                      # Generated figures and paper assets
├── logs/                       # SLURM stdout/stderr and workflow logs
├── archive/                    # Superseded runs, logs, and code (reference only)
├── .cursor/                    # Tracked editor rule files
├── .vscode/                    # Local workspace settings (ignored)
├── .mplconfig/                 # Local Matplotlib cache (ignored)
└── .julia_depot*/              # Local Julia depots (ignored)
```

## `scripts/` Layout

```text
scripts/
├── shell/
│   ├── submit/                 # sbatch wrappers
│   ├── run/                    # bash drivers
│   ├── check/                  # progress & verification
│   ├── retry/                  # reruns & queue cleanup
│   └── maintenance/            # shell-only maintenance helpers
├── julia_scripts/
│   ├── plotting/               # Julia figure and video entry points
│   ├── data_collection/        # Aggregation scripts for finished runs
│   ├── analysis/               # Post-processing and comparison helpers
│   ├── utilities/              # Diagnostics, scaling, misc helpers
│   └── archive/                # Historical scripts kept for reference
├── python_plots/               # Python paper-figure assembly scripts
├── python_tools/               # Python maintenance / layout tools
├── gamma_tables/               # Historical gamma tables from a deprecated workflow
└── __pycache__/                # Local cache only; ignored
```

For actual script entry points and when to use them, see `docs/reference/SCRIPTS_INDEX.md`.

## Root Directory (Keep Tidy)

Keep the repository root limited to project metadata and agent-facing docs (for example `Project.toml`, `Manifest.toml`, `README.md`, `CLAUDE.md`, `AGENTS.md`). Put **SLURM / batch logs**, **submit logs**, and similar under **`logs/`**. Store large analysis artifacts such as **`data/three_set_posteriro_samples_t1_pof_cvar.jld2`** under **`data/`**. Small helper shell scripts (including `check_*.sh`) live under **`scripts/shell/`**; run them from the project root or rely on their internal `cd` to the repo root where noted.

## Local Tooling (Not In Git)

Editor- or machine-specific directories such as **`.julia_depot*/`** (project-local Julia depots), **`.mplconfig/`** (Matplotlib cache), and **`.vscode/`** (workspace settings) are listed in `.gitignore` and should not be committed. See **`docs/reference/MACHINE_LOCAL.md`** for what each folder does and when it is safe to delete. The tracked **`.cursor/rules/`** files are the exception: they encode shared repo guidance and are part of the project.

## `archive/` Layout

```text
archive/
├── 2026-04-07_step3_bad_sample_specific_injstart/   # bad step-3 campaign (data/plots/logs)
└── logs/2025-11-24_backup_logs/                     # former 11-24-2025_backup_logs/
```

See `archive/README.md`. Large archived logs are gitignored under `archive/logs/`.

## File Category Descriptions

### Core Modules (src/)
- Contains the main Julia module code for the project
- These files are referenced by other scripts

### Script Files (`scripts/`)
- **`shell/`**: SLURM submission, run, progress-check, and rerun helpers
- **`julia_scripts/`**: Julia plotting, collection, analysis, and utility scripts
- **`python_plots/`**: Python figure-assembly scripts for paper-quality plots
- **`python_tools/`**: Python maintenance and reorganization helpers
- **`gamma_tables/`**: historical gamma tables kept only for reproducibility of an older comparison workflow

### Data Files (`data/`)
- Experiment data, intermediate results, configuration files, etc.
- This directory is intentionally large and remains ignored by git.

### Image Files (`plots/`)
- All generated image files
- Organized by experiment type or figure family
- This directory is intentionally large and remains ignored by git.

### Logs (`logs/`)
- SLURM stdout/stderr, status captures, and workflow logs
- Organized by task type under `logs/optimization/`, `logs/utilities/`, and `logs/submit/`; see `logs/README.md`
- This directory is intentionally large and remains ignored by git.

### Documentation (`docs/`)
- **`workflow/`**: PACE submission, batch runs, progress checks
- **`reference/`**: directory layout, scripts index
- **`optimization/`**: optimizer choice, parameters, refactor notes
- **`statistics/`**: bootstrap/KDE methodology, figure layout
- **`analysis/`**: performance, solver, troubleshooting writeups
- **`historical/`**: deprecated gamma-table POF/CVaR comparison docs
- **`injection_rate_arrays.md`**: canonical injection ramps (kept at `docs/` root for stable references from `src/`)

### Tests (`test/`)
- **`unit/`**: Fast isolated tests (utils, risk metrics, I/O, optimization helpers)
- **`integration/`**: Heavier tests (e.g. forward-simulation `ds` verification)
- **`runtests.jl`**: Main test runner; see `test/README.md`

## File Naming Conventions

- Script files use lowercase letters and underscores: `plot_pof_cvar.py`
- Module files use lowercase letters and underscores: `optim_inject.jl`
- Data files use descriptive names: `injr_dist_1_to_32.jld2`

## Maintenance Guidelines

1. **New scripts**: Add to appropriate subdirectory in `scripts/`
2. **New data**: Add to appropriate subdirectory in `data/`
3. **New images**: Add to appropriate subdirectory in `plots/`
4. **Logs and submit output**: Keep under `logs/`, not repository root
5. **Old files**: Move to `archive/` directory instead of deleting directly
6. **Core modules**: Only modify files in `src/`, keep interfaces stable

## Notes

- The repository currently contains large local working directories: `data/`, `plots/`, and `logs/`.
- Local depots such as `.julia_depot_cursor/` and `.julia_depot_cdf/` are intentionally ignored rather than deleted.
- Some older docs and scripts still describe historical workflows; prefer the actual files present in `scripts/` when there is a mismatch.
- `scripts/gamma_tables/` and related helper scripts belong to a deprecated POF/CVaR comparison route and should not be treated as the recommended workflow.
- Do not delete historical gamma tables or their helper scripts without explicit user authorization.
