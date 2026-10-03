#!/usr/bin/env bash
# Read-only submission and allocation status for CVaR samples 65-128.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LOG_FILE="${SUBMISSION_LOG:-${ROOT_DIR}/logs/submit/submit_20_cases_65_128.log}"
if [[ -z "${SUBMISSION_LOG:-}" && ! -f "${LOG_FILE}" ]]; then
    LOG_FILE="${ROOT_DIR}/submit_65_128.log"
fi

echo "=== CVaR Jobs (samples 65-128) Progress Check ==="
if pgrep -f "submit_20_cases_samples_65_128_smart.sh" > /dev/null; then
    echo "Submission script is running"
else
    echo "Submission script is not running (may have completed)"
fi

# Explicit job-name output avoids squeue's default truncation. Reuse one snapshot.
# Extract an integer instead of a digit-pattern approximation to the sample range.
SAMPLE_AWK='
function sample(name, value) {
    if (!match(name, /_s[0-9]+($|_)/)) return -1
    value = substr(name, RSTART + 2, RLENGTH - 2)
    sub(/_$/, "", value)
    return value + 0
}'
echo
echo "=== Queue Status (samples 65-128) ==="
if QUEUE=$(squeue -h -u "$USER" -o '%j|%t' 2>/dev/null); then
    awk -F '|' "$SAMPLE_AWK"'
    /^DT_CVaR/ {
        all++
        s = sample($1)
        if (s >= 0) {
            if (!seen || s < low) low = s
            if (!seen || s > high) high = s
            seen = 1
        }
        if (s >= 65 && s <= 128) {
            total++
            if ($2 == "R") running++
            if ($2 == "PD") pending++
        }
    }
    END {
        printf "Running: %d\nPending: %d\nTotal in queue: %d\n", running, pending, total
        printf "Total CVaR jobs in queue (all samples): %d\n", all
        if (seen) printf "Sample range in queue (all CVaR): %d - %d\n", low, high
        else print "No CVaR samples in queue"
    }' <<< "$QUEUE"
else
    echo "Queue status unavailable: squeue query failed."
fi

echo
echo "=== Submission Log ==="
if [[ -f "${LOG_FILE}" ]]; then
    echo "Log: ${LOG_FILE}"
    awk '
        /\[PROGRESS\]/ { last_progress = $0 }
        /\[SUBMIT\]/ { attempts++ }
        /\[SKIP\]/ { skipped++ }
        END {
            if (last_progress != "") print last_progress
            printf "Submission attempts: %d\nSkip records: %d\n", attempts, skipped
        }
    ' "${LOG_FILE}"
    echo "Last 5 lines:"
    tail -5 "${LOG_FILE}"
else
    echo "No submission log found. Set SUBMISSION_LOG to select an existing log."
fi
echo "Expected campaign size: 1280 jobs (20 cases x 64 samples)."
echo "Log entries may include retries or failed submissions; they do not determine remaining jobs."

echo
echo "=== Allocation Records (samples 65-128, last 7 days) ==="
STARTDATE=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
# -X excludes job steps, which would otherwise count the same allocation again.
if ACCOUNTING=$(sacct -X -n -P -u "$USER" --format=JobName%200,State%40 --starttime="${STARTDATE}" 2>/dev/null); then
    awk -F '|' "$SAMPLE_AWK"'
    /^DT_CVaR/ {
        s = sample($1)
        if (s >= 65 && s <= 128) {
            if ($2 == "COMPLETED") completed++
            if ($2 == "FAILED") failed++
        }
    }
    END { printf "Completed: %d\nFailed: %d\n", completed, failed }
    ' <<< "$ACCOUNTING"
    echo "These are allocation counts, including reruns; scientific completion requires final.jld2."
else
    echo "Allocation status unavailable: sacct query failed."
fi
