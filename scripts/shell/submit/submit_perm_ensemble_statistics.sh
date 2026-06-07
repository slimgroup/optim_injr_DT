#!/bin/bash
#SBATCH --job-name=perm_ensemble_stats
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=01:00:00
#SBATCH --output=logs/out_perm_ensemble_stats_%j.txt
#SBATCH --error=logs/err_perm_ensemble_stats_%j.txt

set -euo pipefail

module load anaconda3/2023.03
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR="/tmp/mplconfig_${SLURM_JOB_ID}"
mkdir -p "$MPLCONFIGDIR"

python scripts/python_plots/plot_perm_ensemble.py
