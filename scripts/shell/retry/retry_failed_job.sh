#!/usr/bin/env bash
# Script to retry a single failed job
# Usage: bash scripts/shell/retry/retry_failed_job.sh DT_CVaR_a=0.0_g=0.01 2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <CASE_TAG> <SAMPLE>"
  echo "Example: $0 DT_CVaR_a=0.0_g=0.01 2"
  exit 1
fi

CASE_TAG="$1"
SAMPLE="$2"

# CVaR base arguments (same as in submit_11_cases_samples_2_64_smart.sh)
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

# Parse case tag to extract alpha and gamma
if [[ "${CASE_TAG}" =~ a=([0-9.]+)_g=([0-9.]+) ]]; then
  ALPHA="${BASH_REMATCH[1]}"
  GAMMA="${BASH_REMATCH[2]}"
  RISK_ARGS="${CVAR_BASE} --alpha ${ALPHA} --gamma_cvar ${GAMMA}"
else
  echo "ERROR: Cannot parse CASE_TAG: ${CASE_TAG}"
  echo "Expected format: DT_CVaR_a=<alpha>_g=<gamma>"
  exit 1
fi

echo "=========================================="
echo "Retrying Failed Job"
echo "=========================================="
echo "Case Tag: ${CASE_TAG}"
echo "Sample: ${SAMPLE}"
echo "Risk Args: ${RISK_ARGS}"
echo ""

# Submit the job
echo "Submitting job..."
JOB_NAME="${CASE_TAG}_s${SAMPLE}"
SBATCH_OUTPUT=$(sbatch --parsable --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
  --job-name="${JOB_NAME}" \
  --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}" \
  "${SBATCH_FILE}" 2>&1)
SBATCH_EXIT=$?

if [ ${SBATCH_EXIT} -eq 0 ] && [ -n "${SBATCH_OUTPUT}" ] && [[ "${SBATCH_OUTPUT}" =~ ^[0-9]+$ ]]; then
  echo "✓ Job submitted successfully!"
  echo "  Job ID: ${SBATCH_OUTPUT}"
  echo "  Job Name: ${JOB_NAME}"
  echo ""
  echo "You can monitor the job with:"
  echo "  squeue -j ${SBATCH_OUTPUT}"
  echo "  tail -f logs/out_${JOB_NAME}_${SBATCH_OUTPUT}_*.txt"
else
  echo "✗ Failed to submit job"
  echo "  Error: ${SBATCH_OUTPUT}"
  exit 1
fi

