# PACE 提交指南

## 快速运行（推荐）

```bash
# 提交快速运行作业（5 个阈值，10 次迭代，预计 1-3 小时）
sbatch scripts/shell/submit/submit_threshold_sensitivity.sh
```

## 完整运行

```bash
# 提交完整运行作业（10 个阈值，20 次迭代，预计 10-20 小时）
sbatch scripts/shell/submit/submit_threshold_sensitivity_full.sh
```

## 检查作业状态

```bash
# 查看作业队列
squeue -u $USER

# 查看作业详情
scontrol show job <JOB_ID>

# 查看实时输出
tail -f logs/threshold_sensitivity_<JOB_ID>.out

# 查看错误日志
tail -f logs/threshold_sensitivity_<JOB_ID>.err
```

## 检查进度（在另一个终端）

```bash
# 检查进度
julia scripts/julia_scripts/utilities/check_progress.jl 128
```

## 取消作业

```bash
# 取消作业
scancel <JOB_ID>

# 取消所有相关作业
scancel -n thresh_sens_128
```

## 修改参数

如果需要修改参数（如 `idx_num`、`threshold_num` 等），编辑对应的脚本文件：

- 快速运行：`scripts/shell/submit/submit_threshold_sensitivity.sh`
- 完整运行：`scripts/shell/submit/submit_threshold_sensitivity_full.sh`

## 资源说明

- **CPU**: 8 核
- **内存**: 32GB
- **时间限制**: 
  - 快速模式：12 小时
  - 完整模式：24 小时
- **分区**: inferno
- **账户**: gts-fherrmann9

## 输出文件

运行完成后，结果保存在：
- `data/DT_control/exp_name=step1/threshold_sensitivity/summary__sample=128.jld2`
- `data/DT_control/exp_name=step1/threshold_sensitivity/risk_params__sample=128.jld2`
- `plots/DT_control/exp_name=step1/threshold_sensitivity/` (如果启用绘图)

日志文件：
- `logs/threshold_sensitivity_<JOB_ID>.out` - 标准输出
- `logs/threshold_sensitivity_<JOB_ID>.err` - 错误输出

