# julia_scripts/

Julia analysis, plotting, and collection scripts (non-SLURM entry points).

```text
julia_scripts/
├── plotting/          # figures & videos (subfolders by workflow)
├── data_collection/   # aggregate finished-run CSV/JLD2 and forward exports
│   └── forward_exports/
├── analysis/          # inj-rate / posterior comparisons
├── utilities/         # scaling, diagnostics, and retained tutorial
└── archive/           # Cruyff driver and DrWatson tutorial helper
```

See `plotting/README.md` for the plotting sub-tree and
`data_collection/README.md` for export/aggregation scripts.

The archived Cruyff driver still has two shell callers. The small archived
tutorial helper is used by `utilities/intro.jl`. Neither is a current paper
entry point. See the [scripts and archive review](../../docs/reference/SCRIPTS_AND_ARCHIVE_REVIEW_2026-10-03.md)
before retiring either workflow.
