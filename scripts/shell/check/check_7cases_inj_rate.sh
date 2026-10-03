#!/usr/bin/env bash
# Run the injection-rate check for seven recovery cases.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
JULIA_SCRIPT="${ROOT_DIR}/scripts/julia_scripts/utilities/check_7cases_inj_rate.jl"

cd "${ROOT_DIR}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"

# Try to locate Julia
if command -v julia &> /dev/null; then
    julia "${JULIA_SCRIPT}"
else
    echo "Error: julia command not found"
    echo "Ensure julia is on PATH, or submit the job with sbatch"
    exit 1
fi
