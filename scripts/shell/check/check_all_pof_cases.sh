#!/usr/bin/env bash
# Check status of all POF cases: submitted, completed, or missing

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

echo "=== Checking all PoF cases ==="
echo ""

# Query each Slurm service once, using full names and allocation records only.
# An allocation record means submitted at least once, not necessarily successful.
STARTDATE=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
QUEUE_OK=true
ACCOUNTING_OK=true
QUEUE=$(squeue -h -u "$USER" -o '%j' 2>/dev/null) || QUEUE_OK=false
ACCOUNTING=$(sacct -X -n -P -u "$USER" --format=JobName%200 --starttime="${STARTDATE}" 2>/dev/null) || ACCOUNTING_OK=false
declare -A SUBMITTED_JOBS=()
while IFS='|' read -r jobname rest; do
  if [[ -n "$jobname" ]]; then
    SUBMITTED_JOBS["$jobname"]=1
  fi
done <<< "${QUEUE}
${ACCOUNTING}"

check_task() {
  local tag="$1" sample="$2"
  local jobname="${tag}_s${sample}"
  local eps="${tag#DT_POF_eps=}"
  local case_dir="POF__HARD__eps=${eps}__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
  local final_file="${ROOT_DIR}/data/DT_control/exp_name=step1/${case_dir}/sample=${sample}/final.jld2"

  if [[ -f "$final_file" ]]; then
    echo "COMPLETED"
  elif [[ -n "${SUBMITTED_JOBS[$jobname]:-}" ]]; then
    echo "SUBMITTED"
  elif [[ "$QUEUE_OK" != true || "$ACCOUNTING_OK" != true ]]; then
    echo "UNKNOWN"
  else
    echo "MISSING"
  fi
}

# Counters
TOTAL=0
COMPLETED=0
SUBMITTED=0
MISSING=0
UNKNOWN=0
MISSING_LIST=()

# Group 1: eps=0.0, 0.001, 0.01, 0.02, 0.05 × samples 65-128
echo "Checking group 1: eps=0.0,0.001,0.01,0.02,0.05 × samples 65–128..."
for sample in $(seq 65 128); do
  for eps in 0.0 0.001 0.01 0.02 0.05; do
    TAG="DT_POF_eps=${eps}"
    STATUS=$(check_task "${TAG}" "${sample}")
    ((++TOTAL))
    case "$STATUS" in
      COMPLETED) ((++COMPLETED)) ;;
      SUBMITTED) ((++SUBMITTED)) ;;
      UNKNOWN) ((++UNKNOWN)) ;;
      MISSING) 
        ((++MISSING))
        MISSING_LIST+=("${TAG} sample=${sample}")
        ;;
    esac
  done
done

# Group 2: eps=0.002, 0.003, 0.005, 0.03 × samples 33-128
echo "Checking group 2: eps=0.002,0.003,0.005,0.03 × samples 33–128..."
for sample in $(seq 33 128); do
  for eps in 0.002 0.003 0.005 0.03; do
    TAG="DT_POF_eps=${eps}"
    STATUS=$(check_task "${TAG}" "${sample}")
    ((++TOTAL))
    case "$STATUS" in
      COMPLETED) ((++COMPLETED)) ;;
      SUBMITTED) ((++SUBMITTED)) ;;
      UNKNOWN) ((++UNKNOWN)) ;;
      MISSING) 
        ((++MISSING))
        MISSING_LIST+=("${TAG} sample=${sample}")
        ;;
    esac
  done
done

# Group 3: eps=0.1 × samples 1-128
echo "Checking group 3: eps=0.1 × samples 1–128..."
for sample in $(seq 1 128); do
  TAG="DT_POF_eps=0.1"
  STATUS=$(check_task "${TAG}" "${sample}")
  ((++TOTAL))
  case "$STATUS" in
    COMPLETED) ((++COMPLETED)) ;;
    SUBMITTED) ((++SUBMITTED)) ;;
    UNKNOWN) ((++UNKNOWN)) ;;
    MISSING) 
      ((++MISSING))
      MISSING_LIST+=("${TAG} sample=${sample}")
      ;;
  esac
done

echo ""
echo "=========================================="
echo "Counts:"
echo "  Total: $TOTAL jobs"
echo "  Completed: $COMPLETED"
echo "  Submitted: $SUBMITTED (queue or recent allocation record; success not implied)"
echo "  Missing: $MISSING"
echo "  Unknown: $UNKNOWN"
echo "=========================================="

if [ $MISSING -gt 0 ]; then
  echo ""
  echo "Missing jobs (first 20):"
  printf '%s\n' "${MISSING_LIST[@]:0:20}"
  if [ $MISSING -gt 20 ]; then
    echo "... and $((MISSING - 20)) more"
  fi
fi

if [ "$UNKNOWN" -gt 0 ]; then
  echo "Slurm status unavailable for some samples; re-check the failed query before deciding to resubmit."
  exit 2
elif [ "$MISSING" -gt 0 ]; then
  exit 1
else
  echo ""
  echo "✓ All jobs have been submitted or completed"
  exit 0
fi
