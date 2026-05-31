#!/usr/bin/env bash
# 运行检查7个cases的injection rate脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
JULIA_SCRIPT="${ROOT_DIR}/scripts/julia_scripts/utilities/check_7cases_inj_rate.jl"

cd "${ROOT_DIR}"

# 尝试找到julia
if command -v julia &> /dev/null; then
    julia "${JULIA_SCRIPT}"
else
    echo "错误: 找不到julia命令"
    echo "请确保julia在PATH中，或者使用sbatch提交作业"
    exit 1
fi

