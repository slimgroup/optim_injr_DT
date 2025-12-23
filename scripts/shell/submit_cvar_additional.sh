#!/bin/bash
#SBATCH --job-name=cvar_add
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-8
#SBATCH --output=logs/cvar_additional_%A_%a.out
#SBATCH --error=logs/cvar_additional_%A_%a.err

# CVaR additional cases:
# Tasks 1-4: alpha=0.0, gamma=0.0, 0.01, 0.02, 0.05
# Tasks 5-8: alpha=0.001, gamma=0.0, 0.01, 0.02, 0.05

module purge
module load julia/1.11.3

# Set alpha and gamma based on array task ID
case $SLURM_ARRAY_TASK_ID in
    1)
        ALPHA=0.0
        GAMMA=0.0
        ;;
    2)
        ALPHA=0.0
        GAMMA=0.01
        ;;
    3)
        ALPHA=0.0
        GAMMA=0.02
        ;;
    4)
        ALPHA=0.0
        GAMMA=0.05
        ;;
    5)
        ALPHA=0.001
        GAMMA=0.0
        ;;
    6)
        ALPHA=0.001
        GAMMA=0.01
        ;;
    7)
        ALPHA=0.001
        GAMMA=0.02
        ;;
    8)
        ALPHA=0.001
        GAMMA=0.05
        ;;
esac

echo "=========================================="
echo "CVaR Case: alpha=$ALPHA, gamma=$GAMMA"
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
    --gamma_cvar $GAMMA \
    --cvar_soft \
    --niterations 20 \
    --inj_guess 0.05 \
    --inj_start 0.0001 \
    --save_plots \
    --plot_stride 5 \
    --save_states \
    --save_every 1

echo "=========================================="
echo "Completed: CVaR alpha=$ALPHA, gamma=$GAMMA"
echo "=========================================="

