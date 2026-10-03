#!/bin/bash
#SBATCH --job-name=joint_perm_day480
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/joint_perm_day480_%A_%a.out
#SBATCH --error=logs/joint_perm_day480_%A_%a.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export HDF5_USE_FILE_LOCKING=FALSE
run_dir="${1:?Pass the approved run directory}"
test -f "$run_dir/approval.json"
julia --startup-file=no --project=. "$run_dir/code/run_joint_permeability_forward.jl" \
  "${SLURM_ARRAY_TASK_ID:?Submit with explicit member array}" "$run_dir"
