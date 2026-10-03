#!/bin/bash
#SBATCH --job-name=pof_jump_compare
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --output=logs/pof_jump_comparison_%j.out
#SBATCH --error=logs/pof_jump_comparison_%j.err

set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 CACHE_JLD2 NEW_OUTPUT_DIR"; exit 2; }
cd "${SLURM_SUBMIT_DIR:?Submit from the repository root}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=1
export JULIA_PKG_PRECOMPILE_AUTO=0
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
module purge
module load julia/1.12.5
exec julia --project=. scripts/julia_scripts/plotting/bootstrap_ecdf/export_pof_jump_comparison.jl "$1" "$2"
