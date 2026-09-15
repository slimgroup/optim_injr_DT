#!/bin/bash
#SBATCH --job-name=continued_reference_movies
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=01:30:00
#SBATCH --output=logs/continued_reference_movies_%j.out
#SBATCH --error=logs/continued_reference_movies_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$PWD}"
continuation_file="$1"
movie_outdir="plots/paper_figures/p1_continued_reference_movies_20260914_${SLURM_JOB_ID}"
export HDF5_USE_FILE_LOCKING=FALSE
export MPLCONFIGDIR="/tmp/mpl_continued_reference_${SLURM_JOB_ID}"
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p "$MPLCONFIGDIR"
/usr/bin/python3 -u scripts/python_plots/create_static_reference_movies.py \
    --outdir "$movie_outdir" --end-day 1920 --no-control-continuation "$continuation_file"
/usr/bin/python3 -u scripts/python_tools/analysis/analyze_no_control_continuation.py \
    --source "$continuation_file" --outdir "$movie_outdir"
/usr/bin/python3 -u scripts/python_tools/analysis/validate_selected_control_media.py "$movie_outdir"
