# Gamma Table 重新生成指南

## 为什么需要重新生成？

如果你之前生成的 gamma table 使用的是**旧方法**（固定注入率单次模拟），那么：

1. **准确性不足**：Gamma 值可能不对应 "当 POF = eps 时，CVaR = gamma"
2. **改进的方法**：现在使用二分搜索找到使 POF ≈ eps 的注入率，更准确

## 如何检查现有 Gamma Table

**在 PACE 上运行**（需要 salloc 和设置环境）：

```bash
salloc -N1 -t 30 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

julia --project=. scripts/julia_scripts/utilities/check_gamma_table.jl \
  scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2
```

这会显示：
- Gamma table 的元数据
- 每个 (eps, threshold) 对的 POF 和 CVaR 值
- POF 与目标 eps 的误差（如果误差 > 5%，建议重新生成）

**注意**：脚本会自动检测 PACE 环境并设置 `JULIA_DEPOT_PATH`，但仍需要手动加载 Julia 模块。

## 重新生成 Gamma Table（使用改进方法）

### 方法 1: 交互式运行（推荐，可以看到进度）

```bash
salloc -N1 -t 120 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

julia --project=. src/threshold_sensitivity.jl \
  --idx_num 128 \
  --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
  --gamma_table_generate auto \
  --gamma_table_eps_list 0.01
```

### 方法 2: 提交 SLURM 作业

创建一个简单的提交脚本：

```bash
#!/bin/bash
#SBATCH --job-name=gamma_table_gen
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 4:00:00
#SBATCH -q inferno
#SBATCH --output=logs/gamma_table_gen_%j.txt
#SBATCH --error=logs/gamma_table_gen_%j.txt

module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

cd "$SLURM_SUBMIT_DIR"

julia --project=. -t 1 src/threshold_sensitivity.jl \
  --idx_num 128 \
  --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
  --gamma_table_generate auto \
  --gamma_table_eps_list 0.01
```

然后运行：
```bash
sbatch scripts/shell/submit_gamma_table_generation.sh
```

## 改进方法的优势

### 旧方法（已废弃）
- 使用固定注入率（如 0.05）运行一次模拟
- POF 可能远大于 eps_target（如 0.26 vs 0.01）
- Gamma 值不准确

### 新方法（当前）
- 使用**二分搜索**找到使 POF ≈ eps_target 的注入率
- 读取此时的 CVaR 作为 gamma
- **确保对应关系**：当 POF = eps 时，CVaR = gamma

## 生成时间

- **旧方法**：每个 (threshold, eps) 对约 1-2 分钟
- **新方法**：每个 (threshold, eps) 对约 3-5 分钟（需要多次模拟进行二分搜索）

对于 5 个阈值 × 1 个 eps = **约 15-25 分钟**

## 验证新生成的 Table

生成后，检查准确性（在 PACE 上）：

```bash
salloc -N1 -t 30 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

julia --project=. scripts/julia_scripts/utilities/check_gamma_table.jl \
  data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2
```

应该看到所有条目都标记为 ✓（POF 误差 < 5%）

## 使用新生成的 Table

```bash
export GAMMA_TABLE_PATH=data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2
export EPS_POF=0.01
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

