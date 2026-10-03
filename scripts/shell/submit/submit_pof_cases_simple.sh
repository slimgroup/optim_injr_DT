#!/usr/bin/env bash
# Simple POF submission script: Only submit tasks without final.jld2
# No sacct checking - only check final.jld2 and queue

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

# POF base arguments
POF_BASE="--use_pof --pof_as_constraint --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime"

# Queue management
MAX_QUEUE_SIZE=800
QUEUE_CHECK_INTERVAL=30
SUBMIT_BATCH_SIZE=50

# Convert job tag to directory name
tag_to_dir() {
  local TAG="$1"
  local eps=$(echo "${TAG}" | grep -oE "eps=[0-9.]+" 2>/dev/null | cut -d= -f2 2>/dev/null || echo "")
  if [ -z "${eps}" ]; then
    return 1
  fi
  echo "POF__HARD__eps=${eps}__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
}

# Associative array to track submitted jobs in this script run
# This prevents duplicate submissions within the same script execution
declare -A SUBMITTED_IN_THIS_RUN

# Check if a task is already completed or in queue
# Returns: 0 if completed/in queue, 1 if not
is_completed_or_queued() {
  local TAG="$1"
  local SAMPLE="$2"
  local jobname="${TAG}_s${SAMPLE}"
  
  # Method 0: Check if already submitted in this script run (NEW: prevents duplicate submissions)
  if [[ -n "${SUBMITTED_IN_THIS_RUN[${jobname}]:-}" ]]; then
    return 0
  fi
  
  # Method 1: Check final.jld2 file (most reliable - if file exists, task is done)
  local case_dir=$(tag_to_dir "${TAG}" 2>/dev/null || echo "")
  if [ -n "${case_dir}" ]; then
    local final_file="${ROOT_DIR}/data/DT_control/exp_name=step1/${case_dir}/sample=${SAMPLE}/final.jld2"
    if [ -f "${final_file}" ] 2>/dev/null; then
      return 0
    fi
  fi
  
  # Method 2: Check queue (if in queue, don't submit again)
  # Use -w to ensure whole word match, avoid partial matches
  if squeue -u $USER 2>/dev/null | grep -wq "${jobname}" 2>/dev/null; then
    return 0
  fi
  
  return 1
}

# Get current queue size for DT_POF jobs
get_queue_size() {
  squeue -u $USER 2>/dev/null | grep "DT_POF" | wc -l | tr -d ' \n'
}

# Submit one sample job
# Returns: 0=success, 1=skip, 2=QOS limit reached
submit_one_sample() {
  local TAG="$1" ARGS="$2" SAMPLE="$3"
  local jobname="${TAG}_s${SAMPLE}"

  # Check if already completed or in queue
  if is_completed_or_queued "${TAG}" "${SAMPLE}" 2>/dev/null; then
    echo "[SKIP] ${TAG}  sample=${SAMPLE} (already completed or in queue)" >&2
    return 1
  fi

  echo "[SUBMIT] ${TAG}  sample=${SAMPLE}" >&2
  SBATCH_OUTPUT=$(sbatch --parsable --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
    --job-name="${jobname}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}" 2>&1)
  SBATCH_EXIT=$?
  
  # Check if submission was successful
  if [ ${SBATCH_EXIT} -eq 0 ] && [ -n "${SBATCH_OUTPUT}" ] && [[ "${SBATCH_OUTPUT}" =~ ^[0-9]+$ ]]; then
    # Mark as submitted in this script run (NEW: prevents duplicate submissions)
    SUBMITTED_IN_THIS_RUN["${jobname}"]=1
    
    # Wait a bit and verify job is in queue (increased wait time for reliability)
    sleep 1.0
    # Retry check up to 2 times if not found
    for retry in {1..2}; do
      if squeue -u $USER 2>/dev/null | grep -wq "${jobname}" 2>/dev/null; then
        return 0
      fi
      if [ $retry -lt 2 ]; then
        sleep 0.5
      fi
    done
    
    # Job submitted but not in queue - might be rejected or still processing
    echo "[WARN] ${TAG}  sample=${SAMPLE} submitted (job ID: ${SBATCH_OUTPUT}) but not in queue after retries" >&2
    # Still return success - job ID was returned, so submission was accepted
    # Job is already marked in SUBMITTED_IN_THIS_RUN, so won't be resubmitted
    return 0
  fi
  
  # Check for QOS limit error
  if echo "${SBATCH_OUTPUT}" | grep -q "QOSMaxSubmitJobPerUserLimit"; then
    echo "[QOS_LIMIT] Reached QOSMaxSubmitJobPerUserLimit. Stopping submission." >&2
    echo "[QOS_LIMIT] Error: ${SBATCH_OUTPUT}" >&2
    return 2
  fi
  
  # Other error
  echo "[ERROR] Failed to submit ${TAG} sample=${SAMPLE}: ${SBATCH_OUTPUT}" >&2
  return 1
}

echo "=========================================="
echo "Simple POF Submission: Only submit tasks without final.jld2"
echo "Total target: 832 jobs"
echo "  - 5 cases (eps=0.0,0.001,0.01,0.02,0.05) × 64 samples (65-128) = 320 jobs"
echo "  - 4 cases (eps=0.002,0.003,0.005,0.03) × 96 samples (33-128) = 384 jobs"
echo "  - 1 case (eps=0.1) × 128 samples (1-128) = 128 jobs"
echo "Will only submit tasks that don't have final.jld2"
echo "=========================================="

