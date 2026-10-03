#!/bin/bash
#SBATCH --job-name=posterior_all_cases_video
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:20:00
#SBATCH --output=logs/out_posterior_all_cases_video_%j.txt
#SBATCH --error=logs/err_posterior_all_cases_video_%j.txt

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR="/tmp/mpl_posterior_all_cases_${SLURM_JOB_ID}"
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export HDF5_USE_FILE_LOCKING=FALSE
mkdir -p "$MPLCONFIGDIR"
python -u scripts/python_plots/create_posterior_all_cases_video.py "$@"
