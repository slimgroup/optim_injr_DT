#!/bin/bash

# Combined scaling script — submits and runs SLURM jobs for various CPU counts

# Create logs directory if it doesn't exist
mkdir -p logs

# List of CPU counts to test
for cpu in 8 16 32
# for cpu in 1 2 4
do
  echo "Submitting job with ${cpu} CPUs..."

  sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=scale_cpu_${cpu}
#SBATCH --output=logs/output_scale_cpu_${cpu}.txt
#SBATCH --error=logs/error_scale_cpu_${cpu}.txt
#SBATCH --cpus-per-task=${cpu}
#SBATCH --mem=32G
#SBATCH --time=04:00:00

# Load necessary modules
module load Julia/1.8/5 Miniconda/3

# Record start time
start=\$(date +%s)

# Run the Julia script
julia scripts/scaling_jutul_cruyff.jl

# Record end time and compute runtime
end=\$(date +%s)
runtime=\$((end - start))

# Log runtime information
echo "CPU: ${cpu} Runtime: \${runtime}s"
echo "CPU: ${cpu} Runtime: \${runtime}s" >> /nethome/hli853/optim_injr_DT/runtime_log.txt
EOF

done


# chmod +x scripts/run_scaling_all.sh
# ./scripts/run_scaling_all.sh
