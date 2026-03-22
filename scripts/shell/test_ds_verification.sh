#!/usr/bin/env bash
# SBATCH script to verify ds parameter performance

#SBATCH --job-name=ds_verification
#SBATCH --output=logs/ds_verification_%j.out
#SBATCH --error=logs/ds_verification_%j.err
#SBATCH --time=00:30:00
#SBATCH --mem=8G
#SBATCH --partition=cpu-short
#SBATCH --account=gts-fherrmann9

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment (使用已存在的 julia-depot 避免重复编译)
export JULIA_DEPOT_PATH="$HOME/julia-depot"
# 确保 julia-depot 目录存在
if [ ! -d "$JULIA_DEPOT_PATH" ]; then
    mkdir -p "$JULIA_DEPOT_PATH"
fi
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
# 允许自动预编译（如果包已存在，会使用预编译版本）
export JULIA_PKG_PRECOMPILE_AUTO=1
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1

# Get project root (same logic as optim_inject_pace.sh)
if [ -n "${SLURM_SUBMIT_DIR:-}" ]; then
    # If SLURM_SUBMIT_DIR is set and points to scripts/, go up one level
    if [ -f "${SLURM_SUBMIT_DIR}/test/test_ds_minimal.jl" ]; then
        ROOT_DIR="${SLURM_SUBMIT_DIR}"
    elif [ -f "${SLURM_SUBMIT_DIR}/../test/test_ds_minimal.jl" ]; then
        ROOT_DIR="$(cd "${SLURM_SUBMIT_DIR}/.." && pwd)"
    else
        # Fallback: assume project root
        ROOT_DIR="$(cd "${SLURM_SUBMIT_DIR}" && pwd)"
    fi
else
    # Fallback: use script location
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

# Ensure logs directory exists
LOGS_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOGS_DIR}" 2>/dev/null || true

# Change to project root directory (critical!)
cd "${ROOT_DIR}" || { echo "ERROR: Cannot cd to ${ROOT_DIR}"; exit 1; }

echo "=========================================="
echo "ds 参数验证测试"
echo "=========================================="
echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "Start time: $(date)"
echo "Current directory: $(pwd)"
echo "ROOT_DIR: ${ROOT_DIR}"
echo "Test file exists: $([ -f test/test_ds_minimal.jl ] && echo 'YES' || echo 'NO')"
echo ""

# Run the verification test (use minimal version to avoid PyCall compilation)
julia --project="${ROOT_DIR}" -t 1 "${ROOT_DIR}/test/test_ds_minimal.jl"

echo ""
echo "=========================================="
echo "完成时间: $(date)"
echo "=========================================="

