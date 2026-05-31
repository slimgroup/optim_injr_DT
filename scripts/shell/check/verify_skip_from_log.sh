#!/usr/bin/env bash
# Verify skipped jobs from submit_smart.log by checking if they actually exist

echo "=========================================="
echo "Verifying Skip Correctness from Log"
echo "=========================================="
echo ""

# Based on PROGRESS reports, first 50 tasks (sample 2-9) were all skipped
# Let's verify some of these

SAMPLES=(2 3 4 5 6 7 8 9)
CASES=(
  "DT_CVaR_a=0.0_g=0.0"
  "DT_CVaR_a=0.0_g=0.01"
  "DT_CVaR_a=0.0_g=0.02"
  "DT_CVaR_a=0.0_g=0.05"
  "DT_CVaR_a=0.001_g=0.0"
  "DT_CVaR_a=0.001_g=0.01"
  "DT_CVaR_a=0.001_g=0.02"
  "DT_CVaR_a=0.001_g=0.05"
)

echo "Checking first batch of skipped jobs (sample 2-9)..."
echo ""

CORRECT=0
INCORRECT=0
CHECKED=0

for sample in "${SAMPLES[@]}"; do
  for case_tag in "${CASES[@]}"; do
    jobname="${case_tag}_s${sample}"
    
    # Check queue
    in_queue=$(squeue -u $USER 2>/dev/null | grep -c "${jobname}" 2>/dev/null || echo 0)
    in_queue=${in_queue:-0}
    
    # Check logs (logs are in project root logs/ directory)
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    has_logs=$(ls "${ROOT_DIR}/logs"/*${jobname}* 2>/dev/null | wc -l | tr -d ' ' 2>/dev/null || echo 0)
    has_logs=${has_logs:-0}
    
    # Check sacct for completed
    if sacct -u $USER --format=JobName,State --starttime=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d) 2>/dev/null | \
       grep -q "${jobname}.*COMPLETED"; then
      is_completed=1
    else
      is_completed=0
    fi
    
    if [[ ${in_queue} -gt 0 ]] || [[ ${has_logs} -gt 0 ]] || [[ ${is_completed} -eq 1 ]]; then
      ((CORRECT++)) || true
      echo "✓ ${jobname}: queue=${in_queue}, logs=${has_logs}, completed=${is_completed}"
    else
      ((INCORRECT++)) || true
      echo "✗ ${jobname}: NOT FOUND (should have been skipped incorrectly)"
    fi
    
    ((CHECKED++)) || true
    
    # Only check first few to avoid too much output
    if [[ ${CHECKED} -ge 20 ]]; then
      break 2
    fi
  done
done

echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Checked: ${CHECKED} jobs"
echo "Correct skip (found in queue/logs): ${CORRECT}"
echo "Incorrect skip (not found): ${INCORRECT}"
echo ""
if [[ ${INCORRECT} -eq 0 ]]; then
  echo "✓ All checked jobs were correctly skipped!"
else
  echo "⚠ Some jobs were skipped but not found - may need investigation"
fi

