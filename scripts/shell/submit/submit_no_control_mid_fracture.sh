#!/bin/bash
#SBATCH --job-name=nc_mid_frac
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/out_nc_mid_frac_%j.txt
#SBATCH --error=logs/err_nc_mid_frac_%j.txt

set -euo pipefail

module load julia/1.11.3
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"

julia scripts/julia_scripts/data_collection/forward_exports/run_no_control_mid_fracture.jl
