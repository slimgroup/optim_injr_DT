#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

CASE_KEY="pof_eps0.01"
SAMPLE_RANGE="1-2"
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
      echo "Usage: $0 [--case pof_eps0.01|pof_eps0.0|cvar_g0.1_a0.01] [--samples 1-2] [--mem 64G] [--time 24:00:00]"
      exit 1;;
  esac
done

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

case "${CASE_KEY}" in
  pof_eps0.0)
    JOB_NAME="DT_step4_POF_eps=0.0_prior=paired_smoke"
    CASE_TAG="DT_step4_POF_eps=0.0_prior=paired"
    RISK_ARGS="--monitoring_step 4 --case_key pof_eps0.0 \
               --use_pof --pof_as_constraint \
               --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
               --eps_pof 0.0 --risk_mode relative --weight_mode voltime \
               --prior_mode paired_posterior_sample"
    ;;
  pof_eps0.01)
    JOB_NAME="DT_step4_POF_eps=0.01_prior=paired_smoke"
    CASE_TAG="DT_step4_POF_eps=0.01_prior=paired"
    RISK_ARGS="--monitoring_step 4 --case_key pof_eps0.01 \
               --use_pof --pof_as_constraint \
               --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
               --eps_pof 0.01 --risk_mode relative --weight_mode voltime \
               --prior_mode paired_posterior_sample"
    ;;
  cvar_g0.1_a0.01)
    JOB_NAME="DT_step4_CVaR_g=0.1_a=0.01_prior=paired_smoke"
    CASE_TAG="DT_step4_CVaR_g=0.1_a=0.01_prior=paired"
    RISK_ARGS="--monitoring_step 4 --case_key cvar_g0.1_a0.01 \
               --use_cvar --cvar_as_constraint --cvar_soft \
               --lambda_cvar 3.0e9 --kappa_cvar 50 \
               --gamma_cvar 0.1 --alpha 0.01 \
               --risk_mode relative --weight_mode voltime \
               --prior_mode paired_posterior_sample"
    ;;
  *)
    echo "Unsupported case: ${CASE_KEY}"
    echo "Supported cases: pof_eps0.0, pof_eps0.01, cvar_g0.1_a0.01"
    exit 1
    ;;
esac

echo "Submitting step-4 paired-posterior smoke test"
echo "  case key: ${CASE_KEY}"
echo "  samples:  ${SAMPLE_RANGE}"
echo "  memory:   ${MEMORY}"
echo "  walltime: ${WALLTIME}"
echo "  job name: ${JOB_NAME}"
echo "  case tag: ${CASE_TAG}"
echo "  risk args: ${RISK_ARGS}"

JOBID=$(sbatch --parsable --array="${SAMPLE_RANGE}" --chdir="${ROOT_DIR}" \
  --job-name="${JOB_NAME}" \
  --mem="${MEMORY}" \
  --time="${WALLTIME}" \
  --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}" \
  "${SBATCH_FILE}")

echo "Submitted job ${JOBID}"
echo "Monitor with:"
echo "  scontrol show job ${JOBID%%_*}"
echo "  squeue -j ${JOBID%%_*}"
