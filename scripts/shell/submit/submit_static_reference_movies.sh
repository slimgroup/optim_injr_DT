#!/bin/bash
#SBATCH --job-name=static_reference_movies
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=01:30:00
#SBATCH --output=logs/out_static_reference_movies_%j.txt
#SBATCH --error=logs/err_static_reference_movies_%j.txt
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export HDF5_USE_FILE_LOCKING=FALSE
export MPLCONFIGDIR="/tmp/mpl_static_reference_movies_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
# Render saved fields only. --no-control-continuation PATH uses a separately
# validated continuation; otherwise --end-day 1920 labels the held day728 state.
/usr/bin/python3 -u scripts/python_plots/create_static_reference_movies.py \
    --outdir "plots/paper_figures/p1_static_reference_movies_20260914_${SLURM_JOB_ID}" "$@"
