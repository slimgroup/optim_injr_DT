#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/shell/submit_pof_sensitivity.sh
#   scripts/shell/submit_pof_sensitivity.sh -s 17
#   scripts/shell/submit_pof_sensitivity.sh -s 1-64

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"     # repo root directory
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"  # pace script in this directory

# Default sample range = 1-32 (consistent with your current optim_inject_pace.sh)
SAMPLE_RANGE="1-32"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--samples)
      SAMPLE_RANGE="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

[[ -f "${SBATCH_FILE}" ]] || { echo "ERROR: Cannot find ${SBATCH_FILE}"; exit 1; }

# Common POF parameters
POF_BASE="--use_pof --pof_as_constraint \
          --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
          --risk_mode relative --weight_mode voltime"

# Five new eps values to add
EPS_LIST=(0.0005 0.002 0.003 0.005 0.03)

DEP_OPT=""

submit_one () {
  local eps="$1"
  local tag="DT_POF_eps=${eps}"

  echo "[SUBMIT] ${tag}  samples=${SAMPLE_RANGE} ${DEP_OPT:+(dep ${DEP_OPT})}"
  jobline=$(sbatch ${DEP_OPT} --parsable --array="${SAMPLE_RANGE}" --chdir="${ROOT_DIR}" \
            --job-name="${tag}" \
            --export=ALL,CASE_TAG="${tag}",RISK_ARGS="${POF_BASE} --eps_pof ${eps}" \
            "${SBATCH_FILE}")
  jobid="${jobline%%_*}"
  echo "  -> jobid ${jobid}"
  DEP_OPT="--dependency=afterany:${jobid}"
}

for eps in "${EPS_LIST[@]}"; do
  submit_one "${eps}"
done
