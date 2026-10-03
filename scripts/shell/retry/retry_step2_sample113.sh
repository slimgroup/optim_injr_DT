#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

SAMPLE="${1:-113}"
MEMORY="${MEMORY:-32G}"
WALLTIME="${WALLTIME:-48:00:00}"
JOB_NAME="DT_step2_POF_eps0.0_prior_paired_retry${SAMPLE}"
CASE_TAG="DT_step2_POF_eps=0.0_prior=paired"

RISK_ARGS="--monitoring_step 2 --case_key pof_eps0.0 \
           --use_pof --pof_as_constraint \
           --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
           --eps_pof 0.0 --risk_mode relative --weight_mode voltime \
           --prior_mode paired_posterior_sample"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

echo "Submitting step-2 paired posterior rerun"
echo "  sample:   ${SAMPLE}"
echo "  memory:   ${MEMORY}"
echo "  walltime: ${WALLTIME}"
echo "  job name: ${JOB_NAME}"
echo "  case tag: ${CASE_TAG}"
echo "  risk args: ${RISK_ARGS}"

JOBID=$(sbatch --parsable --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
  --job-name="${JOB_NAME}" \
  --mem="${MEMORY}" \
  --time="${WALLTIME}" \
  --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}" \
  "${SBATCH_FILE}")

echo "Submitted job ${JOBID}"
echo "Monitor with:"
echo "  scontrol show job ${JOBID}"
echo "  squeue -j ${JOBID}"
echo "  tail -f ${ROOT_DIR}/logs/out_${JOB_NAME}_${JOBID}_${SAMPLE}.txt"
