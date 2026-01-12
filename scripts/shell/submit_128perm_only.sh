#!/bin/bash
#SBATCH --job-name=gen_128perm
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16GB
#SBATCH --time=00:30:00
#SBATCH --partition=cpu-small
#SBATCH --account=gts-fherrmann9
#SBATCH --output=logs/128perm_%j.out
#SBATCH --error=logs/128perm_%j.err

echo "Generating 128 permeability video..."
module load julia/1.10.1
module load anaconda3/2023.03

julia --project=. scripts/julia_scripts/plotting/generate_128samples_video.jl

echo "Creating video from frames..."
python scripts/create_videos_from_frames.py

echo "Done!"
