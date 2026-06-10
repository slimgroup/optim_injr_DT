#!/bin/bash
#SBATCH --job-name=ctrl_day728
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --array=0-1
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=logs/out_ctrl_day728_%A_%a.txt
#SBATCH --error=logs/err_ctrl_day728_%A_%a.txt

set -euo pipefail

module load julia/1.11.3
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"

julia scripts/julia_scripts/data_collection/forward_exports/run_controlled_day728_from_day720.jl
