#!/bin/bash
#SBATCH --job-name=paper_bhp_audit
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --array=0-6
#SBATCH --output=logs/bhp_audit_%A_%a.out
#SBATCH --error=logs/bhp_audit_%A_%a.err
set -euo pipefail
module load julia/1.11.3
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export OPENBLAS_NUM_THREADS=1
export JULIA_NUM_THREADS=1
cases=(POF_eps0 POF_eps0p01 CVaR_g01_a001 No_Control_shutdown POF_eps0p01_1p65x CVaR_g01_a001_1p22x CVaR_g01_a001_1p22x_Figure1)
audit_outdir="${BHP_AUDIT_OUTDIR:-data/diagnostics/bhp_audit_20260907_${SLURM_ARRAY_JOB_ID}}"
julia scripts/julia_scripts/utilities/audit_paper_bhp.jl "${cases[$SLURM_ARRAY_TASK_ID]}" "$audit_outdir"
