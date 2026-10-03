#!/usr/bin/env bash
# Cancel duplicate POF jobs:
# 1. Jobs that have already completed (have final.jld2)
# 2. Jobs with duplicate jobnames in queue

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

echo "=== Review and cancel duplicate PoF jobs ==="
echo ""

# Find completed jobs that are still running
echo "1. Checking jobs with completed results that are still running..."
COMPLETED_JOBS=$(squeue -u $USER -o "%.18i %.50j" 2>/dev/null | grep "DT_POF" | while read line; do
  JOBID=$(echo "$line" | awk '{print $1}')
  JOBNAME=$(echo "$line" | awk '{print $2}')
  
  # Extract TAG and SAMPLE from job name
  TAG=$(echo "$JOBNAME" | sed 's/_s[0-9]*$//')
  SAMPLE=$(echo "$JOBNAME" | grep -oE "s[0-9]+" | sed 's/s//')
  
  # Extract eps from TAG
  EPS=$(echo "$TAG" | grep -oE "eps=[0-9.]+" | cut -d= -f2)
  
  # Build case directory name
  CASE_DIR="POF__HARD__eps=${EPS}__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
  
  # Check if final.jld2 exists
  FINAL_FILE="${ROOT_DIR}/data/DT_control/exp_name=step1/${CASE_DIR}/sample=${SAMPLE}/final.jld2"
  
  if [ -f "$FINAL_FILE" ]; then
    echo "${JOBID}|${JOBNAME}|completed"
  fi
done)

COMPLETED_COUNT=$(echo "$COMPLETED_JOBS" | grep -v "^$" | wc -l)

# Find duplicate jobnames in queue
echo "2. Checking duplicate job names in the queue..."
DUPLICATE_JOBS=$(squeue -u $USER -o "%.18i %.50j" 2>/dev/null | grep "DT_POF" | \
  awk '{print $2}' | sort | uniq -d | while read jobname; do
  # Get all job IDs with this name, keep only the first one
  squeue -u $USER -o "%.18i %.50j" 2>/dev/null | grep "DT_POF" | \
    awk -v name="$jobname" '$2 == name {print $1 "|" $2 "|duplicate"}' | tail -n +2
done)

DUPLICATE_COUNT=$(echo "$DUPLICATE_JOBS" | grep -v "^$" | wc -l)

TOTAL_COUNT=$((COMPLETED_COUNT + DUPLICATE_COUNT))

if [ "$TOTAL_COUNT" -eq 0 ]; then
  echo "✓ No cancellation candidates found"
  exit 0
fi

echo ""
echo "Cancellation candidates:"
echo "  - Completed results, still running: $COMPLETED_COUNT"
echo "  - Queue duplicates: $DUPLICATE_COUNT"
echo "  - Total: $TOTAL_COUNT"
echo ""

if [ "$COMPLETED_COUNT" -gt 0 ]; then
  echo "Jobs with completed results that are still running:"
  echo "$COMPLETED_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    echo "  - $JOBID: $JOBNAME ($REASON)"
  done
  echo ""
fi

if [ "$DUPLICATE_COUNT" -gt 0 ]; then
  echo "Duplicate queued jobs (keep the first; cancel the others):"
  echo "$DUPLICATE_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    echo "  - $JOBID: $JOBNAME ($REASON)"
  done
  echo ""
fi

# Ask for confirmation
read -p "Cancel these jobs? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Operation canceled"
  exit 0
fi

# Cancel jobs
echo ""
echo "Canceling jobs..."
CANCELED=0

# Cancel completed jobs
if [ "$COMPLETED_COUNT" -gt 0 ]; then
  echo "$COMPLETED_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    if [ -n "$JOBID" ] && [ -n "$JOBNAME" ]; then
      if scancel "$JOBID" 2>/dev/null; then
        echo "  ✓ Canceled: $JOBID ($JOBNAME) - $REASON"
        CANCELED=$((CANCELED + 1))
      else
        echo "  ✗ Cancellation failed: $JOBID ($JOBNAME)"
      fi
    fi
  done
fi

# Cancel duplicate jobs
if [ "$DUPLICATE_COUNT" -gt 0 ]; then
  echo "$DUPLICATE_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    if [ -n "$JOBID" ] && [ -n "$JOBNAME" ]; then
      if scancel "$JOBID" 2>/dev/null; then
        echo "  ✓ Canceled: $JOBID ($JOBNAME) - $REASON"
        CANCELED=$((CANCELED + 1))
      else
        echo "  ✗ Cancellation failed: $JOBID ($JOBNAME)"
      fi
    fi
  done
fi

echo ""
echo "Cancellation pass complete"

