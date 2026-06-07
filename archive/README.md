# archive/

Cold storage for superseded runs, logs, and code — **not** part of the active workflow.

## Contents

| Path | Description |
|------|-------------|
| `2026-04-07_step3_bad_sample_specific_injstart/` | Step-3 campaign with incorrect per-sample `inj_start`; kept for audit (data, plots, logs). See its `README.md`. |
| `logs/2025-11-24_backup_logs/` | Former top-level `11-24-2025_backup_logs/` (~646M SLURM backup). Gitignored via `archive/logs/`. |

## Conventions

- Move old artifacts here instead of deleting when they may be needed for reproducibility.
- Do **not** point new SLURM scripts or docs at archived paths unless explicitly reproducing a historical run.
- Active SLURM logs belong under `logs/` at the repo root; run `scripts/python_tools/maintenance/organize_logs.py` to tidy.
