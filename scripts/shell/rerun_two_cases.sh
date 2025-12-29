#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

submit_one_sample () {
  local TAG="$1"; shift
  local ARGS="$1"; shift
  local SAMPLE="$1"; shift

  echo "[RERUN] ${TAG}  sample=${SAMPLE}"
  # Use explicit array range to override default array=1-32 in optim_inject_pace.sh
  sbatch --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
    --job-name="${TAG}_rerun_${SAMPLE}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}"
}

CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

# =========== Only re-run missing samples ===========

# Case 1: DT_CVaR_g=0.05_a=0.01 → missing sample 17
submit_one_sample \
  "DT_CVaR_g=0.05_a=0.01" \
  "${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.01" \
  17

# Case 2: DT_CVaR_g=0.02_a=0.05 → missing sample 42
submit_one_sample \
  "DT_CVaR_g=0.02_a=0.05" \
  "${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.05" \
  42
