#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"

CASE_KEY="pof_eps0.01"
JOB_ID=""
PATTERN=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/shell/check_step3_smoketest_logs.sh [--case CASE_KEY] [--job JOBID] [--pattern TEXT]

Options:
  --case      One of: pof_eps0.0, pof_eps0.01, cvar_g0.1_a0.01
  --job       Slurm base job id, used to match logs like *_JOBID_*.txt
  --pattern   Extra filename substring filter when job id is unknown

Examples:
  bash scripts/shell/check_step3_smoketest_logs.sh --case pof_eps0.01 --job 1234567
  bash scripts/shell/check_step3_smoketest_logs.sh --case pof_eps0.01 --pattern paired
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case)
      CASE_KEY="$2"; shift 2;;
    --job)
      JOB_ID="$2"; shift 2;;
    --pattern)
      PATTERN="$2"; shift 2;;
    -h|--help)
      usage
      exit 0;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 1;;
  esac
done

case "${CASE_KEY}" in
  pof_eps0.0)
    EXPECTED_POST_KEY="X_post1"
    EXPECTED_ENDPOINT="0.04489"
    CASE_HINT="eps=0.0"
    ;;
  pof_eps0.01)
    EXPECTED_POST_KEY="X_post2"
    EXPECTED_ENDPOINT="0.07317"
    CASE_HINT="eps=0.01"
    ;;
  cvar_g0.1_a0.01)
    EXPECTED_POST_KEY="X_post3"
    EXPECTED_ENDPOINT="0.11529"
    CASE_HINT="CVaR_g=0.1_a=0.01"
    ;;
  *)
    echo "Unsupported case: ${CASE_KEY}" >&2
    exit 1
    ;;
esac

if [[ ! -d "${LOG_DIR}" ]]; then
  echo "Logs directory not found: ${LOG_DIR}" >&2
  exit 1
fi

declare -a FILES=()

if [[ -n "${JOB_ID}" ]]; then
  while IFS= read -r file; do
    FILES+=("${file}")
  done < <(find "${LOG_DIR}" -maxdepth 1 -type f | sort | rg "_${JOB_ID}_" || true)
else
  while IFS= read -r file; do
    FILES+=("${file}")
  done < <(find "${LOG_DIR}" -maxdepth 1 -type f | sort | rg "step3|paired|${CASE_HINT}" || true)
fi

if [[ -n "${PATTERN}" ]]; then
  FILTERED=()
  for file in "${FILES[@]}"; do
    if [[ "${file}" == *"${PATTERN}"* ]]; then
      FILTERED+=("${file}")
    fi
  done
  FILES=("${FILTERED[@]}")
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No matching log files found."
  echo "Checked in: ${LOG_DIR}"
  if [[ -n "${JOB_ID}" ]]; then
    echo "Filter: job id ${JOB_ID}"
  else
    echo "Filter: step3/paired/${CASE_HINT}"
  fi
  [[ -n "${PATTERN}" ]] && echo "Extra pattern: ${PATTERN}"
  exit 1
fi

echo "Matched log files:"
printf '  %s\n' "${FILES[@]}"
echo ""

echo "Key smoke-test signals:"
rg -n \
  "posterior_key|Matched permeability sample|Using case-level inj_start|Recovered previous-step endpoint" \
  "${FILES[@]}" || true
echo ""

echo "Case-specific expectations for ${CASE_KEY}:"
rg -n \
  "${EXPECTED_POST_KEY}|idx_t3|case-level inj_start|${EXPECTED_ENDPOINT}" \
  "${FILES[@]}" || true
