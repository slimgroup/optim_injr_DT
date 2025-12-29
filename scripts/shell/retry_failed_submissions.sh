#!/usr/bin/env bash
# Script to retry failed submissions from submit_smart.log
# Specifically handles the 3 cases that failed: alpha=0.01, 0.02, 0.05

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

# Function to check if already submitted
is_submitted() {
  local TAG="$1"
  local SAMPLE="$2"
  local jobname="${TAG}_s${SAMPLE}"
  
  if squeue -u $USER 2>/dev/null | grep -q "${jobname}"; then
    return 0
  fi
  
  if ls "${ROOT_DIR}/logs"/*${jobname}* 2>/dev/null | head -1 | grep -q . 2>/dev/null; then
    return 0
  fi
  
  return 1
}

# Failed cases: alpha=0.01, 0.02, 0.05 with gamma=0.0, samples 13-64
CASES=(
  "DT_CVaR_a=0.01_g=0.0|--alpha 0.01 --gamma_cvar 0.0"
  "DT_CVaR_a=0.02_g=0.0|--alpha 0.02 --gamma_cvar 0.0"
  "DT_CVaR_a=0.05_g=0.0|--alpha 0.05 --gamma_cvar 0.0"
)

SUBMITTED=0
SKIPPED=0
FAILED=0

echo "=========================================="
echo "Retrying Failed Submissions"
echo "Cases: alpha=0.01, 0.02, 0.05 (samples 13-64)"
echo "=========================================="
echo ""

for case_info in "${CASES[@]}"; do
  IFS='|' read -r TAG ALPHA_ARGS <<< "${case_info}"
  
  for sample in $(seq 13 64); do
    if is_submitted "${TAG}" "${sample}"; then
      echo "[SKIP] ${TAG} sample=${sample} (already submitted/completed)"
      ((SKIPPED++)) || true
      continue
    fi
    
    echo "[SUBMIT] ${TAG} sample=${sample}"
    RISK_ARGS="${CVAR_BASE} ${ALPHA_ARGS}"
    
    SBATCH_OUTPUT=$(sbatch --parsable --array="${sample}-${sample}" --chdir="${SCRIPT_DIR}/.." \
      --job-name="${TAG}_s${sample}" \
      --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${RISK_ARGS}" \
      "${SBATCH_FILE}" 2>&1)
    SBATCH_EXIT=$?
    
    if [ ${SBATCH_EXIT} -eq 0 ] && [[ "${SBATCH_OUTPUT}" =~ ^[0-9]+$ ]]; then
      echo "  → Job ID: ${SBATCH_OUTPUT}"
      ((SUBMITTED++)) || true
      sleep 0.1
    else
      echo "  ✗ Failed: ${SBATCH_OUTPUT}"
      ((FAILED++)) || true
    fi
  done
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Submitted: ${SUBMITTED}"
echo "Skipped: ${SKIPPED}"
echo "Failed: ${FAILED}"
echo ""

