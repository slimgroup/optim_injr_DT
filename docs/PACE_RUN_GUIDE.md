# PACE 运行指南：POF vs CVaR 对比实验

本指南说明如何在 PACE 上运行 POF-only 和 CVaR-only 的阈值敏感度分析，并生成对比图。

> **状态说明**
> 本文档里涉及的 gamma-table 生成与复用步骤属于较早期的 POF/CVaR 对比路线。
> 这些内容目前保留用于复现实验历史结果，不应默认视为当前推荐 workflow。

## ✅ EPS 和 Gamma 对应关系（已改进）

**确保 POF-only 和 CVaR-only 使用相同的 `eps_pof` 值！**

- POF-only: 使用 `eps_pof = 0.01`（目标 POF 阈值）
- CVaR-only: 使用 `eps_pof = 0.01`（用于从 gamma table 查找对应的 gamma）

**改进**：Gamma table 生成现在使用**二分搜索**找到使 POF ≈ eps_target 的注入率，然后读取此时的 CVaR 作为 gamma。这确保了更准确的对应关系。

**工作流程**：
1. 生成 gamma table 时，对每个阈值和 eps，找到使 POF ≈ eps 的注入率
2. 读取此时的 CVaR 值作为 gamma
3. 这样 gamma table 中的 gamma 值就是"当 POF = eps 时，CVaR = gamma"的对应关系

详见 `docs/EPS_GAMMA_ALIGNMENT.md`。

## ⚠️ 重要：先检查并重新生成 Gamma Table

根据检查结果，**现有的 gamma table 不准确**（所有条目都有 ⚠️ 标记）。**必须先重新生成**，然后再运行优化。

### 步骤 0: 重新生成 Gamma Table（必须）

```bash
# 提交作业生成（推荐，约 15-25 分钟）
sbatch scripts/shell/submit_gamma_table_generation.sh
```

或者交互式运行：

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

**注意**：
- 新方法使用**二分搜索**，会找到使 POF ≈ eps_target 的注入率，确保对应关系
- 使用**多线程并行处理**，所有阈值同时计算，大幅缩短生成时间（约 3-5 分钟 vs 15-25 分钟）

## 快速开始

### 步骤 1: 运行 POF-only 优化

```bash
# 提交 5 个 array 任务（每个阈值一个）
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh
```

这会生成：`summary__POF__sample=128.jld2`

### 步骤 2: 运行 CVaR-only 优化

```bash
# 确保 gamma table 已生成（如果还没有）
# 然后提交 5 个 array 任务
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

这会生成：`summary__CVaR__sample=128.jld2`

### 步骤 0: 检查现有 Gamma Table（可选）

如果想检查现有 gamma table 的准确性：

```bash
salloc -N1 -t 30 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
julia --project=. scripts/julia_scripts/utilities/check_gamma_table.jl \
  scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2
```

如果看到很多 ⚠️（POF 误差 > 5%），建议重新生成。

### 步骤 3: 生成对比图

等两个作业都完成后，在交互式节点上运行：

```bash
salloc -N1 -t 60 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
julia --project=. scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl --idx_num 128
```

## 详细说明

### 1. POF-only 运行

**脚本**: `scripts/shell/submit_threshold_sensitivity_pof_only.sh`

**默认设置**:
- `eps_pof = 0.01`
- `lambda_pof = 1.0`
- 阈值: 2.0, 3.0, 4.0, 5.0, 6.0 MPa
- 迭代次数: 10

**自定义参数**:
```bash
export EPS_POF=0.005
export LAMBDA_POF=2.0
export THRESHOLD_VALUES=2.0,3.0,4.0,5.0,6.0
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh
```

**输出文件**:
- `data/DT_control/exp_name=step1/threshold_sensitivity/summary__POF__sample=128.jld2`
- 每个阈值的详细结果在各自的子目录中

### 2. CVaR-only 运行

**脚本**: `scripts/shell/submit_threshold_sensitivity_cvar_only.sh`

**默认设置**:
- 使用 gamma table: `scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2`
- `eps_pof = 0.01` (用于 gamma table 查找)
- `lambda_cvar = 1.0`
- 阈值: 2.0, 3.0, 4.0, 5.0, 6.0 MPa
- 迭代次数: 10

**自定义参数**:
```bash
export GAMMA_TABLE_PATH=scripts/gamma_tables/your_custom_table.jld2
export EPS_POF=0.01
export LAMBDA_CVAR=2.0
export THRESHOLD_VALUES=2.0,3.0,4.0,5.0,6.0
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

