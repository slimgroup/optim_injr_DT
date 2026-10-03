#!/bin/bash
#SBATCH --job-name=joint_perm_movie
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --output=logs/joint_perm_movie_%j.out
#SBATCH --error=logs/joint_perm_movie_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR="/tmp/mpl_joint_movie_${SLURM_JOB_ID}"
export MPLBACKEND=Agg OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export HDF5_USE_FILE_LOCKING=FALSE
mkdir -p "$MPLCONFIGDIR"
python -u scripts/python_plots/create_joint_permeability_movie.py "$@"
