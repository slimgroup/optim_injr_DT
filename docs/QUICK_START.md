# 快速开始：POF vs CVaR 对比实验

## 完整运行流程（按顺序）

### 步骤 1: 生成 Gamma Table（必须，约 3-5 分钟，并行处理）

**方法 A: 提交作业（推荐）**

```bash
sbatch scripts/shell/submit_gamma_table_generation.sh
```

**方法 B: 交互式运行（可以看到进度）**

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

**检查作业状态**：
```bash
squeue -u hli853
```

**查看输出**（如果提交了作业）：
```bash
tail -f logs/gamma_table_gen_<JOBID>.txt
```

**生成的文件**：
- `data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2`

---

### 步骤 2: 验证 Gamma Table（可选但推荐）

等步骤 1 完成后，检查准确性：

```bash
salloc -N1 -t 30 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

# 找到最新生成的 gamma table
julia --project=. scripts/julia_scripts/utilities/check_gamma_table.jl \
  data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2
```

应该看到大部分条目标记为 ✓（POF 误差 < 5%）。

---

### 步骤 3: 运行 POF-only 优化

```bash
export EPS_POF=0.01
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh
```

**检查作业状态**：
```bash
squeue -u hli853
```

**查看输出**：
```bash
tail -f logs/threshold_sensitivity_POF_<JOBID>.txt
```

**生成的文件**：
- `data/DT_control/exp_name=step1/threshold_sensitivity/summary__POF__sample=128.jld2`

---

### 步骤 4: 运行 CVaR-only 优化

**先找到步骤 1 生成的 gamma table 路径**，然后：

```bash
# 设置环境变量（使用步骤 1 生成的 gamma table）
export EPS_POF=0.01
export GAMMA_TABLE_PATH=data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2

# 提交作业
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

**或者直接指定完整路径**（如果知道文件名）：
```bash
export EPS_POF=0.01
export GAMMA_TABLE_PATH=data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__20251125_*.jld2
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

**检查作业状态**：
```bash
squeue -u hli853
```

**查看输出**：
```bash
tail -f logs/threshold_sensitivity_CVaR_<JOBID>.txt
```

**生成的文件**：
- `data/DT_control/exp_name=step1/threshold_sensitivity/summary__CVaR__sample=128.jld2`

---

### 步骤 5: 生成对比图

等步骤 3 和 4 都完成后：

```bash
salloc -N1 -t 60 --account=gts-fherrmann9 -q inferno
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg

julia --project=. scripts/julia_scripts/plotting/plot_pof_vs_cvar.jl --idx_num 128
```

**生成的图表**：
- `plots/DT_control/exp_name=step1/threshold_sensitivity/inj_vs_threshold__POF_vs_CVaR__sample=128.png`
- `plots/DT_control/exp_name=step1/threshold_sensitivity/risk_utilization__POF_vs_CVaR__sample=128.png`
- `plots/DT_control/exp_name=step1/threshold_sensitivity/pof_vs_cvar_comparison__sample=128.png`

---

## 时间估算

- **步骤 1 (Gamma Table)**: 3-5 分钟（并行处理，使用 8 线程）
- **步骤 2 (验证)**: 1-2 分钟
- **步骤 3 (POF-only)**: 1-3 小时（5 个阈值，每个约 20-30 分钟）
- **步骤 4 (CVaR-only)**: 1-3 小时（5 个阈值，每个约 20-30 分钟）
- **步骤 5 (绘图)**: 1-2 分钟

**总计**: 约 2.5-6.5 小时（大部分时间在等待作业）

---

## 检查所有作业状态

```bash
# 查看所有作业
squeue -u hli853

# 查看特定作业的输出
tail -f logs/gamma_table_gen_<JOBID>.txt
tail -f logs/threshold_sensitivity_POF_<JOBID>_<ARRAY_ID>.txt
tail -f logs/threshold_sensitivity_CVaR_<JOBID>_<ARRAY_ID>.txt
```

---

## 故障排除

### 问题 1: Gamma table 未找到

**错误**: `[ERROR] Gamma table not found`

**解决**: 
1. 检查步骤 1 是否完成：`squeue -u hli853`
2. 检查文件是否存在：`ls data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__*.jld2`
3. 使用完整路径：`export GAMMA_TABLE_PATH=<完整路径>`

### 问题 2: Summary 文件未找到

**错误**: `POF summary not found` 或 `CVaR summary not found`

**解决**:
1. 检查作业是否完成：`squeue -u hli853`
2. 检查输出日志：`tail logs/threshold_sensitivity_*.txt`
3. 确认文件路径：`ls data/DT_control/exp_name=step1/threshold_sensitivity/summary__*.jld2`

### 问题 3: 作业运行时间过长

如果单个阈值运行超过 1 小时，可能：
- 优化迭代次数太多（默认 10 次）
- 梯度计算太慢

**解决**: 可以减少迭代次数或使用 forward difference gradient（已在脚本中启用）

---

## 一键运行（所有步骤）

如果你想一次性提交所有作业（不推荐，因为步骤 4 依赖步骤 1）：

```bash
# 1. 生成 gamma table
JOB1=$(sbatch scripts/shell/submit_gamma_table_generation.sh | awk '{print $4}')

# 2. 等 gamma table 完成后，运行 POF-only（需要手动等待）
# export EPS_POF=0.01
# sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh

# 3. 运行 CVaR-only（需要手动等待步骤 1 完成）
# export EPS_POF=0.01
# export GAMMA_TABLE_PATH=data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=128__*.jld2
# sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

**建议**: 按顺序运行，确保每一步都成功完成。

