# Submission guide

Use [the current PACE guide](PACE_RUN_GUIDE.md),
[the script index](../reference/SCRIPTS_INDEX.md), and
[the reproduction order](../REPRODUCIBILITY.md). Submit from the repository
root with `logs/` created. Wrappers that call `sbatch` internally run with
`bash`; scripts with their own Slurm directives run with `sbatch`.

Read-only job inspection:

```bash
squeue -u "$USER"
scontrol show job JOB_ID
```

Inspect the stdout/stderr paths recorded for that job. Cancel a job only when
that specific cancellation is intended and authorized; repository maintenance
does not imply permission to cancel running experiments.

The previous version of this file described fast/full threshold-sensitivity
jobs with eight CPUs, 32 GB, and 12/24-hour limits. That gamma-table comparison
workflow was [retired on 2026-10-03](../reference/DELETION_REVIEW_2026-10-03.md).
Its runtime estimates and old `summary__sample=128.jld2` paths are historical,
not current submission instructions.
