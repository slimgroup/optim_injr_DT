#!/bin/bash
# 检查 ds 验证测试状态

echo "=== ds 验证测试状态检查 ==="
echo ""

# 检查运行中的任务
echo "1. 运行中的任务:"
squeue -u $USER -o "%.10i %.12P %.20j %.8u %.2t %.10M %.6D %R" 2>/dev/null | head -5

echo ""
echo "2. 输出文件状态:"
if [ -f ds_verification_output.txt ]; then
    echo "  文件存在，大小: $(wc -l < ds_verification_output.txt) 行"
    echo ""
    echo "  最后 30 行输出:"
    echo "  ----------------------------------------"
    tail -30 ds_verification_output.txt 2>/dev/null
    echo "  ----------------------------------------"
else
    echo "  输出文件尚未创建"
fi

echo ""
echo "3. 如果任务已完成，查看完整结果:"
echo "  cat ds_verification_output.txt"

echo ""
echo "4. 如果任务还在运行，实时查看:"
echo "  tail -f ds_verification_output.txt"

