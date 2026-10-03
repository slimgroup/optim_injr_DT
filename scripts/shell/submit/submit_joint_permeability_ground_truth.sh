#!/bin/bash
#SBATCH --job-name=joint_perm_gt2000
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/joint_perm_gt2000_%j.out
#SBATCH --error=logs/joint_perm_gt2000_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 HDF5_USE_FILE_LOCKING=FALSE
ensemble_dir="${1:?Pass the existing ensemble directory}"
reference_dir="${2:?Pass a NEW reference directory}"
test ! -e "$reference_dir"
julia --startup-file=no --project=. \
    scripts/julia_scripts/data_collection/forward_exports/run_joint_permeability_ground_truth.jl \
    "$ensemble_dir" "$reference_dir"
