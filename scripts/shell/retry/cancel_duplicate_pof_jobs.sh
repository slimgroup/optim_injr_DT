#!/usr/bin/env bash
# Cancel duplicate POF jobs:
# 1. Jobs that have already completed (have final.jld2)
# 2. Jobs with duplicate jobnames in queue

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

echo "=== 检查并取消重复的POF任务 ==="
echo ""

# Find completed jobs that are still running
echo "1. 检查已完成但仍运行的任务..."
COMPLETED_JOBS=$(squeue -u $USER -o "%.18i %.50j" 2>/dev/null | grep "DT_POF" | while read line; do
  JOBID=$(echo "$line" | awk '{print $1}')
  JOBNAME=$(echo "$line" | awk '{print $2}')
  
  # Extract TAG and SAMPLE from job name
  TAG=$(echo "$JOBNAME" | sed 's/_s[0-9]*$//')
  SAMPLE=$(echo "$JOBNAME" | grep -oE "s[0-9]+" | sed 's/s//')
  
  # Extract eps from TAG
  EPS=$(echo "$TAG" | grep -oE "eps=[0-9.]+" | cut -d= -f2)
  
  # Build case directory name
  CASE_DIR="POF__HARD__eps=${EPS}__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
  
  # Check if final.jld2 exists
  FINAL_FILE="${ROOT_DIR}/data/DT_control/exp_name=step1/${CASE_DIR}/sample=${SAMPLE}/final.jld2"
  
  if [ -f "$FINAL_FILE" ]; then
    echo "${JOBID}|${JOBNAME}|completed"
  fi
done)

COMPLETED_COUNT=$(echo "$COMPLETED_JOBS" | grep -v "^$" | wc -l)

# Find duplicate jobnames in queue
echo "2. 检查队列中重复的任务名称..."
DUPLICATE_JOBS=$(squeue -u $USER -o "%.18i %.50j" 2>/dev/null | grep "DT_POF" | \
  awk '{print $2}' | sort | uniq -d | while read jobname; do
  # Get all job IDs with this name, keep only the first one
  squeue -u $USER -o "%.18i %.50j" 2>/dev/null | grep "DT_POF" | \
    awk -v name="$jobname" '$2 == name {print $1 "|" $2 "|duplicate"}' | tail -n +2
done)

DUPLICATE_COUNT=$(echo "$DUPLICATE_JOBS" | grep -v "^$" | wc -l)

TOTAL_COUNT=$((COMPLETED_COUNT + DUPLICATE_COUNT))

if [ "$TOTAL_COUNT" -eq 0 ]; then
  echo "✓ 没有发现需要取消的任务"
  exit 0
fi

echo ""
echo "发现需要取消的任务:"
echo "  - 已完成但仍运行: $COMPLETED_COUNT 个"
echo "  - 队列中重复: $DUPLICATE_COUNT 个"
echo "  - 总计: $TOTAL_COUNT 个"
echo ""

if [ "$COMPLETED_COUNT" -gt 0 ]; then
  echo "已完成但仍运行的任务:"
  echo "$COMPLETED_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    echo "  - $JOBID: $JOBNAME ($REASON)"
  done
  echo ""
fi

if [ "$DUPLICATE_COUNT" -gt 0 ]; then
  echo "队列中重复的任务（保留第一个，取消其余的）:"
  echo "$DUPLICATE_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    echo "  - $JOBID: $JOBNAME ($REASON)"
  done
  echo ""
fi

# Ask for confirmation
read -p "是否取消这些任务? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "已取消操作"
  exit 0
fi

# Cancel jobs
echo ""
echo "正在取消任务..."
CANCELED=0

# Cancel completed jobs
if [ "$COMPLETED_COUNT" -gt 0 ]; then
  echo "$COMPLETED_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    if [ -n "$JOBID" ] && [ -n "$JOBNAME" ]; then
      if scancel "$JOBID" 2>/dev/null; then
        echo "  ✓ 已取消: $JOBID ($JOBNAME) - $REASON"
        CANCELED=$((CANCELED + 1))
      else
        echo "  ✗ 取消失败: $JOBID ($JOBNAME)"
      fi
    fi
  done
fi

# Cancel duplicate jobs
if [ "$DUPLICATE_COUNT" -gt 0 ]; then
  echo "$DUPLICATE_JOBS" | grep -v "^$" | while IFS='|' read -r JOBID JOBNAME REASON; do
    if [ -n "$JOBID" ] && [ -n "$JOBNAME" ]; then
      if scancel "$JOBID" 2>/dev/null; then
        echo "  ✓ 已取消: $JOBID ($JOBNAME) - $REASON"
        CANCELED=$((CANCELED + 1))
      else
        echo "  ✗ 取消失败: $JOBID ($JOBNAME)"
      fi
    fi
  done
fi

echo ""
echo "完成！已取消任务"

