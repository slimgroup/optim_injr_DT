#!/bin/bash
#SBATCH --job-name=scale_jutul
#SBATCH --mem=32G
#SBATCH --time=01:00:00

# Use a default if CPU is not passed
CPU=${CPU:-1}

echo "Started job on CPU=$CPU"

module load Julia/1.8.5

which julia
julia --version

start=$(date +%s)

# Run your Julia script
julia scripts/scaling_jutul_cruyff.jl --cpu $CPU

end=$(date +%s)
runtime=$((end - start))

echo "CPU: $CPU Runtime: ${runtime}s" >> /nethome/hli853/optim_injr_DT/runtime_log.txt
