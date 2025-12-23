#!/bin/bash
#SBATCH --job-name=cvar_g0
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-3
#SBATCH --output=logs/cvar_gamma0_%A_%a.out
#SBATCH --error=logs/cvar_gamma0_%A_%a.err

# CVaR cases with gamma=0.0 and alpha=0.01, 0.02, 0.05
# Array task 1: alpha=0.01
# Array task 2: alpha=0.02
# Array task 3: alpha=0.05

module purge
module load julia/1.11.3

# Set alpha based on array task ID
case $SLURM_ARRAY_TASK_ID in
    1)
        ALPHA=0.01
        ;;
    2)
        ALPHA=0.02
        ;;
    3)
        ALPHA=0.05
        ;;
esac

echo "=========================================="
echo "CVaR Case: gamma=0.0, alpha=$ALPHA"
echo "Task ID: $SLURM_ARRAY_TASK_ID"
echo "=========================================="

export JULIA_DEPOT_PATH="$HOME/julia-depot"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

cd /storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT

julia --project=. src/optim_inject.jl \
    --idx_num 128 \
    --alpha $ALPHA \
    --use_cvar \
    --lambda_cvar 1.0 \
    --gamma_cvar 0.0 \
    --cvar_soft \
    --niterations 20 \
    --inj_guess 0.05 \
    --inj_start 0.0001 \
    --save_plots \
    --plot_stride 5 \
    --save_states \
    --save_every 1

echo "=========================================="
echo "Completed: CVaR gamma=0.0, alpha=$ALPHA"
echo "=========================================="

