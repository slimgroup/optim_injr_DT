# Running on PACE

Run from the repository root. Batch scripts retain PACE account and module
settings; inspect them before running on another cluster or allocation.

## Environment

Inside your usual interactive compute allocation:

```bash
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export MPLBACKEND=Agg
export JULIA_PKG_PRECOMPILE_AUTO=0
mkdir -p logs
```

For a new PyCall installation, set `PYTHON` to the chosen environment before
building PyCall. Existing wrappers retain their configured PACE Python path.
Do not switch that environment during an active campaign.

## Submission patterns

Scripts that call `sbatch` internally are run with `bash`:

```bash
bash scripts/shell/submit/submit_step3_paired_smoketest.sh \
  --case pof_eps0.01 --samples 1-2
bash scripts/shell/submit/submit_step4_paired_all.sh \
  --case all --samples 1-128
```

Scripts with `#SBATCH` resource directives use `sbatch`:

```bash
sbatch scripts/shell/submit/submit_bootstrap_cdf.sh
sbatch scripts/shell/submit/submit_posterior_margin_sensitivity.sh \
  --mode increment --factor 1.13 \
  --output plots/paper_figures/NEW_posterior_margin_1p13
```

The lower-level `scripts/shell/run/optim_inject_pace.sh` requires `CASE_TAG`
and `RISK_ARGS` from its submitter. Do not invoke it without that environment.

## Data and status

Read [the reproduction guide](../REPRODUCIBILITY.md) for previous-step inputs
and shared starting rates. Create `logs/` before submission: Slurm opens the
output files before executing the job's shell commands.

```bash
squeue -u "$USER"
bash scripts/shell/check/check_step2_progress.sh
```

Lightweight checks can run on the login node. Optimization, forward simulation,
multi-file posterior rendering, and videos must use compute nodes. Recheck
sandboxed Slurm connectivity failures outside the sandbox before diagnosing
a controller outage.

The [old gamma-table guide](../historical/workflow/PACE_RUN_GUIDE.md) describes
a separate deprecated comparison workflow.
