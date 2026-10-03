#!/usr/bin/env bash
# Smart submission script for POF cases
# Features:
#   - Skips already submitted/completed jobs (checks queue, final.jld2, and sacct)
#   - Monitors queue size and waits if queue is full
#   - Handles QOS submission limits gracefully
#   - Can be resumed after QOS limit is reached
#   - Total: 832 jobs
#     - 5 cases (eps=0.0,0.001,0.01,0.02,0.05) × 64 samples (65-128) = 320 jobs
#     - 4 cases (eps=0.002,0.003,0.005,0.03) × 96 samples (33-128) = 384 jobs
#     - 1 case (eps=0.1) × 128 samples (1-128) = 128 jobs

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"  # Project root for logs
SBATCH_FILE="${SCRIPT_DIR}/../run/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

# Configuration
MAX_QUEUE_SIZE=800      # Maximum queue size before waiting
QUEUE_CHECK_INTERVAL=30  # Check queue every 30 seconds when full
SUBMIT_BATCH_SIZE=50    # Submit in batches of 50
BATCH_DELAY=2           # Delay between batches (seconds)

# POF base arguments
POF_BASE="--use_pof --pof_as_constraint \
          --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
          --risk_mode relative --weight_mode voltime"

# Convert TAG to output directory name
# Input:  DT_POF_eps=0.01
# Output: POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0
tag_to_dir() {
  local TAG="$1"
  local eps=$(echo "${TAG}" | grep -oE "eps=[0-9.]+" 2>/dev/null | cut -d= -f2 2>/dev/null || echo "")
  
  if [ -z "${eps}" ]; then
    return 1
  fi
  echo "POF__HARD__eps=${eps}__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
}

# Check if a job is already submitted/completed
# Returns: 0 if submitted/completed, 1 if not
is_submitted() {
  local TAG="$1"
  local SAMPLE="$2"
  local jobname="${TAG}_s${SAMPLE}"
  
  # Method 1: Check queue (fastest)
  if squeue -u $USER 2>/dev/null | grep -q "${jobname}" 2>/dev/null; then
    return 0
  fi
  
  # Method 2: Check final.jld2 file (most reliable)
  local case_dir=$(tag_to_dir "${TAG}" 2>/dev/null || echo "")
  if [ -n "${case_dir}" ]; then
    local final_file="${ROOT_DIR}/data/DT_control/exp_name=step1/${case_dir}/sample=${SAMPLE}/final.jld2"
    if [ -f "${final_file}" ] 2>/dev/null; then
      return 0
    fi
  fi
  
  # Method 3: Check sacct for any job state (not just COMPLETED)
  # This catches jobs that are RUNNING, PENDING, COMPLETED, FAILED, etc.
  # Use 30 days to catch older jobs that may have been cancelled/failed
  local startdate
  if date -d "30 days ago" +%Y-%m-%d >/dev/null 2>&1; then
    startdate=$(date -d "30 days ago" +%Y-%m-%d)
  elif date -v-30d +%Y-%m-%d >/dev/null 2>&1; then
    startdate=$(date -v-30d +%Y-%m-%d)
  else
    startdate=$(date +%Y-%m-%d)
  fi
  
  # Check for any job with this name in sacct (any state)
  # Note: sacct output format may truncate JobName, so we need to specify width
  # Also, sacct may show jobname with array index like "DT_POF_eps=0.003_s77[77]"
  # We check if the base jobname (without array index) matches
  if sacct -u $USER --format=JobID,JobName%50,State --starttime="${startdate}" 2>/dev/null | \
     grep -q "${jobname}" 2>/dev/null; then
    return 0
  fi
  
  return 1
}

# Get current queue size for DT_POF jobs
get_queue_size() {
  squeue -u $USER 2>/dev/null | grep "DT_POF" | wc -l | tr -d ' \n'
}