# Generate all tasks
declare -a TASKS
TASK_IDX=0

# Group 1: eps=0.0, 0.001, 0.01, 0.02, 0.05 × samples 65-128
SAMPLES_65_128=($(seq 65 128))
for sample in "${SAMPLES_65_128[@]}"; do
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.0|${POF_BASE} --eps_pof 0.0|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.001|${POF_BASE} --eps_pof 0.001|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.01|${POF_BASE} --eps_pof 0.01|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.02|${POF_BASE} --eps_pof 0.02|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.05|${POF_BASE} --eps_pof 0.05|${sample}"
done

# Group 2: eps=0.002, 0.003, 0.005, 0.03 × samples 33-128
SAMPLES_33_128=($(seq 33 128))
for sample in "${SAMPLES_33_128[@]}"; do
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.002|${POF_BASE} --eps_pof 0.002|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.003|${POF_BASE} --eps_pof 0.003|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.005|${POF_BASE} --eps_pof 0.005|${sample}"
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.03|${POF_BASE} --eps_pof 0.03|${sample}"
done

# Group 3: eps=0.1 × samples 1-128
SAMPLES_1_128=($(seq 1 128))
for sample in "${SAMPLES_1_128[@]}"; do
  TASKS[$((TASK_IDX++))]="DT_POF_eps=0.1|${POF_BASE} --eps_pof 0.1|${sample}"
done

TOTAL_TASKS=${#TASKS[@]}
CURRENT_INDEX=0
SUBMITTED_COUNT=0
SKIPPED_COUNT=0

echo "Total tasks: ${TOTAL_TASKS}"
echo "Starting submission loop..."
echo ""

# Main loop: Continue until all tasks are submitted
while [ ${CURRENT_INDEX} -lt ${TOTAL_TASKS} ]; do
  # Check current queue size
  QUEUE_SIZE=$(get_queue_size 2>/dev/null || echo "0")
  QUEUE_SIZE=${QUEUE_SIZE:-0}
  
  # If queue is too large, wait
  if [ "${QUEUE_SIZE}" -ge "${MAX_QUEUE_SIZE}" ] 2>/dev/null; then
    echo "[WAIT] Queue size: ${QUEUE_SIZE}/${MAX_QUEUE_SIZE}, waiting ${QUEUE_CHECK_INTERVAL}s..." >&2
    sleep ${QUEUE_CHECK_INTERVAL}
    continue
  fi
  
  # Submit a batch
  BATCH_START=${CURRENT_INDEX}
  BATCH_END=$((CURRENT_INDEX + SUBMIT_BATCH_SIZE))
  if [ ${BATCH_END} -gt ${TOTAL_TASKS} ]; then
    BATCH_END=${TOTAL_TASKS}
  fi
  
  echo "[BATCH] Processing tasks ${BATCH_START}-$((BATCH_END - 1)) (Queue: ${QUEUE_SIZE}/${MAX_QUEUE_SIZE})" >&2
  
  QOS_LIMIT_REACHED=0
  for ((i=${BATCH_START}; i<${BATCH_END}; i++)); do
    IFS='|' read -r TAG ARGS SAMPLE <<< "${TASKS[$i]}" || { echo "[ERROR] Failed to parse task ${i}: ${TASKS[$i]}" >&2; continue; }
    if [ -z "${TAG}" ] || [ -z "${SAMPLE}" ]; then
      echo "[WARN] Skipping empty TAG or SAMPLE for task ${i}" >&2
      continue
    fi
    # Temporarily disable exit-on-error to prevent script exit if submission fails
    set +e
    submit_one_sample "${TAG}" "${ARGS}" "${SAMPLE}"
    SUBMIT_RESULT=$?
    set -e
    
    if [ ${SUBMIT_RESULT} -eq 0 ]; then
      ((SUBMITTED_COUNT++)) || true
    elif [ ${SUBMIT_RESULT} -eq 2 ]; then
      # QOS limit reached - stop immediately
      QOS_LIMIT_REACHED=1
      CURRENT_INDEX=$i  # Save current position
      break
    else
      ((SKIPPED_COUNT++)) || true
    fi
  done
  
  # If QOS limit reached, exit the loop
  if [ ${QOS_LIMIT_REACHED} -eq 1 ]; then
    echo "" >&2
    echo "[STOP] QOS submission limit reached. Stopping submission." >&2
    echo "[STOP] Progress saved. Resume by running this script again." >&2
    break
  fi
  
  CURRENT_INDEX=${BATCH_END}
  
  # Progress update
  REMAINING=$((TOTAL_TASKS - CURRENT_INDEX))
  echo "[PROGRESS] Submitted: ${SUBMITTED_COUNT}, Skipped: ${SKIPPED_COUNT}, Remaining: ${REMAINING}" >&2
  echo "" >&2
  
  # Small delay between batches
  sleep 1
done

echo "" >&2
echo "==========================================" >&2
echo "Submission complete!" >&2
echo "  Submitted: ${SUBMITTED_COUNT}" >&2
echo "  Skipped: ${SKIPPED_COUNT}" >&2
echo "  Total processed: $((SUBMITTED_COUNT + SKIPPED_COUNT))/${TOTAL_TASKS}" >&2
echo "==========================================" >&2

