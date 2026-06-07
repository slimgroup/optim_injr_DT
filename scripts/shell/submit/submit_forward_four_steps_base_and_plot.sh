#!/bin/bash
#SBATCH --job-name=fwd_four_steps_base
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/out_fwd_four_steps_base_%j.txt
#SBATCH --error=logs/err_fwd_four_steps_base_%j.txt

set -euo pipefail

module load julia/1.11.3
module load anaconda3/2023.03

cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export MPLCONFIGDIR=/tmp/mplconfig_${SLURM_JOB_ID}
mkdir -p "$MPLCONFIGDIR"

echo "=== Step 1: four-step Julia forward simulation export ==="
julia scripts/julia_scripts/data_collection/forward_exports/run_forward_four_steps_base_export.jl

echo ""
echo "=== Step 2: base-rate ground-truth comparison plot ==="
KMP_INIT_AT_FORK=FALSE python scripts/python_plots/plot_fracture_comparison_four_steps_base.py

echo ""
echo "=== Step 3: four-step injection schedule with forward-derived fracture ==="
KMP_INIT_AT_FORK=FALSE python scripts/python_plots/plot_injection_schedule_over_four_steps.py

echo "Done!"
