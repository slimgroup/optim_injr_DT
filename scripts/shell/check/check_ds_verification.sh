#!/bin/bash
# 检查 ds 验证测试状态和结果（从任意目录运行：会 cd 到仓库根目录）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT_DIR}" || exit 1

# 自动查找最新的 ds_verification job
JOB_ID=$(squeue -u $USER -o "%.10i %.20j" 2>/dev/null | grep "ds_verification" | awk '{print $1}' | head -1)

# 如果没有运行中的任务，查找最新的输出文件
if [ -z "${JOB_ID}" ]; then
    LATEST_OUTPUT=$(ls -t logs/utilities/ds_verification_*.out logs/ds_verification_*.out 2>/dev/null | head -1)
    if [ -n "${LATEST_OUTPUT}" ]; then
        JOB_ID=$(echo "${LATEST_OUTPUT}" | sed 's/.*ds_verification_\([0-9]*\)\.out/\1/')
    else
        JOB_ID="3142377"  # 最新的 job ID
    fi
fi

echo "=== ds 验证测试状态 ==="
echo ""

# 检查任务状态
echo "1. 任务状态:"
squeue -j ${JOB_ID} -o "%.10i %.12P %.20j %.8u %.2t %.10M %.6D %R" 2>/dev/null || echo "  任务已完成或不在队列中"
echo ""

# 检查输出文件
echo "2. 输出文件:"
OUTPUT_FILE=$(ls -t logs/utilities/ds_verification_${JOB_ID}.out logs/ds_verification_${JOB_ID}.out 2>/dev/null | head -1)
ERROR_FILE=$(ls -t logs/utilities/ds_verification_${JOB_ID}.err logs/ds_verification_${JOB_ID}.err 2>/dev/null | head -1)

if [ -f "${OUTPUT_FILE}" ]; then
    echo "  输出文件: ${OUTPUT_FILE}"
    echo "  文件大小: $(wc -l < ${OUTPUT_FILE}) 行"
    echo ""
    echo "  最后 50 行输出:"
    echo "  ----------------------------------------"
    tail -50 "${OUTPUT_FILE}" 2>/dev/null
    echo "  ----------------------------------------"
else
    echo "  输出文件尚未创建（任务可能还在排队或启动中）"
fi

if [ -f "${ERROR_FILE}" ]; then
    echo ""
    echo "3. 错误文件:"
    echo "  ${ERROR_FILE}"
    if [ -s "${ERROR_FILE}" ]; then
        echo "  错误内容:"
        cat "${ERROR_FILE}"
    else
        echo "  （无错误）"
    fi
fi

echo ""
echo "4. 实时查看输出:"
echo "  tail -f logs/ds_verification_${JOB_ID}.out"
echo ""
echo "5. 查看完整结果:"
echo "  cat logs/ds_verification_${JOB_ID}.out"

