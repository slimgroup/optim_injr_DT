#!/bin/bash
#SBATCH --job-name=gamma_table_gen
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 4:00:00
#SBATCH -q inferno
#SBATCH --output=logs/gamma_table_gen_%j.txt
#SBATCH --error=logs/gamma_table_gen_%j.txt
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

# Generate gamma table using improved binary search method
# Estimated runtime: 15-25 minutes (5 thresholds, 1 eps value)

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

# Change to project directory
cd "$SLURM_SUBMIT_DIR"

echo "Job started at $(date)"
echo "Generating gamma table with improved binary search method"
echo ""

# Configuration
EPS_LIST="${EPS_LIST:-0.01}"
THRESHOLD_MIN="${THRESHOLD_MIN:-2.0}"
THRESHOLD_MAX="${THRESHOLD_MAX:-6.0}"
THRESHOLD_NUM="${THRESHOLD_NUM:-5}"

echo "Configuration:"
echo "  Sample index: 128"
echo "  Eps values: $EPS_LIST"
echo "  Thresholds: $THRESHOLD_MIN to $THRESHOLD_MAX ($THRESHOLD_NUM values)"
echo ""

# Run gamma table generation
julia --project="$SLURM_SUBMIT_DIR" -t 1 src/threshold_sensitivity.jl \
  --idx_num 128 \
  --threshold_min "$THRESHOLD_MIN" \
  --threshold_max "$THRESHOLD_MAX" \
  --threshold_num "$THRESHOLD_NUM" \
  --gamma_table_generate auto \
  --gamma_table_eps_list "$EPS_LIST"

echo ""
echo "Job completed at $(date)"
echo ""
echo "Gamma table saved to: data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2"
echo ""
echo "To verify accuracy, run:"
echo "  julia --project=. scripts/julia_scripts/utilities/check_gamma_table.jl <table_path>"

