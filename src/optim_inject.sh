#!/bin/bash

# SLURM job options
#SBATCH --job-name=optim_injr_DT          # Job name
#SBATCH --output=output_%j.txt            # Standard output file
#SBATCH --error=error_%j.txt              # Standard error file
#SBATCH --cpus-per-task=32                # Number of CPUs per task 
#SBATCH --mem=32G                         # Total memory
#SBATCH --time=12:00:00                   # Max runtime 
#SBATCH --gres=gpu:0                      # No GPU required

# Load necessary modules
module load Julia/1.8/5 Miniconda/3

# Dynamically assign CPU cores to each task based on the task ID
task_id=$SLURM_ARRAY_TASK_ID

julia src/optim_inject_cruyff.jl --idx_num $task_id

## commented sbatch --array=1-2 optim_inject.sh