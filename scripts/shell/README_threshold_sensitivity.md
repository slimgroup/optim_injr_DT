# Threshold Sensitivity Scripts

## Overview

简化的threshold sensitivity分析脚本。现在只需要两个主要脚本：

1. **submit_gamma_table_generation.sh** - 生成gamma查找表
2. **submit_threshold_sensitivity.sh** - 运行threshold sensitivity分析

## Quick Start

### 1. 生成Gamma Table（可选，仅当使用CVaR时需要）

```bash
# 默认设置（eps=0.01, 5个thresholds: 2.0-6.0）
sbatch scripts/shell/submit_gamma_table_generation.sh

# 自定义设置
export EPS_LIST=0.005,0.01,0.02
export THRESHOLD_MIN=2.0
export THRESHOLD_MAX=6.0
export THRESHOLD_NUM=10
sbatch scripts/shell/submit_gamma_table_generation.sh
```

### 2. 运行Threshold Sensitivity分析

```bash
# 基础运行（POF+CVaR，使用默认gamma table）
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity.sh

# POF-only模式
export USE_POF=1 USE_CVAR=0
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity.sh

# CVaR-only模式（需要gamma table）
export USE_POF=0 USE_CVAR=1 GAMMA_TABLE_PATH=path/to/gamma_table.jld2
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity.sh

# 自定义thresholds和iterations
export THRESHOLD_VALUES=2.0,3.0,4.0 NITERATIONS=20
sbatch --array=1-3 scripts/shell/submit_threshold_sensitivity.sh
```

## 环境变量配置

### submit_threshold_sensitivity.sh

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `IDX_NUM` | 128 | 样本索引 |
| `USE_POF` | 1 | 是否启用POF |
| `USE_CVAR` | 1 | 是否启用CVaR |
| `EPS_POF` | 0.01 | POF阈值 |
| `LAMBDA_POF` | 1.0 | POF权重 |
| `LAMBDA_CVAR` | 1.0 | CVaR权重 |
| `NITERATIONS` | 10 | 优化迭代次数 |
| `THRESHOLD_MIN` | 2.0 | 最小threshold (MPa) |
| `THRESHOLD_MAX` | 6.0 | 最大threshold (MPa) |
| `THRESHOLD_NUM` | 5 | Threshold数量 |
| `THRESHOLD_VALUES` | 自动生成 | 逗号分隔的threshold列表（覆盖min/max/num） |
| `GAMMA_TABLE_PATH` | 自动查找 | Gamma table路径（CVaR模式需要） |

### submit_gamma_table_generation.sh

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `IDX_NUM` | 128 | 样本索引 |
| `EPS_LIST` | 0.01 | 逗号分隔的eps值列表 |
| `THRESHOLD_MIN` | 2.0 | 最小threshold (MPa) |
| `THRESHOLD_MAX` | 6.0 | 最大threshold (MPa) |
| `THRESHOLD_NUM` | 5 | Threshold数量 |

## 输出文件

- **Gamma Table**: `data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=<IDX>__<timestamp>.jld2`
- **Summary**: `data/DT_control/exp_name=step1/threshold_sensitivity/summary_<RISK_LABEL>__sample=<IDX>.jld2`
- **Plots**: `plots/DT_control/exp_name=step1/threshold_sensitivity/`

## 注意事项

1. **CVaR模式需要gamma table**：如果启用CVaR但没有指定`GAMMA_TABLE_PATH`，脚本会自动查找最新的gamma table文件
2. **Array jobs**：使用`--array=1-N`来并行运行多个thresholds
3. **结果合并**：使用array jobs时，结果会自动合并到同一个summary文件

## 已删除的脚本

以下脚本已被合并到通用脚本中，不再需要：

- `submit_threshold_sensitivity_full.sh` → 使用`NITERATIONS=20 THRESHOLD_NUM=10`
- `submit_threshold_sensitivity_pof_only.sh` → 使用`USE_POF=1 USE_CVAR=0`
- `submit_threshold_sensitivity_cvar_only.sh` → 使用`USE_POF=0 USE_CVAR=1`
- `submit_threshold_sensitivity_separate.sh` → 使用array jobs分别运行
- `submit_gamma_table_generation_array.sh` → 使用标准版本即可
- `run_threshold_sensitivity_after_gamma.sh` → 直接运行`submit_threshold_sensitivity.sh`
- `run_quick_sensitivity.sh` → 本地运行可直接调用Julia脚本

