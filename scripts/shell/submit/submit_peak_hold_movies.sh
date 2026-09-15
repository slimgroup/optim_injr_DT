#!/bin/bash
#SBATCH --job-name=peak_hold_movies
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=00:30:00
#SBATCH --output=logs/peak_hold_movies_%j.out
#SBATCH --error=logs/peak_hold_movies_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export HDF5_USE_FILE_LOCKING=FALSE
export MPLCONFIGDIR="/tmp/mpl_peak_hold_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
movie_outdir="plots/paper_figures/p1_peak_hold_movies_20260915_${SLURM_JOB_ID}"
/usr/bin/python3 -u scripts/python_plots/create_static_reference_movies.py \
    --outdir "$movie_outdir" --end-day 1920 --seconds 20 --compact-header "$@"
if [ -f "$movie_outdir/comparison.mp4" ]; then
    /usr/bin/python3 -u scripts/python_tools/analysis/validate_selected_control_media.py "$movie_outdir" --frames 600
fi
