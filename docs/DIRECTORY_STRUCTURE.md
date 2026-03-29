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
├── .cursor/                    # Tracked editor rule files
├── .vscode/                    # Local workspace settings (ignored)
├── .mplconfig/                 # Local Matplotlib cache (ignored)
└── .julia_depot*/              # Local Julia depots (ignored)
```

## `scripts/` Layout

```text
scripts/
├── shell/                      # SLURM submit/run/check helpers
├── julia_scripts/
│   ├── plotting/               # Julia figure and video entry points
│   ├── data_collection/        # Aggregation scripts for finished runs
│   ├── analysis/               # Post-processing and comparison helpers
│   ├── utilities/              # Diagnostics, scaling, misc helpers
│   └── archive/                # Historical scripts kept for reference
├── python_plots/               # Python paper-figure assembly scripts
├── gamma_tables/               # Small version-controlled lookup tables
└── __pycache__/                # Local cache only; ignored
```

For actual script entry points and when to use them, see `docs/SCRIPTS_INDEX.md`.

## Root Directory (Keep Tidy)

Keep the repository root limited to project metadata and agent-facing docs (for example `Project.toml`, `Manifest.toml`, `README.md`, `CLAUDE.md`, `AGENTS.md`). Put **SLURM / batch logs**, **submit logs**, and similar under **`logs/`**. Store large analysis artifacts such as **`data/three_set_posteriro_samples_t1_pof_cvar.jld2`** under **`data/`**. Small helper shell scripts (including `check_*.sh`) live under **`scripts/shell/`**; run them from the project root or rely on their internal `cd` to the repo root where noted.

## Local Tooling (Not In Git)

Editor- or machine-specific directories such as **`.julia_depot*/`** (project-local Julia depots), **`.mplconfig/`** (Matplotlib cache), and **`.vscode/`** (workspace settings) are listed in `.gitignore` and should not be committed. The tracked **`.cursor/rules/`** files are the exception: they encode shared repo guidance and are part of the project.

## File Category Descriptions

### Core Modules (src/)
- Contains the main Julia module code for the project
- These files are referenced by other scripts

### Script Files (`scripts/`)
- **`shell/`**: SLURM submission, run, progress-check, and rerun helpers
- **`julia_scripts/`**: Julia plotting, collection, analysis, and utility scripts
- **`python_plots/`**: Python figure-assembly scripts for paper-quality plots
- **`gamma_tables/`**: small lookup tables intentionally kept in git

### Data Files (`data/`)
- Experiment data, intermediate results, configuration files, etc.
- This directory is intentionally large and remains ignored by git.

### Image Files (`plots/`)
- All generated image files
- Organized by experiment type or figure family
- This directory is intentionally large and remains ignored by git.

### Logs (`logs/`)
- SLURM stdout/stderr, status captures, and workflow logs
- This directory is intentionally large and remains ignored by git.

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
