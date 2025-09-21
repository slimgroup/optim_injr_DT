#!/bin/bash
#SBATCH --job-name=optim_injr_DT
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1          # 单进程
#SBATCH --cpus-per-task=1            # 每进程1 CPU（和 -t 1 对齐）
#SBATCH --mem-per-cpu=4G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-2                 # << 如需数组任务，设定范围；不需要就删掉本行
#SBATCH --output=logs/output_DT_step2_t4_f2_%a.txt
#SBATCH --error=logs/error_DT_step2_t4_f2_%a.txt
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

module load julia/1.10.1

# 确保日志目录存在
mkdir -p logs

# 如果不是数组作业，给 idx 一个默认值 1
task_id=${SLURM_ARRAY_TASK_ID:-1}

# ===== 在这里选用你要的“风险模式参数” =====
# 示例1：零超压（只有 CVaR，硬约束）
# RISK_ARGS="--use_cvar --cvar_as_constraint --alpha 0.05 --gamma_cvar 0.0 --lambda_cvar 0.0 --weight_mode uniform --risk_mode relative --kappa_cvar 50 --cvar_soft"

# 示例2：零超压（只有 POF，硬约束）
# RISK_ARGS="--use_pof --pof_as_constraint --eps_pof 0.0 --lambda_pof 0.0 --weight_mode uniform --risk_mode relative --kappa_pof 50"

# 示例3：允许极小容忍度（只有 CVaR，硬约束，尾部2%平均严重度≤1e-3）
RISK_ARGS="--use_cvar --cvar_as_constraint --alpha 0.02 --gamma_cvar 1e-3 --lambda_cvar 0.0 --weight_mode uniform --risk_mode relative --kappa_cvar 50 --cvar_soft"

# 示例4：允许1%超压（只有 POF，硬约束）
# RISK_ARGS="--use_pof --pof_as_constraint --eps_pof 0.01 --lambda_pof 0.0 --weight_mode uniform --risk_mode relative --kappa_pof 50"

# 选一个打开展示（这里给一个默认：CVaR零超压）
RISK_ARGS="--use_cvar --cvar_as_constraint --alpha 0.05 --gamma_cvar 0.0 --lambda_cvar 0.0 --weight_mode uniform --risk_mode relative --kappa_cvar 50 --cvar_soft"

# 通用运行选项
COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

# 运行
julia --project -t 1 src/optim_inject.jl --idx_num "$task_id" $RISK_ARGS $COMMON_ARGS
