#!/bin/bash
#SBATCH --job-name=posterior_margin_sensitivity
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --output=logs/out_posterior_margin_sensitivity_%j.txt
#SBATCH --error=logs/err_posterior_margin_sensitivity_%j.txt
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLBACKEND=Agg
export MPLCONFIGDIR="/tmp/mpl_margin_sensitivity_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
python -u scripts/python_plots/preview_posterior_margin_sensitivity.py "$@"
