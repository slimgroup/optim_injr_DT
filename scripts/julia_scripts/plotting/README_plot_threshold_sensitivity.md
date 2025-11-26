# Threshold Sensitivity Plotting Guide

## 概述

`plot_threshold_sensitivity.jl` 用于从已完成的阈值敏感度分析结果中生成图表。

## 使用方法

### 基本用法（使用默认路径）

```bash
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl
```

默认会：
- 使用 sample index = 128
- 从 `data/DT_control/exp_name=step1/threshold_sensitivity/summary__sample=128.jld2` 读取结果
- 保存图表到 `plots/DT_control/exp_name=step1/threshold_sensitivity/`

### 指定 sample index

```bash
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl --idx_num 128
```

### 指定自定义 summary 文件路径

```bash
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl \
  --summary_path /path/to/your/summary__sample=128.jld2
```

### 指定输出目录

```bash
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl \
  --output_dir /path/to/output/plots
```

## 生成的图表

脚本会生成以下 6 个图表：

1. **inj_rate_vs_threshold__sample=*.png**
   - 最优注入率 vs 压力阈值

2. **objective_vs_threshold__sample=*.png**
   - 目标函数值 vs 压力阈值（包含总目标、基础目标、惩罚项）

3. **pof_vs_threshold__sample=*.png**
   - 失效概率 (POF) vs 压力阈值（包含平滑和硬约束版本）
   - 如果启用了 POF，会显示 eps 参考线

4. **cvar_vs_threshold__sample=*.png**
   - CVaR vs 压力阈值
   - 如果启用了 CVaR，会显示 gamma 参考线

5. **sensitivity_summary__sample=*.png**
   - 2x2 组合视图，包含所有关键指标

6. **risk_metrics_vs_threshold__sample=*.png**
   - POF 和 CVaR 的双 y 轴对比图

## 在 PACE 上运行

如果结果文件在 PACE 上，可以：

1. **直接在 PACE 上运行绘图**（如果安装了 PyPlot）：
   ```bash
   module load julia/1.11.3
   julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl --idx_num 128
   ```

2. **或者下载结果文件到本地再绘图**：
   ```bash
   # 在本地
   scp user@pace.gatech.edu:/path/to/summary__sample=128.jld2 ./
   julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl \
     --summary_path ./summary__sample=128.jld2
   ```

## 注意事项

- 确保 summary 文件存在且格式正确
- 如果某些阈值的数据缺失（NaN），绘图时会自动跳过
- 图表会显示风险参数的参考线（eps, gamma），如果它们在结果文件中可用

