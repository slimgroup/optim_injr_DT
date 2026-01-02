#!/usr/bin/env bash
set -euo pipefail

# Submit CVaR case: gamma=0.2, alpha=0.01 (128 samples)
# This is the 4th case that failed due to QOS limit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

# CVaR base arguments
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

echo "[SUBMIT] DT_CVaR_g=0.2_a=0.01  samples=1-128"
sbatch --array=1-128 --chdir="${ROOT_DIR}" \
       --job-name="DT_CVaR_g=0.2_a=0.01" \
       --export=ALL,CASE_TAG="DT_CVaR_g=0.2_a=0.01",RISK_ARGS="${CVAR_BASE} --gamma_cvar 0.2 --alpha 0.01" \
       "${SBATCH_FILE}"

echo "Submitted: DT_CVaR_g=0.2_a=0.01 (128 samples)"

