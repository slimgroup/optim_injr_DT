#!/usr/bin/env bash
# SBATCH script to check 7 missing samples for outliers

#SBATCH --job-name=check_7cases_outlier
#SBATCH --output=logs/check_7cases_outlier_%j.out
#SBATCH --error=logs/check_7cases_outlier_%j.err
#SBATCH --time=00:10:00
#SBATCH --mem=4G
#SBATCH --partition=cpu-short
#SBATCH --account=gts-fherrmann9

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT_DIR}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"

echo "=========================================="
echo "Checking 7 missing samples for outliers"
echo "=========================================="
echo ""

julia scripts/julia_scripts/utilities/check_7cases_outlier_analysis.jl

echo ""
echo "=========================================="
echo "Done"
echo "=========================================="
