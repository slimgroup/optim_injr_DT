#!/bin/bash
#SBATCH --job-name=fig67_decimal4
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --output=logs/figures67_decimal4_%j.out
#SBATCH --error=logs/figures67_decimal4_%j.err

# From repository root:
# sbatch scripts/shell/submit/submit_figures_6_7_decimal4.sh NEW_PLOT_DIR NEW_CACHE_DIR
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 NEW_PLOT_DIR NEW_CACHE_DIR" >&2; exit 2; }
cd "${SLURM_SUBMIT_DIR:?Submit from the repository root}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=2
export JULIA_PKG_PRECOMPILE_AUTO=0
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MPLBACKEND=Agg
export MPLCONFIGDIR="${TMPDIR:-/tmp}/figures67_mpl_${SLURM_JOB_ID}"
mkdir -p "$MPLCONFIGDIR"
module purge
module load julia/1.12.5
exec julia --project=. scripts/julia_scripts/plotting/bootstrap_ecdf/reexport_figures_6_7.jl "$1" "$2"
