#!/bin/bash

# Loop over different CPU counts
for cpu in 1 2 4 8 16 32
do
  sbatch --cpus-per-task=$cpu --export=CPU=$cpu scaling_runner.sh
done
