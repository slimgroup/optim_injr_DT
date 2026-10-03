#!/usr/bin/env bash
set -euo pipefail

# Submit 11 CVaR SOFT cases for sample 1 and sample 128
# Total: 11 cases × 2 samples = 22 jobs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

submit_one_sample () {
  local TAG="$1"; shift
  local ARGS="$1"; shift
  local SAMPLE="$1"; shift

  echo "[SUBMIT] ${TAG}  sample=${SAMPLE}"
  # Use explicit array range to override default array=1-32 in optim_inject_pace.sh
  sbatch --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
    --job-name="${TAG}_s${SAMPLE}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}"
}

# CVaR base arguments (aligned with submit_all.sh and rerun_two_cases.sh)
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

echo "=========================================="
echo "Submitting 11 CVaR cases for samples 1 and 128"
echo "=========================================="

# 8 cases: alpha=0.0 or 0.001, with various gamma values
for sample in 1 128; do
  # alpha=0.0, gamma=0.0, 0.01, 0.02, 0.05
  submit_one_sample "DT_CVaR_a=0.0_g=0.0"   "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.0" ${sample}
  submit_one_sample "DT_CVaR_a=0.0_g=0.01"  "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.01" ${sample}
  submit_one_sample "DT_CVaR_a=0.0_g=0.02"  "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.02" ${sample}
  submit_one_sample "DT_CVaR_a=0.0_g=0.05"  "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.05" ${sample}
  
  # alpha=0.001, gamma=0.0, 0.01, 0.02, 0.05
  submit_one_sample "DT_CVaR_a=0.001_g=0.0"   "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.0" ${sample}
  submit_one_sample "DT_CVaR_a=0.001_g=0.01"  "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.01" ${sample}
  submit_one_sample "DT_CVaR_a=0.001_g=0.02"  "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.02" ${sample}
  submit_one_sample "DT_CVaR_a=0.001_g=0.05"  "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.05" ${sample}
done

# 3 cases: alpha=0.01, 0.02, 0.05 with gamma=0.0
for sample in 1 128; do
  submit_one_sample "DT_CVaR_a=0.01_g=0.0" "${CVAR_BASE} --alpha 0.01 --gamma_cvar 0.0" ${sample}
  submit_one_sample "DT_CVaR_a=0.02_g=0.0" "${CVAR_BASE} --alpha 0.02 --gamma_cvar 0.0" ${sample}
  submit_one_sample "DT_CVaR_a=0.05_g=0.0" "${CVAR_BASE} --alpha 0.05 --gamma_cvar 0.0" ${sample}
done

echo "=========================================="
echo "Total: 11 cases × 2 samples = 22 jobs"
echo "=========================================="

