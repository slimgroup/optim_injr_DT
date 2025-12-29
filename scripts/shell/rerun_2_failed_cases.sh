#!/usr/bin/env bash
set -euo pipefail

# Re-run 2 failed cases from the 7 missing CVaR samples
# Job 3091343: DT_CVaR_g=0.01_a=0.05, sample=17 (environment initialization issue)
# Job 3091344: DT_CVaR_g=0.02_a=0.01, sample=64 (numerical issue)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace_7cases_fix.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

submit_one_sample () {
  local TAG="$1"; shift
  local ARGS="$1"; shift
  local SAMPLE="$1"; shift

  echo "[RERUN] ${TAG}  sample=${SAMPLE}"
  # Use explicit array range to override default array=1-32 in optim_inject_pace.sh
  sbatch --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
    --job-name="${TAG}_rerun_s${SAMPLE}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}"
}

# CVaR base arguments (aligned with submit_all.sh)
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

echo "=========================================="
echo "Re-running 2 failed cases from 7 missing CVaR samples"
echo "=========================================="

# Case 1: DT_CVaR_g=0.01_a=0.05 → missing sample 17 (environment initialization issue)
submit_one_sample \
  "DT_CVaR_g=0.01_a=0.05" \
  "${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.05" \
  17

# Case 2: DT_CVaR_g=0.02_a=0.01 → missing sample 64 (numerical issue)
submit_one_sample \
  "DT_CVaR_g=0.02_a=0.01" \
  "${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.01" \
  64

echo "=========================================="
echo "Total: 2 jobs submitted"
echo "=========================================="