# Submit one sample job
# Returns: 0=success, 1=skip/failed, 2=QOS limit reached
submit_one_sample() {
  local TAG="$1" ARGS="$2" SAMPLE="$3"

  if is_submitted "${TAG}" "${SAMPLE}" 2>/dev/null; then
    echo "[SKIP] ${TAG}  sample=${SAMPLE} (already submitted/completed)" >&2
    return 1
  fi

  echo "[SUBMIT] ${TAG}  sample=${SAMPLE}" >&2
  local jobname="${TAG}_s${SAMPLE}"
  SBATCH_OUTPUT=$(sbatch --parsable --array="${SAMPLE}-${SAMPLE}" --chdir="${ROOT_DIR}" \
    --job-name="${jobname}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}" 2>&1)
  SBATCH_EXIT=$?
  
  # Check if submission was successful (--parsable returns job ID on success)
  if [ ${SBATCH_EXIT} -eq 0 ] && [ -n "${SBATCH_OUTPUT}" ] && [[ "${SBATCH_OUTPUT}" =~ ^[0-9]+$ ]]; then
    # Verify job is actually in queue (sbatch may return success but job could be rejected)
    sleep 0.1  # Brief delay to allow job to appear in queue
    if squeue -u $USER 2>/dev/null | grep -q "${jobname}" 2>/dev/null; then
      sleep 0.02
      return 0
    else
      # Job submitted but not in queue - might be rejected or already completed
      # Check sacct to see if it was submitted before (use 30 days to catch older jobs)
      local startdate
      if date -d "30 days ago" +%Y-%m-%d >/dev/null 2>&1; then
        startdate=$(date -d "30 days ago" +%Y-%m-%d)
      elif date -v-30d +%Y-%m-%d >/dev/null 2>&1; then
        startdate=$(date -v-30d +%Y-%m-%d)
      else
        startdate=$(date +%Y-%m-%d)
      fi
      if sacct -u $USER --format=JobID,JobName%50,State --starttime="${startdate}" 2>/dev/null | \
         grep -q "${jobname}" 2>/dev/null; then
        # Job was submitted before, skip
        echo "[SKIP] ${TAG}  sample=${SAMPLE} (already in sacct)" >&2
        return 1
      else
        # Job submission may have failed silently
        echo "[WARN] ${TAG}  sample=${SAMPLE} submitted (job ID: ${SBATCH_OUTPUT}) but not in queue" >&2
        return 0  # Still count as submitted attempt
      fi
    fi
  fi
  
  # Check for QOS limit error
  if echo "${SBATCH_OUTPUT}" | grep -q "QOSMaxSubmitJobPerUserLimit"; then
    echo "[QOS_LIMIT] Reached QOSMaxSubmitJobPerUserLimit. Stopping submission." >&2
    echo "[QOS_LIMIT] Error: ${SBATCH_OUTPUT}" >&2
    return 2
  fi
  
  # Log error only if job is not already submitted
  if ! is_submitted "${TAG}" "${SAMPLE}" 2>/dev/null; then
    echo "[ERROR] Failed to submit ${TAG} sample=${SAMPLE}: ${SBATCH_OUTPUT}" >&2
  fi
  return 1
}

echo "=========================================="
echo "Smart Submission: POF cases"
echo "Total target: 832 jobs"
echo "  - 5 cases (eps=0.0,0.001,0.01,0.02,0.05) × 64 samples (65-128) = 320 jobs"
echo "  - 4 cases (eps=0.002,0.003,0.005,0.03) × 96 samples (33-128) = 384 jobs"
echo "  - 1 case (eps=0.1) × 128 samples (1-128) = 128 jobs"
echo "Will continuously submit until all are queued/completed"
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
echo "Starting smart submission loop..."
echo ""

# Main loop: Continue until all tasks are submitted
while [ ${CURRENT_INDEX} -lt ${TOTAL_TASKS} ]; do
  # Check current queue size
  QUEUE_SIZE=$(get_queue_size 2>/dev/null || echo "0")
  # Ensure QUEUE_SIZE is a valid number
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
  
  # Progress report
  echo "[PROGRESS] Submitted: ${SUBMITTED_COUNT}, Skipped: ${SKIPPED_COUNT}, Remaining: $((TOTAL_TASKS - CURRENT_INDEX))" >&2
  echo "" >&2
  
  # Delay between batches
  sleep ${BATCH_DELAY}
done

echo "=========================================="
if [ ${CURRENT_INDEX} -ge ${TOTAL_TASKS} ]; then
  echo "Smart submission complete!"
  echo "  Submitted: ${SUBMITTED_COUNT} jobs"
  echo "  Skipped (already submitted/completed): ${SKIPPED_COUNT} jobs"
  echo "  Total processed: ${TOTAL_TASKS} tasks"
  echo ""
  echo "All 832 jobs are now submitted. They will run automatically as resources become available."
else
  echo "Submission paused due to QOS limit"
  echo "  Submitted: ${SUBMITTED_COUNT} jobs"
  echo "  Skipped (already submitted/completed): ${SKIPPED_COUNT} jobs"
  echo "  Processed: ${CURRENT_INDEX}/${TOTAL_TASKS} tasks"
  echo "  Remaining: $((TOTAL_TASKS - CURRENT_INDEX)) tasks"
  echo ""
  echo "To resume submission, run this script again:"
  echo "  bash ${0}"
  echo ""
  echo "The script will automatically skip already submitted/completed jobs."
fi
echo "=========================================="

