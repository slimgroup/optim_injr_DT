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
##SBATCH --mail-user=YOUR_EMAIL@example.com

# Generate gamma lookup table for threshold sensitivity analysis
# Estimated runtime: 15-25 minutes (5 thresholds, 1 eps value)
#
# Usage:
#   # Default settings (eps=0.01, 5 thresholds: 2.0-6.0)
#   sbatch scripts/shell/submit/submit_gamma_table_generation.sh
#   
#   # Custom eps values and thresholds
#   export EPS_LIST=0.005,0.01,0.02 THRESHOLD_MIN=2.0 THRESHOLD_MAX=6.0 THRESHOLD_NUM=10
#   sbatch scripts/shell/submit/submit_gamma_table_generation.sh

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

cd "$SLURM_SUBMIT_DIR"

echo "Job started at $(date)"
echo "Generating gamma lookup table"
echo ""

# Configuration (with defaults)
IDX_NUM="${IDX_NUM:-128}"
EPS_LIST="${EPS_LIST:-0.01}"
THRESHOLD_MIN="${THRESHOLD_MIN:-2.0}"
THRESHOLD_MAX="${THRESHOLD_MAX:-6.0}"
THRESHOLD_NUM="${THRESHOLD_NUM:-5}"

echo "Configuration:"
echo "  Sample index: $IDX_NUM"
echo "  Eps values: $EPS_LIST"
echo "  Thresholds: $THRESHOLD_MIN to $THRESHOLD_MAX ($THRESHOLD_NUM values)"
echo ""

# Run gamma table generation (use all available threads for parallel processing)
julia --project="$SLURM_SUBMIT_DIR" -t "$SLURM_CPUS_PER_TASK" src/threshold_sensitivity.jl \
  --idx_num "$IDX_NUM" \
  --threshold_min "$THRESHOLD_MIN" \
  --threshold_max "$THRESHOLD_MAX" \
  --threshold_num "$THRESHOLD_NUM" \
  --gamma_table_generate auto \
  --gamma_table_eps_list "$EPS_LIST"

echo ""
echo "Job completed at $(date)"
echo ""
echo "Gamma table saved to: data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=${IDX_NUM}__*.jld2"
