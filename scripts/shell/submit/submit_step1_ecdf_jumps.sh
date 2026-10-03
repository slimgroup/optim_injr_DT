#!/bin/bash
#SBATCH --job-name=step1_ecdf_jumps
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=12G
#SBATCH --time=00:20:00
#SBATCH --output=logs/step1_ecdf_jumps_%j.out
#SBATCH --error=logs/step1_ecdf_jumps_%j.err

set -euo pipefail
[[ $# -ge 2 && $# -le 3 ]] || { echo "Usage: $0 NEW_PLOT_DIR CACHE_DIR [--render-only|--histograms-only]" >&2; exit 2; }
cd "${SLURM_SUBMIT_DIR:?Submit from the repository root}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=2 JULIA_PKG_PRECOMPILE_AUTO=0
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MPLBACKEND=Agg
export MPLCONFIGDIR="${TMPDIR:-/tmp}/step1_ecdf_mpl_${SLURM_JOB_ID}"
mkdir -p "$MPLCONFIGDIR"
module purge
module load julia/1.12.5
exec julia --project=. scripts/julia_scripts/plotting/bootstrap_ecdf/reexport_step1_ecdf_jumps.jl "$@"
