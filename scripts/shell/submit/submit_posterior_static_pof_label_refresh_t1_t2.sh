#!/bin/bash
# Refresh existing t1/t2 static posterior PNGs after display-label edits.
# This intentionally skips videos and does not clear output directories.
# It only overwrites generated PNGs in-place with current plotting labels.
#SBATCH --job-name=posterior_pof_labels
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --output=logs/out_posterior_pof_labels_%j.txt
#SBATCH --error=logs/err_posterior_pof_labels_%j.txt
#SBATCH --time=01:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$PWD}"

export MPLCONFIGDIR=/tmp/mplconfig_${SLURM_JOB_ID}
mkdir -p "$MPLCONFIGDIR"

python scripts/python_plots/plot_posterior_uncertainty.py \
  --input data/posterior/three_set_posteriro_samples_t1_pof_cvar.jld2 \
  --outdir plots/posterior_field_uncertainty \
  --monitoring-step t=1 \
  --skip-videos

python scripts/python_plots/plot_posterior_uncertainty.py \
  --input data/posterior/three_set_posteriro_samples_t2_pof_cvar.jld2 \
  --outdir plots/posterior_field_uncertainty_t2_static \
  --monitoring-step t=2 \
  --skip-videos
