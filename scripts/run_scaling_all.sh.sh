#!/bin/bash

# Combined scaling script — submits and runs SLURM jobs for various CPU counts

# Loop over CPU counts
# for cpu in 1 2 4 8 16 32
for cpu in 8 16 
do
  echo "Submitting job with $cpu CPUs..."

  sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=scale_cpu_${cpu}
#SBATCH --output=logs/output_scale_cpu_${cpu}.txt
#SBATCH --error=logs/error_scale_cpu_${cpu}.txt
#SBATCH --cpus-per-task=${cpu}
#SBATCH --mem=32G
#SBATCH --time=01:00:00

module load Julia/1.8.5 Miniconda/3

start=\$(date +%s)

julia scripts/scaling_jutul_cruyff.jl 

end=\$(date +%s)
runtime=\$((end - start))

echo "CPU: \$CPU Runtime: \${runtime}s" >> /nethome/hli853/optim_injr_DT/runtime_log.txt
EOF

done
