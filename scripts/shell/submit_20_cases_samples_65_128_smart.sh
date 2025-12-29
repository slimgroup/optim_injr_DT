#!/usr/bin/env bash
# Smart submission script for 20 CVaR cases, samples 65-128
# Features:
#   - Skips already submitted/completed jobs (checks queue, final.jld2, and sacct)
#   - Monitors queue size and waits if queue is full
#   - Handles QOS submission limits gracefully
#   - Can be resumed after QOS limit is reached
#   - 20 CVaR cases × 64 samples (65-128) = 1280 jobs total

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"  # Project root for logs
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: Cannot find ${SBATCH_FILE}"
  exit 1
fi

# Configuration
MAX_QUEUE_SIZE=800      # Maximum queue size before waiting
QUEUE_CHECK_INTERVAL=30  # Check queue every 30 seconds when full
SUBMIT_BATCH_SIZE=50    # Submit in batches of 50
BATCH_DELAY=2           # Delay between batches (seconds)

# CVaR base arguments
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

# Convert TAG to output directory name
# Input:  DT_CVaR_a=0.0_g=0.0
# Output: CVaR__HARD__alpha=0.0__gamma=0.0__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0
tag_to_dir() {
  local TAG="$1"
  local alpha=$(echo "${TAG}" | grep -oE "a=[0-9.]+" 2>/dev/null | cut -d= -f2 2>/dev/null || echo "")
  local gamma=$(echo "${TAG}" | grep -oE "g=[0-9.]+" 2>/dev/null | cut -d= -f2 2>/dev/null || echo "")
  
  if [ -z "${alpha}" ] || [ -z "${gamma}" ]; then
    return 1
  fi
  echo "CVaR__HARD__alpha=${alpha}__gamma=${gamma}__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0"
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
  
  # Method 3: Check sacct for completed jobs (last 7 days)
  local startdate
  if date -d "7 days ago" +%Y-%m-%d >/dev/null 2>&1; then
    startdate=$(date -d "7 days ago" +%Y-%m-%d)
  elif date -v-7d +%Y-%m-%d >/dev/null 2>&1; then
    startdate=$(date -v-7d +%Y-%m-%d)
  else
    startdate=$(date +%Y-%m-%d)
  fi
  
  if sacct -u $USER --format=JobName,State --starttime="${startdate}" 2>/dev/null | \
     grep -q "${jobname}.*COMPLETED" 2>/dev/null; then
    return 0
  fi
  
  return 1
}

# Get current queue size for DT_CVaR jobs
get_queue_size() {
  squeue -u $USER 2>/dev/null | grep "DT_CVaR" | wc -l | tr -d ' '
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
  SBATCH_OUTPUT=$(sbatch --parsable --array="${SAMPLE}-${SAMPLE}" --chdir="${SCRIPT_DIR}/.." \
    --job-name="${TAG}_s${SAMPLE}" \
    --export=ALL,CASE_TAG="${TAG}",RISK_ARGS="${ARGS}" \
    "${SBATCH_FILE}" 2>&1)
  SBATCH_EXIT=$?
  
  # Check if submission was successful (--parsable returns job ID on success)
  if [ ${SBATCH_EXIT} -eq 0 ] && [ -n "${SBATCH_OUTPUT}" ] && [[ "${SBATCH_OUTPUT}" =~ ^[0-9]+$ ]]; then
    sleep 0.02
    return 0
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
echo "Smart Submission: 20 CVaR cases for samples 65-128"
echo "Total target: 1280 jobs (20 cases × 64 samples)"
echo "Will continuously submit until all are queued/completed"
echo "=========================================="

# Generate all tasks
declare -a TASKS
SAMPLES=($(seq 65 128))
TASK_IDX=0

# Build task list: 20 CVaR cases
for sample in "${SAMPLES[@]}"; do
  # 8 cases: alpha=0.0 or 0.001, with various gamma values
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.0_g=0.0|${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.0|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.0_g=0.01|${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.01|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.0_g=0.02|${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.02|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.0_g=0.05|${CVAR_BASE} --alpha 0.0 --gamma_cvar 0.05|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.001_g=0.0|${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.0|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.001_g=0.01|${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.01|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.001_g=0.02|${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.02|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.001_g=0.05|${CVAR_BASE} --alpha 0.001 --gamma_cvar 0.05|${sample}"
done

for sample in "${SAMPLES[@]}"; do
  # 3 cases: alpha=0.01, 0.02, 0.05 with gamma=0.0
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.01_g=0.0|${CVAR_BASE} --alpha 0.01 --gamma_cvar 0.0|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.02_g=0.0|${CVAR_BASE} --alpha 0.02 --gamma_cvar 0.0|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.05_g=0.0|${CVAR_BASE} --alpha 0.05 --gamma_cvar 0.0|${sample}"
done

for sample in "${SAMPLES[@]}"; do
  # 9 cases: alpha=0.01, 0.02, 0.05 with gamma=0.01, 0.02, 0.05
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.01_g=0.01|${CVAR_BASE} --alpha 0.01 --gamma_cvar 0.01|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.01_g=0.02|${CVAR_BASE} --alpha 0.01 --gamma_cvar 0.02|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.01_g=0.05|${CVAR_BASE} --alpha 0.01 --gamma_cvar 0.05|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.02_g=0.01|${CVAR_BASE} --alpha 0.02 --gamma_cvar 0.01|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.02_g=0.02|${CVAR_BASE} --alpha 0.02 --gamma_cvar 0.02|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.02_g=0.05|${CVAR_BASE} --alpha 0.02 --gamma_cvar 0.05|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.05_g=0.01|${CVAR_BASE} --alpha 0.05 --gamma_cvar 0.01|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.05_g=0.02|${CVAR_BASE} --alpha 0.05 --gamma_cvar 0.02|${sample}"
  TASKS[$((TASK_IDX++))]="DT_CVaR_a=0.05_g=0.05|${CVAR_BASE} --alpha 0.05 --gamma_cvar 0.05|${sample}"
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
  QUEUE_SIZE=$(get_queue_size)
  
  # If queue is too large, wait
  if [ ${QUEUE_SIZE} -ge ${MAX_QUEUE_SIZE} ]; then
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
    IFS='|' read -r TAG ARGS SAMPLE <<< "${TASKS[$i]}" || continue
    if [ -z "${TAG}" ] || [ -z "${SAMPLE}" ]; then
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
  echo "All 1280 jobs are now submitted. They will run automatically as resources become available."
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

