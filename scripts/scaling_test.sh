#!/bin/bash

# Create logs directory if needed
mkdir -p logs

# Loop over CPU counts
for cpu in 1 2 4 8 16 32
do
  echo "Submitting job with $cpu CPUs..."
  sbatch --job-name=scale_cpu_${cpu} \
         --cpus-per-task=$cpu \
         --output=logs/output_scale_cpu_${cpu}.txt \
         --error=logs/error_scale_cpu_${cpu}.txt \
         --export=CPU=$cpu \
         scripts/scaling_runner.sh
done
