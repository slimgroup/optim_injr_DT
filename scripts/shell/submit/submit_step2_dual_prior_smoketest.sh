#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"
SAMPLE_RANGE="1-32"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--samples)
      SAMPLE_RANGE="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

submit_bucket() {
  local case_tag="$1"; shift
  local risk_args="$*"
  local jobline
  local jobid

  echo "[SUBMIT] ${case_tag}  samples=${SAMPLE_RANGE}"
  jobline=$(sbatch --parsable --array="${SAMPLE_RANGE}" --chdir="${ROOT_DIR}" \
    --job-name="${case_tag}" \
    --export=ALL,CASE_TAG="${case_tag}",RISK_ARGS="${risk_args}" \
    "${SBATCH_FILE}")
  jobid="${jobline%%_*}"
  echo "  -> jobid ${jobid}"
}

POF_BASE="--monitoring_step 2 --case_key pof_eps0.01 \
          --use_pof --pof_as_constraint \
          --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
          --eps_pof 0.01 --risk_mode relative --weight_mode voltime"

CVAR_BASE="--monitoring_step 2 --case_key cvar_g0.1_a0.01 \
           --use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --gamma_cvar 0.1 --alpha 0.01 \
           --risk_mode relative --weight_mode voltime"

echo "Submitting step-2 dual-prior smoke test for samples ${SAMPLE_RANGE}"
echo "Buckets:"
echo "  1. POF eps=0.01 + pointwise_median"
echo "  2. POF eps=0.01 + paired_posterior_sample"
echo "  3. CVaR gamma=0.1 alpha=0.01 + pointwise_median"
echo "  4. CVaR gamma=0.1 alpha=0.01 + paired_posterior_sample"

submit_bucket "DT_step2_POF_eps=0.01_prior=pointwise_median" \
  ${POF_BASE} --prior_mode pointwise_median

submit_bucket "DT_step2_POF_eps=0.01_prior=paired" \
  ${POF_BASE} --prior_mode paired_posterior_sample

submit_bucket "DT_step2_CVaR_g=0.1_a=0.01_prior=pointwise_median" \
  ${CVAR_BASE} --prior_mode pointwise_median

submit_bucket "DT_step2_CVaR_g=0.1_a=0.01_prior=paired" \
  ${CVAR_BASE} --prior_mode paired_posterior_sample
