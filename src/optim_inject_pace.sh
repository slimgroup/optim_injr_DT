#!/bin/bash
#SBATCH --job-name=optim_injr_DT_cvar_zero
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=24G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-2
#SBATCH --output=logs/output_DT_step1_t4_f2_%x_%a.txt
#SBATCH --error=logs/error_DT_step1_t4_f2_%x_%a.txt
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

module load julia/1.10.1

# 无显示端绘图 + 禁止隐式多线程（和 -t 1 配合）
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1

mkdir -p logs
task_id=${SLURM_ARRAY_TASK_ID:-1}

# ========== 按 job name 自动选择场景 ==========
# 关键字：
#   *_cvar_zero : CVaR 硬约束，零容忍（gamma=0）
#   *_cvar_eps  : CVaR 硬约束，小容忍（gamma>0）
#   *_pof_zero  : POF  硬约束，零容忍（eps=0）
#   *_pof_eps   : POF  硬约束，小容忍（eps>0）
#
# 说明：
# - 软罚项已打开（λ>0），同时仍以硬约束判定可行性（不满足直接 Inf）。
# - λ 的量级给了常用起点：CVaR ~ 3e9，POF ~ 8.5e8。
#   运行时你的程序会打印 λ 建议（基于 target_share / delta_ref），
#   如需调节可据此微调。

case "$SLURM_JOB_NAME" in
  *cvar_zero*)
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.05 --gamma_cvar 0.0 \
               --lambda_cvar 3.0e9 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;

  *cvar_eps*)
    # 允许 2% 尾部平均超压 ≤ 1e-3
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.02 --gamma_cvar 1e-3 \
               --lambda_cvar 3.0e9 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;

  *pof_zero*)
    RISK_ARGS="--use_pof --pof_as_constraint \
               --eps_pof 0.0 \
               --lambda_pof 8.5e8 \
               --tau_pof 0.05 --kappa_pof 50 \
               --weight_mode uniform --risk_mode relative"
    ;;

  *pof_eps*)
    # 允许 ≤1% 网格点超压
    RISK_ARGS="--use_pof --pof_as_constraint \
               --eps_pof 0.01 \
               --lambda_pof 8.5e8 \
               --tau_pof 0.05 --kappa_pof 50 \
               --weight_mode uniform --risk_mode relative"
    ;;

  *)
    echo "[INFO] 未识别的 job name，默认用 CVaR 零容忍。"
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.05 --gamma_cvar 0.0 \
               --lambda_cvar 3.0e9 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;
esac

# 可选：让程序打印 λ 建议值，便于后续微调（不会改变 λ，只是打印）
TUNING_HINTS="--target_share 0.01 --delta_ref 0.01"

COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

julia --project -t 1 src/optim_inject.jl \
  --idx_num "$task_id" \
  $RISK_ARGS $TUNING_HINTS $COMMON_ARGS
