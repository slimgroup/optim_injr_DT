# 如何运行所有1-128个index

## 当前状态

- ✅ 已提交11个cases，使用 `idx_num=128` 测试
- ✅ 代码已更新：`ex_step_size = 0.1` (简化版)
- ⏳ 等待稳定后，可以批量运行1-128所有index

## 运行所有index的方法

### 方法1: 修改为SLURM array job（推荐）

修改 `scripts/shell/submit_cvar_gamma0.sh` 和 `submit_cvar_additional.sh`：

```bash
# 在脚本中添加一个index数组参数
#SBATCH --array=1-128

# 然后在julia命令中使用：
julia --project=. -t 1 src/optim_inject.jl \
    --idx_num $SLURM_ARRAY_TASK_ID \  # 改为使用array task ID
    --alpha $ALPHA \
    ...
```

**注意**: 这样会同时运行128个tasks，可能需要大量资源。建议分批运行。

### 方法2: 分批运行（更安全）

创建一个新的脚本 `submit_all_indices.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=cvar_all_idx
#SBATCH --account=gts-fherrmann9
#SBATCH --array=1-128
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --output=logs/cvar_all_idx_%A_%a.out
#SBATCH --error=logs/cvar_all_idx_%A_%a.err

# 使用array task ID作为index
IDX=$SLURM_ARRAY_TASK_ID

# 然后对每个CVaR case分别运行
# 例如：alpha=0.01, gamma=0.0
julia --project=. -t 1 src/optim_inject.jl \
    --idx_num $IDX \
    --alpha 0.01 \
    --use_cvar \
    --lambda_cvar 1.0 \
    --gamma_cvar 0.0 \
    ...
```

### 方法3: 使用循环提交（最灵活）

创建一个脚本循环提交：

```bash
#!/bin/bash
for idx in {1..128}; do
    for alpha in 0.01 0.02 0.05; do
        sbatch --job-name=cvar_idx${idx}_a${alpha} \
               --export=IDX=$idx,ALPHA=$alpha \
               submit_single_case.sh
    done
done
```

## 建议的工作流程

1. **等待当前11个cases完成** (idx=128)
2. **检查结果是否稳定**
3. **选择要运行的CVaR cases组合**
4. **使用方法2创建批量运行脚本**
5. **分批提交**（例如每次提交32个index，分4批）

## 资源估算

- 每个case: 约15-16小时（20 iterations）
- 11个cases × 128个index = 1,408个jobs
- 总计算时间: 约22,000小时（如果串行运行）
- 建议: 使用array job并行运行，但注意资源限制

## 注意事项

- 确保有足够的存储空间（每个case生成多个JLD2文件）
- 监控日志文件大小
- 考虑使用 `--save_every 5` 减少I/O开销
- 单线程配置已设置，避免资源竞争

