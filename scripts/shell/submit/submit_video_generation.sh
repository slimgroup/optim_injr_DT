#!/bin/bash
#SBATCH --job-name=gen_videos
#SBATCH --account=gts-fherrmann9
#SBATCH --qos=inferno
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=2:00:00
#SBATCH --output=logs/video_generation_%j.out
#SBATCH --error=logs/video_generation_%j.err

# Video generation script for CO2 injection simulations
# This script generates:
# 1. 5-case videos on ground truth permeability
# 2. 128-sample video showing permeability uncertainty

# Environment setup
module load anaconda3/2023.03
module load julia/1.10.1

# Navigate to project directory
cd /storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT

# Create logs directory if it doesn't exist
mkdir -p logs

echo "========================================"
echo "Starting video generation"
echo "Date: $(date)"
echo "========================================"

# Option 1: Generate 5-case videos (ground truth permeability)
# Skipping - already done
# echo ""
# echo "Generating 5-case frames..."
# julia --project=. scripts/julia_scripts/plotting/videos/generate_5case_videos.jl

# Option 2: Generate 128-sample video (permeability uncertainty)
echo ""
echo "Generating 128-sample frames..."
julia --project=. scripts/julia_scripts/plotting/videos/generate_128samples_video.jl

# Create videos from frames using Python
echo ""
echo "Creating videos from frames..."
pip install --user --quiet imageio imageio-ffmpeg
python scripts/python_plots/create_videos_from_frames.py

echo ""
echo "========================================"
echo "Video generation complete"
echo "Date: $(date)"
echo "========================================"
