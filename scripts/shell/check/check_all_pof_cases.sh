#!/usr/bin/env bash
# Check status of all POF cases: submitted, completed, or missing

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

echo "=== Checking all PoF cases ==="
echo ""

# Function to check if a task is submitted or completed
check_task() {
  local TAG="$1"
  local SAMPLE="$2"
  local jobname="${TAG}_s${SAMPLE}"
  
  # Extract eps from TAG
  EPS=$(echo "${TAG}" | grep -oE "eps=[0-9.]+" 2>/dev/null | cut -d= -f2 2>/dev/null || echo "")
  if [ -z "${EPS}" ]; then
    return 1
  fi
  
  # Build case directory name
  CASE_DIR="POF__HARD__eps=${EPS}__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
  
  # Check final.jld2
  FINAL_FILE="${ROOT_DIR}/data/DT_control/exp_name=step1/${CASE_DIR}/sample=${SAMPLE}/final.jld2"
  if [ -f "${FINAL_FILE}" ]; then
    echo "COMPLETED"
    return 0
  fi
  
  # Check queue
  if squeue -u $USER 2>/dev/null | grep -q "${jobname}" 2>/dev/null; then
    echo "SUBMITTED"
    return 0
  fi
  
  # Check sacct (any state in last 7 days)
  local startdate
  if date -d "7 days ago" +%Y-%m-%d >/dev/null 2>&1; then
    startdate=$(date -d "7 days ago" +%Y-%m-%d)
  elif date -v-7d +%Y-%m-%d >/dev/null 2>&1; then
    startdate=$(date -v-7d +%Y-%m-%d)
  else
    startdate=$(date +%Y-%m-%d)
  fi
  
  if sacct -u $USER --format=JobName,State --starttime="${startdate}" 2>/dev/null | \
     grep -q "${jobname}" 2>/dev/null; then
    echo "SUBMITTED"
    return 0
  fi
  
  echo "MISSING"
  return 1
}

# Counters
TOTAL=0
COMPLETED=0
SUBMITTED=0
MISSING=0
MISSING_LIST=()

# Group 1: eps=0.0, 0.001, 0.01, 0.02, 0.05 × samples 65-128
echo "Checking group 1: eps=0.0,0.001,0.01,0.02,0.05 × samples 65–128..."
for sample in $(seq 65 128); do
  for eps in 0.0 0.001 0.01 0.02 0.05; do
    TAG="DT_POF_eps=${eps}"
    STATUS=$(check_task "${TAG}" "${sample}")
    ((TOTAL++))
    case "$STATUS" in
      COMPLETED) ((COMPLETED++)) ;;
      SUBMITTED) ((SUBMITTED++)) ;;
      MISSING) 
        ((MISSING++))
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
    ((TOTAL++))
    case "$STATUS" in
      COMPLETED) ((COMPLETED++)) ;;
      SUBMITTED) ((SUBMITTED++)) ;;
      MISSING) 
        ((MISSING++))
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
  ((TOTAL++))
  case "$STATUS" in
    COMPLETED) ((COMPLETED++)) ;;
    SUBMITTED) ((SUBMITTED++)) ;;
    MISSING) 
      ((MISSING++))
      MISSING_LIST+=("${TAG} sample=${sample}")
      ;;
  esac
done

echo ""
echo "=========================================="
echo "Counts:"
echo "  Total: $TOTAL jobs"
echo "  Completed: $COMPLETED"
echo "  Submitted: $SUBMITTED"
echo "  Missing: $MISSING"
echo "=========================================="

if [ $MISSING -gt 0 ]; then
  echo ""
  echo "Missing jobs (first 20):"
  printf '%s\n' "${MISSING_LIST[@]}" | head -20
  if [ $MISSING -gt 20 ]; then
    echo "... and $((MISSING - 20)) more"
  fi
  exit 1
else
  echo ""
  echo "✓ All jobs have been submitted or completed"
  exit 0
fi

