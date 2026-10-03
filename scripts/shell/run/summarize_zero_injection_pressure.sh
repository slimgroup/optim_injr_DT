#!/bin/bash
# Run analysis on PACE allocation, including future 128-member aggregation.
#SBATCH --job-name=zero_pressure_summary
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:20:00
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export MPLCONFIGDIR="${TMPDIR:-/tmp}/zero_pressure_mpl_${SLURM_JOB_ID}"
audit_root="${1:?audit root}"
report_out="${2:?new report directory}"
plot_out="${3:?new plot directory}"
python3 scripts/python_tools/analysis/summarize_zero_pressure_audit.py "$audit_root" "$report_out" "$plot_out"
julia --startup-file=no scripts/julia_scripts/utilities/summarize_zero_pressure_solver.jl "$audit_root" "$report_out/solver_steps.csv"
