# 快速运行指南（启用 POF + CVaR，自动校准）

## 快速运行命令（推荐）

```bash
julia src/threshold_sensitivity.jl \
  --idx_num 128 \
  --use_pof \
  --use_cvar \
  --eps_pof 0.01 \
  --lambda_pof 1.0 \
  --lambda_cvar 1.0 \
  --calibrate_gamma \
  --niterations 10 \
  --grad_forward \
  --threshold_num 5 \
  --threshold_min 2.0 \
  --threshold_max 6.0
```

## 参数说明

### 风险参数（POF + CVaR 对齐）
- `--use_pof`: 启用 POF
- `--use_cvar`: 启用 CVaR
- `--eps_pof 0.01`: POF 阈值（1% 违反概率）
- `--calibrate_gamma`: **自动校准 gamma 以匹配 eps**
- `--lambda_pof 1.0`: POF 惩罚权重
- `--lambda_cvar 1.0`: CVaR 惩罚权重

### 速度优化参数
- `--niterations 10`: 减少迭代次数（默认 20 → 10，**2x 加速**）
- `--grad_forward`: 使用前向差分（**1.5-2x 加速**）
- `--threshold_num 5`: 减少阈值数量（默认可能更多，**3-10x 加速**）

### Threshold 范围
- `--threshold_min 2.0`: 最小阈值（MPa）
- `--threshold_max 6.0`: 最大阈值（MPa）

## 完整参数列表（可选）

如果需要更多控制：

```bash
julia src/threshold_sensitivity.jl \
  --idx_num 128 \
  --use_pof \
  --use_cvar \
  --eps_pof 0.01 \
  --tau_pof 0.05 \
  --lambda_pof 1.0 \
  --lambda_cvar 1.0 \
  --alpha 0.05 \
  --calibrate_gamma \
  --calibration_threshold 4.0 \
  --niterations 10 \
  --grad_forward \
  --threshold_num 5 \
  --threshold_min 2.0 \
  --threshold_max 6.0 \
  --inj_guess 0.05 \
  --inj_start 0.0001
```

## 速度对比

| 配置 | 预计时间 | 速度提升 |
|------|---------|---------|
| 默认（20 iter, central, 10 thresholds） | 10-20 小时 | 1x |
| **快速（10 iter, forward, 5 thresholds）** | **1-3 小时** | **6-12x** |
| 超快（5 iter, forward, 3 thresholds） | 0.5-1 小时 | 15-30x |

## 校准说明

使用 `--calibrate_gamma` 时：
1. 程序会在第一个阈值（或 `--calibration_threshold` 指定的阈值）运行一次前向模拟
2. 根据给定的 `eps_pof`，自动计算对应的 `gamma_cvar`
3. 确保 POF 和 CVaR 阈值对齐
4. 打印并保存校准后的 `(eps, gamma)` 值

## 检查进度

在另一个终端运行：
```bash
julia scripts/check_progress.jl 128
```

## 结果文件

运行完成后，结果保存在：
- `data/DT_control/exp_name=step1/threshold_sensitivity/summary__sample=128.jld2`
- `data/DT_control/exp_name=step1/threshold_sensitivity/risk_params__sample=128.jld2`
- `plots/DT_control/exp_name=step1/threshold_sensitivity/` (如果启用绘图)

