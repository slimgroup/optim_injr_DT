#!/bin/bash
# Check ds verification status; resolve the repository root from any directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT_DIR}" || exit 1

echo "=== ds verification status check ==="
echo ""

# Check running jobs
echo "1. Running jobs:"
squeue -u $USER -o "%.10i %.12P %.20j %.8u %.2t %.10M %.6D %R" 2>/dev/null | head -5

echo ""
echo "2. Output file status:"
if [ -f ds_verification_output.txt ]; then
    echo "  File exists; line count: $(wc -l < ds_verification_output.txt)"
    echo ""
    echo "  Last 30 lines:"
    echo "  ----------------------------------------"
    tail -30 ds_verification_output.txt 2>/dev/null
    echo "  ----------------------------------------"
else
    echo "  Output file not yet created"
fi

echo ""
echo "3. If the job has completed, view all results:"
echo "  cat ds_verification_output.txt"

echo ""
echo "4. If the job is still running, follow live output:"
echo "  tail -f ds_verification_output.txt"

