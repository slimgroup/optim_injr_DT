#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES_FILE="${ROOT}/src/cases.list"
SAMPLE_RANGE="${1:-1-128}"   # 可传 33-128

FIRST_LINE=$(head -n1 "${CASES_FILE}")
CASE_TAG="${FIRST_LINE%%|*}"
RISK_ARGS="${FIRST_LINE#*|}"

echo "[LAUNCH] ${CASE_TAG}  samples=${SAMPLE_RANGE}"
sbatch --array="${SAMPLE_RANGE}" --chdir="${ROOT}" \
  --job-name="${CASE_TAG}" \
  --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}",CASE_IDX=1,CASES_FILE="${CASES_FILE}",SAMPLE_RANGE="${SAMPLE_RANGE}" \
  src/optim_inject_pace.sh
