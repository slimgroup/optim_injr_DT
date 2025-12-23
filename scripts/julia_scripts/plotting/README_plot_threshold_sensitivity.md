# Threshold Sensitivity Plotting Guide

## 概述

简化的threshold sensitivity绘图脚本。现在只需要两个主要脚本：

1. **plot_threshold_sensitivity.jl** - 绘制单个threshold sensitivity分析结果
2. **plot_pof_vs_cvar.jl** - 比较POF-only vs CVaR-only优化结果

## 脚本说明

### 1. plot_threshold_sensitivity.jl

绘制单个threshold sensitivity分析的结果（支持POF-only, CVaR-only, 或POF+CVaR）。

#### 基本用法

```bash
# 使用默认设置（sample=128）
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl

# 指定sample index
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl --idx_num 128

# 指定自定义summary文件路径
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl \
  --summary_path /path/to/summary_POF_CVaR__sample=128.jld2

# 指定输出目录
julia --project=. scripts/julia_scripts/plotting/plot_threshold_sensitivity.jl \
  --output_dir /path/to/output/plots
```

#### 生成的图表

脚本会生成以下6个图表：

1. **inj_rate_vs_threshold__sample=*.png** - 最优注入率 vs 压力阈值
2. **objective_vs_threshold__sample=*.png** - 目标函数值 vs 压力阈值
3. **pof_vs_threshold__sample=*.png** - 失效概率 (POF) vs 压力阈值
4. **cvar_vs_threshold__sample=*.png** - CVaR vs 压力阈值
5. **sensitivity_summary__sample=*.png** - 2x2组合视图
6. **risk_metrics_vs_threshold__sample=*.png** - POF和CVaR的双y轴对比图

### 2. plot_pof_vs_cvar.jl

比较POF-only和CVaR-only优化结果，展示CVaR控制更保守（注入率更低）。

#### 基本用法

```bash
# 使用默认设置（sample=128）
julia --project=. scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl

# 指定sample index
julia --project=. scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl --idx_num 128
```

#### 需要的文件

- `summary__POF__sample=<idx>.jld2` - POF-only优化结果
- `summary__CVaR__sample=<idx>.jld2` - CVaR-only优化结果

#### 生成的图表

1. **inj_vs_threshold__POF_vs_CVaR__sample=*.png** - 注入率对比
2. **risk_utilization__POF_vs_CVaR__sample=*.png** - 风险利用率对比（归一化）
3. **pof_vs_cvar_comparison__sample=*.png** - 2x2综合对比图

## 工具脚本

### check_summary_thresholds.jl

检查summary文件中包含哪些thresholds，用于调试。

```bash
julia --project=. scripts/julia_scripts/plotting/check_summary_thresholds.jl
```

## 在PACE上运行

如果结果文件在PACE上，可以：

1. **直接在PACE上运行绘图**（如果安装了PyPlot）：
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

- 确保summary文件存在且格式正确
- 如果某些阈值的数据缺失（NaN），绘图时会自动跳过
- 图表会显示风险参数的参考线（eps, gamma），如果它们在结果文件中可用
- 对于POF vs CVaR比较，确保两个优化都使用相同的threshold列表

### 3. plot_pof_cvar_comparison_advanced.jl

高级POF vs CVaR比较脚本，提供更深入的分析和可视化。

#### 基本用法

```bash
# 使用默认设置（sample=128）
julia --project=. scripts/julia_scripts/plotting/plot_pof_cvar_comparison_advanced.jl
```

#### 生成的图表

1. **cvar_pof_ratio_sample=*.png** - CVaR/POF比率图（展示CVaR相对POF的保守程度）
2. **relative_change_comparison_sample=*.png** - 相对变化对比（相对于第一个threshold）
3. **normalized_comparison_sample=*.png** - 归一化对比（0-1尺度）
4. **dual_axis_comparison_sample=*.png** - 双Y轴对比（每个指标使用合适的尺度）
5. **inj_rate_comparison_advanced_sample=*.png** - 优化注入率对比（带详细标注）

#### 特点

- 处理POF和CVaR不同单位/尺度的问题
- 提供多种归一化和比较方法
- 自动从合并的summary文件中提取缺失数据

### 4. plot_pof_cvar.py

概念性可视化脚本，用于绘制POF和CVaR关系的示意图。

#### 基本用法

```bash
python scripts/julia_scripts/plotting/plot_pof_cvar.py
```

#### 功能

- 创建概率密度函数图
- 标注POF（exceedance probability）和CVaR（average of worst outcomes）的位置
- 展示两者在分布中的关系
- 生成教学/概念图（`pof_cvar.png`）

**注意**：这是一个概念性可视化脚本，不是数据分析脚本。用于论文或演示中展示POF和CVaR的概念关系。

## 已删除的脚本

以下脚本已被合并或删除，不再需要：

- `plot_threshold_sensitivity_combined.jl` → 功能已合并到`plot_pof_vs_cvar.jl`
- `extract_6mpa_cvar.jl` → 特定用途工具，不再需要
- `fix_missing_6mpa.jl` → 修复工具，不再需要
