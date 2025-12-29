#!/usr/bin/env bash
# Quick script to check submission progress for samples 65-128

echo "=========================================="
echo "CVaR Jobs (samples 65-128) Progress Check"
echo "=========================================="
echo ""

# Check if submission script is still running
if pgrep -f "submit_20_cases_samples_65_128_smart.sh" > /dev/null; then
    echo "✓ Submission script is running"
else
    echo "✗ Submission script is NOT running (may have completed)"
fi
echo ""

# Count jobs by state (for samples 65-128)
echo "=== Queue Status (samples 65-128) ==="
RUNNING=$(squeue -u $USER 2>/dev/null | grep "DT_CVaR.*_s[6-9][0-9]\|DT_CVaR.*_s1[0-2][0-8]" | grep " R " | wc -l | tr -d ' ')
PENDING=$(squeue -u $USER 2>/dev/null | grep "DT_CVaR.*_s[6-9][0-9]\|DT_CVaR.*_s1[0-2][0-8]" | grep "PD" | wc -l | tr -d ' ')
RUNNING=${RUNNING:-0}
PENDING=${PENDING:-0}
echo "Running: ${RUNNING}"
echo "Pending: ${PENDING}"
TOTAL_QUEUE=$((RUNNING + PENDING))
echo "Total in queue: ${TOTAL_QUEUE}"
echo ""

# Count all CVaR jobs (any sample)
ALL_CVAR=$(squeue -u $USER 2>/dev/null | grep "DT_CVaR" | wc -l | tr -d ' ')
echo "Total CVaR jobs in queue (all samples): ${ALL_CVAR}"
echo ""

# Check submission log progress
LOG_FILE="/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/submit_65_128.log"
if [ -f "${LOG_FILE}" ]; then
    echo "=== Submission Log Progress ==="
    LAST_PROGRESS=$(grep "\[PROGRESS\]" "${LOG_FILE}" | tail -1)
    if [ -n "${LAST_PROGRESS}" ]; then
        echo "${LAST_PROGRESS}"
    else
        echo "No progress report yet (still in first batch)"
    fi
    
    SUBMITTED=$(grep -c "\[SUBMIT\]" "${LOG_FILE}" 2>/dev/null || echo "0")
    SKIPPED=$(grep -c "\[SKIP\]" "${LOG_FILE}" 2>/dev/null || echo "0")
    echo "From log: Submitted=${SUBMITTED}, Skipped=${SKIPPED}"
    echo ""
    
    # Show last few lines
    echo "=== Last 5 lines from log ==="
    tail -5 "${LOG_FILE}"
    echo ""
fi

# Count completed jobs for samples 65-128 (last 7 days)
echo "=== Completed Jobs (samples 65-128, last 7 days) ==="
STARTDATE=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
COMPLETED=$(sacct -u $USER --format=JobName,State --starttime="${STARTDATE}" 2>/dev/null | \
  grep "DT_CVaR.*_s[6-9][0-9].*COMPLETED\|DT_CVaR.*_s1[0-2][0-8].*COMPLETED" | wc -l | tr -d ' ')
FAILED=$(sacct -u $USER --format=JobName,State --starttime="${STARTDATE}" 2>/dev/null | \
  grep "DT_CVaR.*_s[6-9][0-9].*FAILED\|DT_CVaR.*_s1[0-2][0-8].*FAILED" | wc -l | tr -d ' ')
echo "Completed: ${COMPLETED}"
echo "Failed: ${FAILED}"
echo ""

# Calculate expected vs actual
EXPECTED=1280  # 20 cases × 64 samples
TOTAL_SUBMITTED=$((SUBMITTED + SKIPPED))
REMAINING=$((EXPECTED - TOTAL_SUBMITTED))
echo "=== Summary ==="
echo "Expected: ${EXPECTED} jobs (20 cases × 64 samples)"
echo "Submitted/Skipped: ${TOTAL_SUBMITTED} jobs"
echo "Remaining to submit: ${REMAINING} jobs"
if [ ${TOTAL_SUBMITTED} -gt 0 ]; then
    PERCENT=$((TOTAL_SUBMITTED * 100 / EXPECTED))
    echo "Progress: ${PERCENT}%"
else
    echo "Progress: 0%"
fi
echo ""

# Show sample range in queue
echo "=== Sample Range in Queue ==="
MIN_SAMPLE=$(squeue -u $USER 2>/dev/null | grep "DT_CVaR.*_s" | grep -oE "_s[0-9]+" | sed 's/_s//' | sort -n | head -1)
MAX_SAMPLE=$(squeue -u $USER 2>/dev/null | grep "DT_CVaR.*_s" | grep -oE "_s[0-9]+" | sed 's/_s//' | sort -n | tail -1)
if [ -n "${MIN_SAMPLE}" ] && [ -n "${MAX_SAMPLE}" ]; then
    echo "Sample range: ${MIN_SAMPLE} - ${MAX_SAMPLE}"
else
    echo "No samples in queue"
fi
echo ""

