# Common Slurm shell-script patterns

This explains implementation patterns, not the repository's entry-point list.
Use [SCRIPTS_INDEX.md](SCRIPTS_INDEX.md) to choose a workflow.

| Pattern | Purpose and limits |
|---|---|
| `set -euo pipefail` | Fail on unset variables and many command/pipeline errors; Bash conditionals and other contexts have exceptions to `-e` |
| `module purge` | Clear loaded modules before constructing the job environment |
| `module load julia/1.11.3` | Load the configured Julia version; a fallback using `|| true` does not prove the load succeeded |
| `JULIA_DEPOT_PATH` | Select package/cache storage, separately from project activation |
| `PYTHON` | Select the Python interpreter used when configuring PyCall; verify the installed bridge/environment |
| `JULIA_PKG_PRECOMPILE_AUTO=0` | Disable automatic package-operation precompilation, not all compilation |
| `MPLBACKEND=Agg` | Use a noninteractive plotting backend |
| `OPENBLAS_NUM_THREADS=1`, `OMP_NUM_THREADS=1` | Limit those libraries' threads; not a guarantee that every operation is single-threaded |
| `cd "$SLURM_SUBMIT_DIR"` | Resolve relative project paths from the submission directory |
| `trap ... TERM` | Run the specified shell handler on TERM; an echo-only handler does not save simulation state |

Before launching Julia, keep the shared depot convention:

```bash
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
```

`--project=.` selects the project environment; it does not replace the package
depot or make packages reside in the project directory. Do not silently switch
to `~/.julia` or a repository-local depot. Install missing packages in the
shared depot according to the established workflow.

Create the `logs/` directory before `sbatch` so Slurm can open its output paths.
Log job IDs, configuration, and start time. A signal directive and trap must
match the actual process/checkpoint design; the old illustrative
`echo "SIGTERM received; try to save"` alone never implemented a checkpoint.

Machine-specific Python paths and resource settings from earlier revisions
are historical examples. Use [the current PACE setup](../workflow/PACE_RUN_GUIDE.md)
and preserve the existing batch interfaces during maintenance.