**输出文件**:
- `data/DT_control/exp_name=step1/threshold_sensitivity/summary__CVaR__sample=128.jld2`
- 每个阈值的详细结果在各自的子目录中

### 3. 生成 Gamma Table（如果需要）

如果还没有 gamma table，或想用改进方法重新生成：

**方法 1: 提交作业（推荐）**

```bash
sbatch scripts/shell/submit_gamma_table_generation.sh
```

**方法 2: 交互式运行**

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

这会生成 gamma table 并保存到 `data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2`

**注意**：新方法使用二分搜索，确保 POF ≈ eps_target，更准确但需要更长时间（约 15-25 分钟）。

### 4. 检查作业状态

```bash
# 查看队列中的作业
squeue -u hli853

# 查看作业输出
tail -f logs/threshold_sensitivity_POF_<JOBID>.txt
tail -f logs/threshold_sensitivity_CVaR_<JOBID>.txt
```

### 5. 生成对比图

等两个作业都完成后：

```bash
# 申请交互式节点
salloc -N1 -t 60 --account=gts-fherrmann9 -q inferno

# 加载模块并设置环境
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

# 运行绘图脚本
julia --project=. scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl --idx_num 128
```

**生成的图表**:
- `plots/DT_control/exp_name=step1/threshold_sensitivity/inj_vs_threshold__POF_vs_CVaR__sample=128.png`
- `plots/DT_control/exp_name=step1/threshold_sensitivity/risk_utilization__POF_vs_CVaR__sample=128.png`
- `plots/DT_control/exp_name=step1/threshold_sensitivity/pof_vs_cvar_comparison__sample=128.png`

## 预期结果

对比图应该显示：
- **CVaR 控制下的注入率更低**（更保守）
- **POF 控制下的注入率更高**（更激进）
- 两种方法的风险利用率对比

## 故障排除

### 问题 1: Gamma table 未找到

**错误**: `[ERROR] Gamma table not found`

**解决**: 先运行 gamma table 生成（见步骤 3）

### 问题 2: Summary 文件未找到

**错误**: `POF summary not found` 或 `CVaR summary not found`

**解决**: 
1. 检查作业是否完成：`squeue -u hli853`
2. 检查输出日志：`tail logs/threshold_sensitivity_*.txt`
3. 确认文件路径：`ls data/DT_control/exp_name=step1/threshold_sensitivity/summary__*.jld2`

### 问题 3: 注入率都是常数

如果所有阈值的注入率都相同（如 1.05），可能：
- 达到了上界约束
- 优化未真正收敛
- 惩罚权重太小

**解决**: 增加 `lambda_pof` 或 `lambda_cvar`，或增加 `niterations`

## 完整工作流示例

```bash
# 1. 生成 gamma table（如果还没有）
julia --project=. src/threshold_sensitivity.jl \
  --idx_num 128 \
  --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
  --gamma_table_generate auto \
  --gamma_table_eps_list 0.01

# 2. 提交 POF-only 作业
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh

# 3. 提交 CVaR-only 作业（等 POF 完成后或并行运行）
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh

# 4. 等待作业完成，然后生成对比图
salloc -N1 -t 60 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
julia --project=. scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl --idx_num 128
```
