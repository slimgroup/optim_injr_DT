#!/bin/bash
#SBATCH --job-name=selected_control_movies
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=01:30:00
#SBATCH --output=logs/out_selected_control_movies_%j.txt
#SBATCH --error=logs/err_selected_control_movies_%j.txt
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export HDF5_USE_FILE_LOCKING=FALSE
export MPLCONFIGDIR="/tmp/mpl_selected_control_movies_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
# Rendering only. No Julia, optimization, training, or forward simulation.
/usr/bin/python3 -u scripts/python_plots/create_selected_control_movies.py \
    --outdir "plots/paper_figures/p1_control_movies_20260913_${SLURM_JOB_ID}"
