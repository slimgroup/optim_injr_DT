#!/bin/bash
# Check test status; resolve the repository root from any directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT_DIR}" || exit 1

echo "=== Checking ds test jobs ==="
echo ""

# Check running jobs
echo "Running jobs:"
squeue -u $USER -o "%.10i %.12P %.20j %.8u %.2t %.10M %.6D %R" 2>/dev/null

echo ""
echo "Recent job output files (logs/):"
ls -lt logs/*.out logs/*.err logs/utilities/*.out logs/utilities/*.err 2>/dev/null | head -5

echo ""
echo "If the job has completed, inspect its output:"
echo "  tail -f logs/ds_verification_<jobid>.out"
echo ""
echo "Or rerun to inspect results:"
echo "  srun --partition=interactive-cpu --time=00:30:00 --mem=8G --cpus-per-task=2 --pty bash -c 'module load julia/1.11.3 && export JULIA_DEPOT_PATH=\"\$HOME/julia-depot\" && mkdir -p \"\$JULIA_DEPOT_PATH\" && cd \"${ROOT_DIR}\" && julia test/integration/test_ds_minimal.jl'"
