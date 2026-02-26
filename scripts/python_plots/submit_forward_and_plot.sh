#!/bin/bash
#SBATCH -J fwd_export
#SBATCH -A gts-fherrmann9-0
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 01:00:00
#SBATCH -q embers
#SBATCH -o %x-%j.out

module load julia/1.11.3
module load anaconda3/2023.03

cd $SLURM_SUBMIT_DIR

echo "=== Step 1: Julia forward simulation export ==="
julia scripts/python_plots/run_forward_export.jl

echo ""
echo "=== Step 2: Python 3-row comparison plot ==="
KMP_INIT_AT_FORK=FALSE python scripts/python_plots/plot_3row_comparison.py

echo "Done!"
