#!/bin/bash
#SBATCH --job-name=optim_injr_DT
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-2
#SBATCH --output=logs/output_DT_step2_t4_f2_%a.txt
#SBATCH --error=logs/error_DT_step2_t4_f2_%a.txt
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

module load julia/1.10.1
module load anaconda3   # 建议保留；若确定上面固定的 Python 已含 cmasher，可去掉

export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1

mkdir -p logs

task_id=${SLURM_ARRAY_TASK_ID:-1}

# ===== 选 1 个 RISK_ARGS =====

# A) CVaR 零容忍（硬约束）—更稳健：
# RISK_ARGS="--use_cvar --cvar_as_constraint --alpha 0.05 --gamma_cvar 0.0 --lambda_cvar 0.0 --weight_mode uniform --risk_mode relative --kappa_cvar 50 --cvar_soft"

# B) CVaR 小容忍（硬约束，尾部2%平均严重度 ≤ 1e-3）：
# RISK_ARGS="--use_cvar --cvar_as_constraint --alpha 0.02 --gamma_cvar 1e-3 --lambda_cvar 0.0 --weight_mode uniform --risk_mode relative --kappa_cvar 50 --cvar_soft"

# C) POF 零容忍（硬约束）—严格控制超压点：
# RISK_ARGS="--use_pof --pof_as_constraint --eps_pof 0.0 --lambda_pof 0.0 --weight_mode uniform --risk_mode relative --kappa_pof 50"

# D) POF 小容忍（硬约束，≤1% 单元允许超压）：
# RISK_ARGS="--use_pof --pof_as_constraint --eps_pof 0.01 --lambda_pof 0.0 --weight_mode uniform --risk_mode relative --kappa_pof 50"

# << 在这一行选用一个 >>
RISK_ARGS="--use_cvar --cvar_as_constraint --alpha 0.05 --gamma_cvar 0.0 --lambda_cvar 0.0 --weight_mode uniform --risk_mode relative --kappa_cvar 50 --cvar_soft"

COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

julia --project -t 1 src/optim_inject.jl --idx_num "$task_id" $RISK_ARGS $COMMON_ARGS
