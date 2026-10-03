#!/usr/bin/env bash
set -euo pipefail

# Submit new CVaR cases with larger gamma values:
#   1. gamma=0.1, alpha=0.05 (128 samples)
#   2. gamma=0.2, alpha=0.05 (128 samples)
#   3. gamma=0.4, alpha=0.05 (128 samples)
# Total: 3 cases × 128 samples = 384 jobs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

# Chain submissions to avoid QOS submit limit
submit_chain () {
  local CASE_TAG="$1"; shift
  local RISK_ARGS="$*"
  local DEP_OPT="${DEP_OPT:-}"

  echo "[SUBMIT] ${CASE_TAG}  samples=1-128 ${DEP_OPT:+(dep ${DEP_OPT})}"
  # Override default array=1-32 in optim_inject_pace.sh to use 1-128
  JOBLINE=$(sbatch ${DEP_OPT} --array=1-128 --chdir="${ROOT_DIR}" \
           --job-name="${CASE_TAG}" \
           --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}" \
           "${SBATCH_FILE}")
  JOBID=$(awk '{print $4}' <<< "${JOBLINE}")
  echo "  -> jobid ${JOBID}"
  DEP_OPT="--dependency=afterany:${JOBID}"
}

# CVaR base arguments (aligned with submit_all.sh)
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

echo "=========================================="
echo "Submitting new CVaR cases (gamma=0.1, 0.2, 0.4) for 128 samples"
echo "=========================================="

DEP_OPT=""
# Case 1: gamma=0.1, alpha=0.05
submit_chain "DT_CVaR_g=0.1_a=0.05" ${CVAR_BASE} --gamma_cvar 0.1 --alpha 0.05

# Case 2: gamma=0.2, alpha=0.05
submit_chain "DT_CVaR_g=0.2_a=0.05" ${CVAR_BASE} --gamma_cvar 0.2 --alpha 0.05

# Case 3: gamma=0.4, alpha=0.05
submit_chain "DT_CVaR_g=0.4_a=0.05" ${CVAR_BASE} --gamma_cvar 0.4 --alpha 0.05

echo "=========================================="
echo "Total: 3 cases × 128 samples = 384 jobs"
echo "=========================================="

