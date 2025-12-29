#!/usr/bin/env bash
set -euo pipefail

# Submit 11 CVaR SOFT cases for samples 2 to 64
# Total: 11 cases × 63 samples = 693 jobs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"  # Project root for logs
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

# Function to check if a sample for a case is already submitted
# Simplified for speed - only check queue and logs
is_submitted() {
  local TAG="$1"
  local SAMPLE="$2"
  local jobname="${TAG}_s${SAMPLE}"
  
  # Method 1: Check queue (fast and reliable)
  if squeue -u $USER 2>/dev/null | grep -q "${jobname}"; then
    return 0  # Already in queue
  fi
  
  # Method 2: Check logs files (logs are in project root logs/ directory)
  # ROOT_DIR is already project root
  local logs_dir="${ROOT_DIR}/logs"
  # Use || true to prevent script exit if ls fails
  if ls "${logs_dir}"/*${jobname}* 2>/dev/null | head -1 | grep -q . || false; then
    return 0  # Has logs, assume already processed
  fi
  
  return 1  # Not submitted
}

submit_one_sample () {
  local TAG="$1"; shift
  local ARGS="$1"; shift
  local SAMPLE="$1"; shift

  # Check if already submitted (use || true to prevent exit on error)
  if is_submitted "${TAG}" "${SAMPLE}" 2>/dev/null || true; then
    echo "[SKIP] ${TAG}  sample=${SAMPLE} (already submitted/completed)" >&2
    return 1
  fi

  echo "[SUBMIT] ${TAG}  sample=${SAMPLE}" >&2
  # Use explicit array range to override default array=1-32 in optim_inject_pace.sh
  # Use --parsable for faster submission and suppress output
  if sbatch --parsable --array="${SAMPLE}-${SAMPLE}" --chdir="${SCRIPT_DIR}/.." \
    --job-name="${TAG}_s${SAMPLE}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}" > /dev/null 2>&1; then
    # Small delay to avoid overwhelming sbatch
    sleep 0.02
    return 0
  else
    echo "[ERROR] Failed to submit ${TAG} sample=${SAMPLE}" >&2
    return 1
  fi
}

# CVaR base arguments (aligned with submit_all.sh and rerun_two_cases.sh)
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

SUBMITTED_COUNT=0
SKIPPED_COUNT=0

echo "=========================================="
echo "Submitting 11 CVaR cases for samples 2-64"
echo "Total: 11 cases × 63 samples = 693 jobs"
echo "This script will skip already submitted/completed jobs"
echo "=========================================="

# Generate sample list from 2 to 64
SAMPLES=($(seq 2 64))

# 8 cases: alpha=0.0 or 0.001, with various gamma values
for sample in "${SAMPLES[@]}"; do
  # alpha=0.0, gamma=0.0, 0.01, 0.02, 0.05
  if submit_one_sample "DT_CVaR_a=0.0_g=0.0"   "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.0" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.0_g=0.01"  "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.01" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.0_g=0.02"  "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.02" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.0_g=0.05"  "${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.05" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  
  # alpha=0.001, gamma=0.0, 0.01, 0.02, 0.05
  if submit_one_sample "DT_CVaR_a=0.001_g=0.0"   "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.0" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.001_g=0.01"  "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.01" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.001_g=0.02"  "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.02" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.001_g=0.05"  "${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.05" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  
  # Progress report every 10 samples
  if (( sample % 10 == 0 )) 2>/dev/null || true; then
    echo "[PROGRESS] Processed samples up to ${sample}: Submitted=${SUBMITTED_COUNT}, Skipped=${SKIPPED_COUNT}" >&2
  fi
done

# 3 cases: alpha=0.01, 0.02, 0.05 with gamma=0.0
for sample in "${SAMPLES[@]}"; do
  if submit_one_sample "DT_CVaR_a=0.01_g=0.0" "${CVAR_BASE} --alpha 0.01 --gamma_cvar 0.0" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.02_g=0.0" "${CVAR_BASE} --alpha 0.02 --gamma_cvar 0.0" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
  if submit_one_sample "DT_CVaR_a=0.05_g=0.0" "${CVAR_BASE} --alpha 0.05 --gamma_cvar 0.0" ${sample}; then ((SUBMITTED_COUNT++)) || true; else ((SKIPPED_COUNT++)) || true; fi
done

echo "=========================================="
echo "Submission complete!"
echo "  Submitted: ${SUBMITTED_COUNT} jobs"
echo "  Skipped (already submitted/completed): ${SKIPPED_COUNT} jobs"
echo "  Total: $((SUBMITTED_COUNT + SKIPPED_COUNT)) jobs processed"
echo "=========================================="
