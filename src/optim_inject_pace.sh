#!/bin/bash

# SLURM job options
#SBATCH --job-name=optim_injr_DT                      # Job name
#SBATCH --account=gts-fherrmann9                      # charge account
#SBATCH -N1 --ntasks-per-node=8                       # Number of nodes and cores per node required
#SBATCH --mem-per-cpu=4G                              # Memory per core
#SBATCH -t12:00:00                                    # Duration of the job (Ex: 1 hour)
#SBATCH -qinferno                                     # QOS Name
## #SBATCH -oReport-%a.out                            # Combined output and error messages file
#SBATCH --output=logs/output_DT_step1_t4_f2_%a.txt    # Standard output file
#SBATCH --error=logs/error_DT_step1_t4_f2_%a.txt      # Standard error file
#SBATCH --mail-type=BEGIN,END,FAIL                    # Mail preferences
#SBATCH --mail-user=hli853@gatech.edu                  # E-mail address for notifications

# Load necessary modules
module load julia/1.10.1 anaconda3
pip install cmasher --user

# Dynamically assign CPU cores to each task based on the task ID
task_id=$SLURM_ARRAY_TASK_ID

julia -t 1 src/optim_inject.jl --idx_num $task_id

## commented sbatch --array=1-2 src/optim_inject_pace.sh