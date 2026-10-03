#!/usr/bin/env bash
# Script to submit missing POF samples using optim_inject_7cases_fix.jl
# Missing samples:
#   - POF eps=0.01, sample 18
#   - POF eps=0.05, sample 64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

# POF base arguments
POF_BASE="--use_pof --pof_as_constraint --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime"

echo "=========================================="
echo "Submitting Missing POF Samples"
echo "=========================================="
echo ""

# Function to submit a single sample
submit_one_sample() {
  local TAG="$1"
  local EPS="$2"
  local SAMPLE="$3"
  local jobname="${TAG}_s${SAMPLE}"
  
  echo "[SUBMIT] ${TAG} sample=${SAMPLE}"
  
  # Submit the job
  JOBLINE=$(sbatch --parsable --array="${SAMPLE}" --chdir="${ROOT_DIR}" \
            --job-name="${jobname}" \
            --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${POF_BASE} --eps_pof ${EPS}" \
            "${SBATCH_FILE}" 2>&1)
  
  if [ $? -eq 0 ]; then
    JOBID="${JOBLINE%%_*}"
    echo "  -> Job submitted: ${JOBID}"
    return 0
  else
    echo "  -> ERROR: ${JOBLINE}"
    return 1
  fi
}

# Submit missing samples
echo "1. Submitting POF eps=0.01, sample 18..."
submit_one_sample "DT_POF_eps=0.01" "0.01" "18"

echo ""
echo "2. Submitting POF eps=0.05, sample 64..."
submit_one_sample "DT_POF_eps=0.05" "0.05" "64"

echo ""
echo "=========================================="
echo "Submission complete!"
echo "=========================================="
echo ""
echo "You can check job status with:"
echo "  squeue -u \$USER"
echo ""
echo "Check logs in: ${ROOT_DIR}/logs/"

