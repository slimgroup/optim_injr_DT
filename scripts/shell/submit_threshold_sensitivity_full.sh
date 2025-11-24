#!/bin/bash
#SBATCH --job-name=thresh_sens_full_128
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --output=logs/threshold_sensitivity_full_%j.txt
#SBATCH --error=logs/threshold_sensitivity_full_%j.txt
#SBATCH --signal=TERM@60
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

# Full run threshold sensitivity analysis (POF + CVaR enabled, auto-calibration)
# Estimated runtime: 10-20 hours (10 thresholds, 20 iterations each)

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment (PyCall stable, single-threaded plotting)
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

trap 'echo "[WARN] SIGTERM received; try to save…"' TERM

# Change to project directory
cd "$SLURM_SUBMIT_DIR"

echo "Job started at $(date)"
echo "Running threshold sensitivity analysis (full mode)"

# Run Julia script (full parameters)
julia --project="$SLURM_SUBMIT_DIR" -t 1 src/threshold_sensitivity.jl \
  --idx_num 128 \
  --use_pof \
  --use_cvar \
  --eps_pof 0.01 \
  --lambda_pof 1.0 \
  --lambda_cvar 1.0 \
  --calibrate_gamma \
  --niterations 20 \
  --threshold_num 10 \
  --threshold_min 2.0 \
  --threshold_max 6.0

echo "Job completed at $(date)"

