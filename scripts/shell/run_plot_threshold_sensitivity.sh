#!/bin/bash
# Quick script to run the combined threshold sensitivity plotting

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

cd /storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT

echo "Running combined threshold sensitivity plotting..."
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity_combined.jl

echo ""
echo "✓ Plotting complete!"
echo "Check plots in: plots/DT_control/exp_name=step1/threshold_sensitivity/"

