#!/bin/bash
#SBATCH --job-name=joint_perm_64_movie
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --output=logs/joint_perm_64_movie_%j.out
#SBATCH --error=logs/joint_perm_64_movie_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR="/tmp/mpl_joint1920_${SLURM_JOB_ID}"
export MPLBACKEND=Agg OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 HDF5_USE_FILE_LOCKING=FALSE
mkdir -p "$MPLCONFIGDIR"
run_dir="${1:?Approved run directory required}"
shift
renderer_dir="${JOINT_PERM_RENDERER_DIR:-$run_dir/code/render_final}"
python -u "$renderer_dir/create_joint_permeability_day1920_movie.py" "$run_dir" "$@"
