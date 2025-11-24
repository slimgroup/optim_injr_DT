#!/bin/bash
#SBATCH --job-name=optim_injr_DT_cvar_zero
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G                 # 用总内存请求，避免 per-cpu 限制；不够再升到 96G/128G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1             # 数组并发=1，避免同节点抢内存
#SBATCH --output=logs/output_DT_step1_t4_f2_%x_%a.txt
#SBATCH --error=logs/error_DT_step1_t4_f2_%x_%a.txt
#SBATCH --signal=TERM@60          # 被杀前 60s 发信号，便于保存中间结果
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

set -euo pipefail

module purge
module load julia/1.10.1

# —— 固定 depot 与 Python，杜绝每次重建 PyCall/Conda ——
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0   # 禁止自动大规模预编译

# 无显示端绘图 + 禁止隐式多线程（和 -t 1 配合）
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1

mkdir -p logs
task_id=${SLURM_ARRAY_TASK_ID:-1}

# ========== 按 job name 自动选择场景 ==========
case "$SLURM_JOB_NAME" in
  *cvar_zero*)
    RISK_ARGS="--use_cvar --cvar_as_constraint \
               --alpha 0.05 --gamma_cvar 0.0 \
               --lambda_cvar 3.0e9 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50 --cvar_soft"
    ;;
  *cvar_eps*)
    # 改成：硬+软，但 α 拉大到 0.25，关注更厚的尾部
    RISK_ARGS="--use_cvar --cvar_as_constraint --cvar_soft \
               --alpha 0.25 --gamma_cvar 1e-3 \
               --lambda_cvar 3.0e9 \
               --weight_mode uniform --risk_mode relative \
               --kappa_cvar 50"
    ;;
  *pof_zero*)
    RISK_ARGS="--use_pof --pof_as_constraint \
               --eps_pof 0.0 \
               --lambda_pof 8.5e8 \
               --tau_pof 0.05 --kappa_pof 50 \
               --weight_mode uniform --risk_mode relative"
    ;;
  *pof_eps*)
    # 已是：硬+软，允许 1% 网格越压（保持不变）
    RISK_ARGS="--use_pof --pof_as_constraint \
               --eps_pof 0.01 \
               --lambda_pof 8.5e8 \
               --tau_pof 0.05 --kappa_pof 50 \
               --weight_mode uniform --risk_mode relative"
    ;;
  *pof_soft*)
    RISK_ARGS="--use_pof \
               --lambda_pof 8.5e8 --eps_pof 0.0 --tau_pof 0.05 \
               --risk_mode relative --weight_mode uniform --kappa_pof 50"
    ;;

  *cvar_soft*)
    RISK_ARGS="--use_cvar --cvar_soft \
               --lambda_cvar 3.0e9 \
               --alpha 0.2 --gamma_cvar 1e-3 \
               --risk_mode relative --weight_mode uniform --kappa_cvar 50"
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

# λ 建议（仅打印，不改 λ）
TUNING_HINTS="--target_share 0.01 --delta_ref 0.01"

# 建议先把频繁 I/O 的绘图收敛一点；OOM/超时再调小或先关掉
COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

# —— 运行 ——
julia --project -t 1 src/optim_inject.jl \
  --idx_num "$task_id" \
  $RISK_ARGS $TUNING_HINTS $COMMON_ARGS
