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
| `python_tools/maintenance/` | Repository checks, artifact assembly, and maintenance helpers |

Scripts with `#SBATCH` resource directives use `sbatch`; wrappers that invoke
`sbatch` internally use `bash`. Heavy computation and rendering use compute
nodes. Store results under `data/`, figures under `plots/`, and logs under `logs/`.

Historical variants with retained callers stay at their existing paths.
The deprecated gamma-table workflow and completed one-time path migrations
were removed after review; see [the deletion record](../docs/reference/DELETION_REVIEW_2026-10-03.md).

The [scripts and archive review](../docs/reference/SCRIPTS_AND_ARCHIVE_REVIEW_2026-10-03.md)
records the remaining historical callers, local archive contents, and possible
future retirements. An `archive` or `legacy` directory name does not establish
that its code is unused.
