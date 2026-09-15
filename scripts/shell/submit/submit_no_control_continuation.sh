#!/bin/bash
#SBATCH --job-name=no_control_continue
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:30:00
#SBATCH --output=logs/no_control_continue_%j.out
#SBATCH --error=logs/no_control_continue_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export HDF5_USE_FILE_LOCKING=FALSE
julia scripts/julia_scripts/data_collection/forward_exports/continue_no_control_from_day800.jl \
    "data/forward/no_control_continued_20260914_${SLURM_JOB_ID}"
