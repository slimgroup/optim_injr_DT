#!/bin/bash
# Check ds verification status and results; resolve the repository root from any directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT_DIR}" || exit 1

# Find the latest ds_verification job
JOB_ID=$(squeue -u $USER -o "%.10i %.20j" 2>/dev/null | grep "ds_verification" | awk '{print $1}' | head -1)

# If no job is running, find the latest output file
if [ -z "${JOB_ID}" ]; then
    LATEST_OUTPUT=$(ls -t logs/utilities/ds_verification_*.out logs/ds_verification_*.out 2>/dev/null | head -1)
    if [ -n "${LATEST_OUTPUT}" ]; then
        JOB_ID=$(echo "${LATEST_OUTPUT}" | sed 's/.*ds_verification_\([0-9]*\)\.out/\1/')
    else
        JOB_ID="3142377"  # Historical fallback job ID
    fi
fi

echo "=== ds verification status ==="
echo ""

# Check job status
echo "1. Job status:"
squeue -j ${JOB_ID} -o "%.10i %.12P %.20j %.8u %.2t %.10M %.6D %R" 2>/dev/null || echo "  Job completed or absent from the queue"
echo ""

# Check output files
echo "2. Output file:"
OUTPUT_FILE=$(ls -t logs/utilities/ds_verification_${JOB_ID}.out logs/ds_verification_${JOB_ID}.out 2>/dev/null | head -1)
ERROR_FILE=$(ls -t logs/utilities/ds_verification_${JOB_ID}.err logs/ds_verification_${JOB_ID}.err 2>/dev/null | head -1)

if [ -f "${OUTPUT_FILE}" ]; then
    echo "  Output file: ${OUTPUT_FILE}"
    echo "  Line count: $(wc -l < ${OUTPUT_FILE})"
    echo ""
    echo "  Last 50 lines:"
    echo "  ----------------------------------------"
    tail -50 "${OUTPUT_FILE}" 2>/dev/null
    echo "  ----------------------------------------"
else
    echo "  Output file not yet created; the job may be queued or starting"
fi

if [ -f "${ERROR_FILE}" ]; then
    echo ""
    echo "3. Error file:"
    echo "  ${ERROR_FILE}"
    if [ -s "${ERROR_FILE}" ]; then
        echo "  Error contents:"
        cat "${ERROR_FILE}"
    else
        echo "  (No errors)"
    fi
fi

echo ""
echo "4. Follow live output:"
echo "  tail -f logs/ds_verification_${JOB_ID}.out"
echo ""
echo "5. View complete results:"
echo "  cat logs/ds_verification_${JOB_ID}.out"

