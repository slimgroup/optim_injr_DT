#!/bin/bash
#SBATCH --job-name=nc_severity
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --array=0-2
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/out_nc_severity_%A_%a.txt
#SBATCH --error=logs/err_nc_severity_%A_%a.txt

set -euo pipefail

module load julia/1.11.3
module load anaconda3/2023.03
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"

julia scripts/julia_scripts/data_collection/forward_exports/run_no_control_severity_sweep.jl
