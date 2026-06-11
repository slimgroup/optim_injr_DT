#!/bin/bash
#SBATCH --job-name=cvar728_sens
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --array=0-5
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/out_cvar728_sens_%A_%a.txt
#SBATCH --error=logs/err_cvar728_sens_%A_%a.txt

set -euo pipefail

module load julia/1.11.3
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"

julia scripts/julia_scripts/data_collection/forward_exports/run_cvar_day728_sensitivity_sweep.jl
