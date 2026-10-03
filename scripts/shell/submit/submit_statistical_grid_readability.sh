#!/bin/bash
# Restyle only the three cached statistical grids; no analysis or simulation.
#SBATCH --job-name=stat_grid_readability
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --output=logs/out_stat_grid_readability_%j.txt
#SBATCH --error=logs/err_stat_grid_readability_%j.txt

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
module load anaconda3/2023.03
export MPLBACKEND=Agg
export MPLCONFIGDIR="/tmp/mpl_stat_grid_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
python -u scripts/python_plots/refine_statistical_grid_readability.py "$@"
