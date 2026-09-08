#!/bin/bash
# Render only the eight posterior maps and three historical Appendix E grids.
#SBATCH --job-name=posterior_appendix_e_export
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --output=logs/out_posterior_appendix_e_export_%j.txt
#SBATCH --error=logs/err_posterior_appendix_e_export_%j.txt
#SBATCH --time=00:30:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR="/tmp/mplconfig_paper_export_${SLURM_JOB_ID}"
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
python -u scripts/python_plots/export_posterior_appendix_e.py --formats png pdf svg "$@"
