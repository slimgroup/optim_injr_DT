#!/bin/bash
#SBATCH --job-name=boot_cdf
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=03:00:00
# Paths below are relative to the directory you were in when you ran `sbatch` (Slurm).
#SBATCH --output=logs/bootstrap_cdf_%j.out
#SBATCH --error=logs/bootstrap_cdf_%j.err

# Run from **repository root**:
#   cd /path/to/optim_injr_DT && sbatch scripts/shell/submit_bootstrap_cdf.sh
#
# Quick mode (no 4×3 grids):
#   cd .../optim_injr_DT && sbatch --export=ALL,BOOTSTRAP_QUICK=1 scripts/shell/submit_bootstrap_cdf.sh

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$PWD}"
export REPO_ROOT="$(pwd)"
mkdir -p logs

exec bash "$REPO_ROOT/scripts/shell/run_bootstrap_cdf.sh"
