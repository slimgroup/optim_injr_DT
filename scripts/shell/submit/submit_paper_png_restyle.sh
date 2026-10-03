#!/bin/bash
# Render cached paper arrays with compact titles and separate 1x3 rate panels.
#SBATCH --job-name=paper_png_restyle
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --output=logs/out_paper_png_restyle_%j.txt
#SBATCH --error=logs/err_paper_png_restyle_%j.txt
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
# Use the same Python environment as the verified historical paper exporter.
export MPLBACKEND=Agg
export MPLCONFIGDIR="/tmp/mpl_paper_restyle_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
python -u scripts/python_plots/restyle_paper_pngs.py "$@"
