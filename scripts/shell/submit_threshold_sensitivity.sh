#!/bin/bash
#SBATCH --job-name=thresh_sens_128
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 12:00:00
#SBATCH -q inferno
#SBATCH --output=logs/threshold_sensitivity_%j.txt
#SBATCH --error=logs/threshold_sensitivity_%j.txt
#SBATCH --signal=TERM@60
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

# Quick run threshold sensitivity analysis (POF + CVaR enabled, auto-calibration)
# Estimated runtime: 1-3 hours (5 thresholds, 10 iterations each)

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment (PyCall stable, single-threaded plotting)
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

# Threshold list handling (supports SLURM array splitting)
THRESHOLD_VALUES="${THRESHOLD_VALUES:-2.0,3.0,4.0,5.0,6.0}"
THRESHOLD_VALUES="${THRESHOLD_VALUES//[$'\t\r\n ']/}"
IFS=',' read -r -a THRESH_ARRAY <<< "$THRESHOLD_VALUES"
THRESH_COUNT="${#THRESH_ARRAY[@]}"
if [[ "${THRESH_COUNT}" -eq 0 ]]; then
  echo "[ERROR] THRESHOLD_VALUES is empty. Set THRESHOLD_VALUES=2.0,3.0,... before submitting." >&2
  exit 1
fi

if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  TASK_ID="${SLURM_ARRAY_TASK_ID}"
  if (( TASK_ID < 1 || TASK_ID > THRESH_COUNT )); then
    echo "[ERROR] SLURM_ARRAY_TASK_ID=${TASK_ID} outside valid range 1-${THRESH_COUNT}" >&2
    exit 2
  fi
  SELECTED_THRESHOLD="${THRESH_ARRAY[$((TASK_ID-1))]}"
  echo "Split run detected: task ${TASK_ID}/${SLURM_ARRAY_TASK_MAX:-$THRESH_COUNT} -> threshold=${SELECTED_THRESHOLD} MPa"
  THRESH_ARGS=(--threshold_list "${SELECTED_THRESHOLD}" --split_threshold_jobs --split_job_index "${TASK_ID}" --split_job_total "${THRESH_COUNT}" --merge_results)
else
  echo "Running all thresholds in a single job: ${THRESHOLD_VALUES}"
  THRESH_ARGS=(--threshold_list "${THRESHOLD_VALUES}")
fi

trap 'echo "[WARN] SIGTERM received; try to save…"' TERM

# Change to project directory
cd "$SLURM_SUBMIT_DIR"

echo "Job started at $(date)"
echo "Running threshold sensitivity analysis (fast mode)"

# Run Julia script
julia --project="$SLURM_SUBMIT_DIR" -t 1 src/threshold_sensitivity.jl \
  --idx_num 128 \
  --use_pof \
  --use_cvar \
  --eps_pof 0.01 \
  --lambda_pof 1.0 \
  --lambda_cvar 1.0 \
  --calibrate_gamma \
  --niterations 10 \
  --grad_forward \
  --threshold_num 5 \
  --threshold_min 2.0 \
  --threshold_max 6.0 \
  "${THRESH_ARGS[@]}"

echo "Job completed at $(date)"

