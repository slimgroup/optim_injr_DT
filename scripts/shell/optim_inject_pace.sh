#!/bin/bash
#SBATCH --job-name=DT_case
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-32
#SBATCH --output=logs/out_%x_%A_%a.txt
#SBATCH --error=logs/err_%x_%A_%a.txt
#SBATCH --signal=TERM@60
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

set -euo pipefail
module purge
module load julia/1.10.1 2>/dev/null || true

# Fixed environment (PyCall stable, single-threaded plotting)
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

trap 'echo "[WARN] SIGTERM received; try to save…"' TERM

# -------- Variables passed from submit_all.sh --------
: "${CASE_TAG:?Missing CASE_TAG}"       # Tag for directory naming and log identification
: "${RISK_ARGS:?Missing RISK_ARGS}"     # Risk parameter combination for this case

# Common training parameters (latest version)
TRAIN_ARGS="--niterations 40 --inj_guess 0.20"

# Lambda suggestions (only print suggestions, don't change values)
TUNING_HINTS="--target_share 0.01 --delta_ref 0.01"

# Optional: save frequency/forward gradient
COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

# sample id = array id
task_id=${SLURM_ARRAY_TASK_ID}
EXP_NAME="step1"

# Change back to submission directory to ensure relative paths and project root are correct
cd "$SLURM_SUBMIT_DIR"

echo "JOB ${SLURM_JOB_ID}.${SLURM_ARRAY_TASK_ID}"
echo "CASE_TAG=${CASE_TAG}"
echo "RISK_ARGS=${RISK_ARGS}"
echo "IDX_NUM=${task_id}"

# Run (no longer pass --output_dir; use project root as --project)
julia --project="$SLURM_SUBMIT_DIR" -t 1 src/optim_inject.jl \
  --idx_num "${task_id}" \
  ${RISK_ARGS} ${TRAIN_ARGS} ${TUNING_HINTS} ${COMMON_ARGS}
