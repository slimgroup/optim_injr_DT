#!/bin/bash

# SLURM job options
#SBATCH --job-name=optim_injr_DT         # Job name
#SBATCH --output=output_%j.txt            # Standard output file
#SBATCH --error=error_%j.txt              # Standard error file
#SBATCH --nodes=1                         # Number of nodes (1 node)
#SBATCH --cpus-per-task=4                 # Number of CPUs per task (4 threads per simulation)
#SBATCH --mem-per-cpu=8G                  # Memory per CPU (16GB per CPU)
#SBATCH --time=12:00:00                   # Max runtime (24 hours)
#SBATCH --partition=cpu                   # Request to run in the CPU partition
#SBATCH --gres=gpu:0                      # No GPU required
## commented SBATCH --nodelist=epyc[1-2]  # Request nodes epyc1 to epyc4

# Load necessary modules
module load Julia cudnn-11 nvhpc Miniconda/3

# Dynamically assign CPU cores to each task based on the task ID
task_id=$SLURM_ARRAY_TASK_ID

# Calculate the starting core for each task (this dynamically sets different cores for each task)
# start_core=$(( (task_id - 1) * 4 )) # Each task uses 4 cores
# end_core=$(( start_core + 3 ))      # 4 cores per task (task_id uses cores from start_core to end_core)

# Pin Julia to specific cores for each task
# taskset -c $start_core-$end_core julia --project=. --threads=4 scripts/co2eor_compass.jl --idx_num $task_id
julia src/optim_inject.jl --idx_num $task_id