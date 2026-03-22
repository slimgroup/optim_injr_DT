#!/bin/bash
# 检查测试状态（从任意目录运行：会 cd 到仓库根目录）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}" || exit 1

echo "=== 检查 ds 测试任务状态 ==="
echo ""

# 检查运行中的任务
echo "运行中的任务:"
squeue -u $USER -o "%.10i %.12P %.20j %.8u %.2t %.10M %.6D %R" 2>/dev/null

echo ""
echo "最近的任务输出文件 (logs/):"
ls -lt logs/*.out logs/*.err 2>/dev/null | head -5

echo ""
echo "如果任务已完成，可以查看输出:"
echo "  tail -f logs/ds_verification_<jobid>.out"
echo ""
echo "或者重新运行查看结果:"
echo "  srun --partition=interactive-cpu --time=00:30:00 --mem=8G --cpus-per-task=2 --pty bash -c 'module load julia/1.11.3 && cd \"${ROOT_DIR}\" && julia test/test_ds_minimal.jl'"

