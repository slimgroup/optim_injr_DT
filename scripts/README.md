# Scripts

Use the [script index](../docs/reference/SCRIPTS_INDEX.md) to choose an entry
point and [the reproduction guide](../docs/REPRODUCIBILITY.md) for execution order.
Run commands from the repository root.

| Directory | Role |
|---|---|
| `shell/submit/` | Batch-job scripts and submission wrappers |
| `shell/run/` | Runtime drivers |
| `shell/check/`, `shell/retry/` | Status checks and targeted recovery |
| `julia_scripts/data_collection/` | Aggregation and forward exports |
| `julia_scripts/plotting/` | Bootstrap ECDF, posterior statistics, and other plots |
| `python_plots/` | Paper rendering and optional presentation/video workflows |
| `python_tools/analysis/` | Post-processing audits |
| `python_tools/maintenance/` | Read-only checks and historical migration tools |
| `gamma_tables/` | Deprecated lookup artifact retained for provenance |

Scripts with `#SBATCH` resource directives use `sbatch`; wrappers that invoke
`sbatch` internally use `bash`. Heavy computation and rendering use compute
nodes. Store results under `data/`, figures under `plots/`, and logs under `logs/`.

Historical variants stay at their existing paths for compatibility. Old
`reorganize_*` and `patch_*_paths.py` migrations are not part of installation.
