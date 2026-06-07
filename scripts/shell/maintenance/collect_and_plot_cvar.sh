#!/bin/bash
# Script to collect CVaR data and generate histogram plots
# This script collects data from all 20 CVaR cases and generates the histogram

set -euo pipefail

# Load Julia module
module purge
module load julia 2>/dev/null || true

# Set up environment
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1

# Get project root
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=========================================="
echo "Step 1: Collecting CVaR data"
echo "=========================================="

# Run data collection script
julia --project=. scripts/julia_scripts/data_collection/collect_cvar_only.jl

echo ""
echo "=========================================="
echo "Step 2: Generating histogram plots"
echo "=========================================="

# Run plotting script
julia --project=. scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_cvar.jl

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="

