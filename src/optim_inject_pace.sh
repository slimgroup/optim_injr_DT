#!/bin/bash
#SBATCH --job-name=optim_injr_DT_cvar_zero          # ← 用 job name 选择场景（见下方提交示例）
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-2
#SBATCH --output=logs/output_DT_step1_t4_f2_%x_%a.txt
#SBATCH --error=logs/error_DT_step1_t4_f2_%x_%a.txt
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

# --- 软件环境 ---
module load julia/1.10.1

# --- 无显示端绘图、禁止隐式多线程（和 -t 1 配合）---
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1

# 日志目录
mkdir -p logs

# 数组任务索引（非数组作业也可用，默认 1）
task_id=${SLURM_ARRAY_TASK_ID:-1}

# ---------- 场景选择（根据 job name 自动匹配） ----------
# 支持的 job name 包含下列关键字：
#   optim_injr_DT_cvar_zero  : CVaR 硬约束、零容忍 (alpha=0.05, gamma=0.0)
#   optim_injr_DT_cvar_eps   : CVaR 硬约束、小容忍 (alpha=0.02, gamma=1e-3)
#   optim_injr_DT_pof_zero   : POF  硬约束、零容忍 (eps=0.0)
#   optim_injr_DT_pof_eps    : POF  硬约束、小容忍 (eps=0.01)

case "$SLURM_JOB_NAME" in
  *cvar_zero*)
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.05 --gamma_cvar 0.0 --lambda_cvar 0.0 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;
  *cvar_eps*)
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.02 --gamma_cvar 1e-3 --lambda_cvar 0.0 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;
  *pof_zero*)
    RISK_ARGS="--use_pof --pof_as_constraint \
               --eps_pof 0.0 --lambda_pof 0.0 \
               --weight_mode uniform --risk_mode relative \
               --kappa_pof 50"
    ;;
  *pof_eps*)
    RISK_ARGS="--use_pof --pof_as_constraint \
               --eps_pof 0.01 --lambda_pof 0.0 \
               --weight_mode uniform --risk_mode relative \
               --kappa_pof 50"
    ;;
  *)
    echo "[INFO] 未识别的 job name，默认用 CVaR 零容忍。"
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.05 --gamma_cvar 0.0 --lambda_cvar 0.0 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;
esac

# 通用参数
COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

# 运行
julia --project -t 1 src/optim_inject.jl --idx_num "$task_id" $RISK_ARGS $COMMON_ARGS
