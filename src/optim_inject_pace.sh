#!/bin/bash
#SBATCH --job-name=DT_case
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --array=1-128
#SBATCH --output=logs/out_%x_%A_%a.txt
#SBATCH --error=logs/err_%x_%A_%a.txt
#SBATCH --signal=TERM@60
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

set -euo pipefail
module purge
module load julia/1.10.1 2>/dev/null || true

# 固定环境（PyCall 稳定、单线程绘图）
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

trap 'echo "[WARN] SIGTERM received; try to save…"' TERM

# -------- 从 submit_all.sh 传入的变量 --------
: "${CASE_TAG:?Missing CASE_TAG}"       # 目录命名与日志识别的标签
: "${RISK_ARGS:?Missing RISK_ARGS}"     # 这一 case 的风险参数组合

# 训练公共参数（你给的最新）
TRAIN_ARGS="--niterations 40 --inj_guess 0.20"

# λ 建议（只打印建议，不改值）
TUNING_HINTS="--target_share 0.01 --delta_ref 0.01"

# 可选：保存频率/前向梯度
COMMON_ARGS="--save_plots --plot_stride 5 --save_every 5 --grad_forward"

# sample id = array id
task_id=${SLURM_ARRAY_TASK_ID}
EXP_NAME="step1"

# 输出到 scratch：exp_name + case + sample
OUT_DIR="/storage/scratch1/6/hli853/data/DT_control/exp_name=${EXP_NAME}/${CASE_TAG}/sample=${task_id}"
mkdir -p "$OUT_DIR"

echo "JOB ${SLURM_JOB_ID}.${SLURM_ARRAY_TASK_ID}"
echo "CASE_TAG=${CASE_TAG}"
echo "OUT_DIR=${OUT_DIR}"
echo "RISK_ARGS=${RISK_ARGS}"

julia --project -t 1 src/optim_inject.jl \
  --idx_num "${task_id}" \
  --output_dir "${OUT_DIR}" \
  ${RISK_ARGS} ${TRAIN_ARGS} ${TUNING_HINTS} ${COMMON_ARGS}
