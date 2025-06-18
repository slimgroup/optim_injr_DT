#!/bin/bash
#SBATCH --job-name=scale_jutul
#SBATCH --output=output_scale_cpu%a.txt
#SBATCH --error=error_scale_cpu%a.txt
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --ntasks=1

# Load modules
module load Julia/1.8.5

# Record start time
start=$(date +%s)

# Run your Julia script
julia scripts/scaling_jutul_cruyff.jl --cpu $CPU

# Record end time
end=$(date +%s)
runtime=$((end - start))

echo "CPU: $CPU Runtime: ${runtime}s" >> runtime_log.txt
