#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

CASE_KEY="all"
SAMPLE_RANGE="${SAMPLE_RANGE:-1-128}"
MEMORY="${MEMORY:-64G}"
WALLTIME="${WALLTIME:-24:00:00}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--case)
      CASE_KEY="$2"; shift 2;;
    -s|--samples)
      SAMPLE_RANGE="$2"; shift 2;;
    -m|--mem)
      MEMORY="$2"; shift 2;;
    -t|--time)
      WALLTIME="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"
      echo "Usage: $0 [--case all|pof_eps0.0|pof_eps0.01|cvar_g0.1_a0.01] [--samples 1-128] [--mem 64G] [--time 24:00:00]"
      exit 1;;
  esac
done

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

submit_case () {
  local case_key="$1"
  local job_name case_tag risk_args

  case "${case_key}" in
    pof_eps0.0)
      job_name="DT_step4_POF_eps=0.0_prior=paired"
      case_tag="DT_step4_POF_eps=0.0_prior=paired"
      risk_args="--monitoring_step 4 --case_key pof_eps0.0 \
                 --use_pof --pof_as_constraint \
                 --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
                 --eps_pof 0.0 --risk_mode relative --weight_mode voltime \
                 --prior_mode paired_posterior_sample"
      ;;
    pof_eps0.01)
      job_name="DT_step4_POF_eps=0.01_prior=paired"
      case_tag="DT_step4_POF_eps=0.01_prior=paired"
      risk_args="--monitoring_step 4 --case_key pof_eps0.01 \
                 --use_pof --pof_as_constraint \
                 --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
                 --eps_pof 0.01 --risk_mode relative --weight_mode voltime \
                 --prior_mode paired_posterior_sample"
      ;;
    cvar_g0.1_a0.01)
      job_name="DT_step4_CVaR_g=0.1_a=0.01_prior=paired"
      case_tag="DT_step4_CVaR_g=0.1_a=0.01_prior=paired"
      risk_args="--monitoring_step 4 --case_key cvar_g0.1_a0.01 \
                 --use_cvar --cvar_as_constraint --cvar_soft \
                 --lambda_cvar 3.0e9 --kappa_cvar 50 \
                 --gamma_cvar 0.1 --alpha 0.01 \
                 --risk_mode relative --weight_mode voltime \
                 --prior_mode paired_posterior_sample"
      ;;
    *)
      echo "Unsupported case: ${case_key}"
      return 1
      ;;
  esac

  echo "[SUBMIT] ${job_name}"
  echo "  samples:  ${SAMPLE_RANGE}"
  echo "  memory:   ${MEMORY}"
  echo "  walltime: ${WALLTIME}"
  echo "  risk args: ${risk_args}"

  local jobid
  jobid=$(sbatch --parsable --array="${SAMPLE_RANGE}" --chdir="${ROOT_DIR}" \
    --job-name="${job_name}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    --export=ALL,CASE_TAG="${case_tag}",RISK_ARGS="${risk_args}" \
    "${SBATCH_FILE}")

  echo "  -> jobid ${jobid}"
}

case "${CASE_KEY}" in
  all)
    submit_case pof_eps0.0
    submit_case pof_eps0.01
    submit_case cvar_g0.1_a0.01
    ;;
  pof_eps0.0|pof_eps0.01|cvar_g0.1_a0.01)
    submit_case "${CASE_KEY}"
    ;;
  *)
    echo "Unsupported case selector: ${CASE_KEY}"
    echo "Supported values: all, pof_eps0.0, pof_eps0.01, cvar_g0.1_a0.01"
    exit 1
    ;;
esac
