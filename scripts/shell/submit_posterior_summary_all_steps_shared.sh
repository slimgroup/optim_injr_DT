#!/bin/bash
#SBATCH --job-name=posterior_summary_all_steps
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --output=logs/out_posterior_summary_all_steps_%j.txt
#SBATCH --error=logs/err_posterior_summary_all_steps_%j.txt
#SBATCH --time=02:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR=/tmp/mplconfig_${SLURM_JOB_ID}
mkdir -p "$MPLCONFIGDIR"

python scripts/plot_posterior_summary_all_steps.py
