#!/bin/bash
#SBATCH --job-name=nc_severity_plot
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --output=logs/out_nc_severity_plot_%j.txt
#SBATCH --error=logs/err_nc_severity_plot_%j.txt

set -euo pipefail

module load anaconda3/2023.03
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export MPLCONFIGDIR="/tmp/mplconfig_${SLURM_JOB_ID}"
mkdir -p "$MPLCONFIGDIR"

python scripts/python_plots/plot_no_control_severity_sweep.py
