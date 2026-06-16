#!/usr/bin/env bash
# Script to check progress of missing POF samples
# Job IDs: 3131882 (sample 18), 3131883 (sample 64)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DATA_DIR="${ROOT_DIR}/data/DT_control/exp_name=step1"

echo "=========================================="
echo "Missing Samples Progress Check"
echo "=========================================="
echo ""

# Check job status
echo "=== Job Status ==="
squeue -u $USER -j 3131882,3131883 --format="%.18i %.20j %.8u %.2t %.10M %.6D %R" 2>&1 || echo "Jobs may have completed"
echo ""

# Check if final.jld2 files exist
echo "=== Output Files ==="
final_path1="${DATA_DIR}/POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0/sample=18/final.jld2"
final_path2="${DATA_DIR}/POF__HARD__eps=0.05__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0/sample=64/final.jld2"

if [ -f "$final_path1" ]; then
    size=$(ls -lh "$final_path1" | awk '{print $5}')
    mtime=$(stat -c %y "$final_path1" | cut -d'.' -f1)
    echo "✓ POF eps=0.01, sample=18: final.jld2 exists (${size}, modified: ${mtime})"
else
    echo "✗ POF eps=0.01, sample=18: final.jld2 not found yet"
fi

if [ -f "$final_path2" ]; then
    size=$(ls -lh "$final_path2" | awk '{print $5}')
    mtime=$(stat -c %y "$final_path2" | cut -d'.' -f1)
    echo "✓ POF eps=0.05, sample=64: final.jld2 exists (${size}, modified: ${mtime})"
else
    echo "✗ POF eps=0.05, sample=64: final.jld2 not found yet"
fi
echo ""

# Check latest log entries
echo "=== Latest Log Entries ==="
log_file1="${ROOT_DIR}/logs/out_DT_POF_eps=0.01_s18_fix_3131882_18.txt"
log_file2="${ROOT_DIR}/logs/out_DT_POF_eps=0.05_s64_fix_3131883_64.txt"

if [ -f "$log_file1" ]; then
    echo "--- POF eps=0.01, sample=18 (last 5 lines) ---"
    tail -5 "$log_file1" 2>/dev/null || echo "  (log file empty or not readable)"
else
    echo "--- POF eps=0.01, sample=18 ---"
    echo "  Log file not found"
fi
echo ""

if [ -f "$log_file2" ]; then
    echo "--- POF eps=0.05, sample=64 (last 5 lines) ---"
    tail -5 "$log_file2" 2>/dev/null || echo "  (log file empty or not readable)"
else
    echo "--- POF eps=0.05, sample=64 ---"
    echo "  Log file not found"
fi
echo ""

# Check for errors
echo "=== Error Logs ==="
err_file1="${ROOT_DIR}/logs/err_DT_POF_eps=0.01_s18_fix_3131882_18.txt"
err_file2="${ROOT_DIR}/logs/err_DT_POF_eps=0.05_s64_fix_3131883_64.txt"

if [ -f "$err_file1" ]; then
    err_size=$(wc -l < "$err_file1" 2>/dev/null || echo "0")
    if [ "$err_size" -gt 0 ]; then
        echo "--- POF eps=0.01, sample=18 errors (last 3 lines) ---"
        tail -3 "$err_file1" 2>/dev/null || echo "  (error reading log)"
    else
        echo "✓ POF eps=0.01, sample=18: No errors in log"
    fi
fi

if [ -f "$err_file2" ]; then
    err_size=$(wc -l < "$err_file2" 2>/dev/null || echo "0")
    if [ "$err_size" -gt 0 ]; then
        echo "--- POF eps=0.05, sample=64 errors (last 3 lines) ---"
        tail -3 "$err_file2" 2>/dev/null || echo "  (error reading log)"
    else
        echo "✓ POF eps=0.05, sample=64: No errors in log"
    fi
fi
echo ""

# Check job history
echo "=== Job History ==="
sacct -j 3131882,3131883 --format=JobID,JobName,State,ExitCode,Elapsed,Start,End --parsable2 2>&1 | grep -E "^3131882_18|^3131883_64" | head -2 || echo "No history found"
echo ""

echo "=========================================="
echo "Check complete!"
echo "=========================================="
