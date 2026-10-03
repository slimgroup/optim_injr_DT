# archive/

Cold storage for superseded runs, logs, and code — **not** part of the active workflow.

## Contents

| Path | Description |
|------|-------------|
| `2026-04-07_step3_bad_sample_specific_injstart/` | Step-3 campaign with incorrect per-sample `inj_start`; kept for audit (data, plots, logs). See its `README.md`. |
| `logs/2025-11-24_backup_logs/` | Former top-level `11-24-2025_backup_logs/` (644.38 MiB of SLURM logs). Gitignored via `archive/logs/`. |
| `figure_previews/` | 19 superseded layout-preview folders archived on 2026-10-03; contents verified against the cleanup receipt. Local only. |

The [2026-10-03 review](../docs/reference/SCRIPTS_AND_ARCHIVE_REVIEW_2026-10-03.md)
lists file counts, sizes, provenance dependencies, and deletion candidates.
No additional archive deletion was authorized by that review. Archived code
under `src/archive/` and `scripts/julia_scripts/archive/` is documented there
separately because it retains executable callers.

## Conventions

- Move old artifacts here instead of deleting when they may be needed for reproducibility.
- Do **not** point new SLURM scripts or docs at archived paths unless explicitly reproducing a historical run.
- Active SLURM logs belong under `logs/` at the repo root; run `scripts/python_tools/maintenance/organize_logs.py` to tidy.
