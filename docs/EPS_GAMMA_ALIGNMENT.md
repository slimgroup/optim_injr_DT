# EPS 和 Gamma 对应关系说明

## 问题

在比较 POF-only 和 CVaR-only 优化时，需要确保：
- **POF-only** 使用 `eps_pof = 0.01`
- **CVaR-only** 使用对应的 `gamma`，使得当 POF = 0.01 时，CVaR ≈ gamma

## 当前实现的限制

### Gamma Table 生成方法

当前的 `calibrate_gamma_for_eps` 函数：
1. 使用固定的初始注入率猜测（默认 0.05）运行一次前向模拟
2. 读取此时的 POF 和 CVaR 值
3. 返回 CVaR 作为 `suggested_gamma`

**问题**：此时 POF 可能**不等于** `eps_target`，所以返回的 gamma 值并不是"当 POF = eps 时，CVaR = gamma"的严格对应关系。

### 为什么不够准确？

```
理想情况：
  POF = eps_target = 0.01  →  CVaR = gamma

实际情况（gamma table 生成）：
  使用 inj_rate_guess = 0.05 运行一次模拟
  POF ≈ 0.26 (可能远大于 0.01)  →  CVaR ≈ 0.75
  返回 gamma = 0.75

但这不是"当 POF = 0.01 时，CVaR = 0.75"的对应关系！
```

## 如何确保对应关系？

### 方法 1: 使用相同的 eps（推荐）

**POF-only 运行**：
```bash
export EPS_POF=0.01
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh
```

**CVaR-only 运行**：
```bash
export EPS_POF=0.01  # ⭐ 必须与 POF-only 相同
export GAMMA_TABLE_PATH=scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

这样 CVaR-only 会从 gamma table 中查找 `eps = 0.01` 对应的 gamma 值。

### 方法 2: 验证和调整（更准确）

1. **先运行 POF-only 优化**，得到最优解
2. **检查最终结果**：
   - 如果 `final_pof ≈ eps_pof`，读取 `final_cvar`
   - 这个 `final_cvar` 就是更准确的 gamma 值
3. **手动更新 gamma table** 或直接使用这个 gamma 值运行 CVaR-only

### 方法 3: 改进 Gamma Table 生成（未来改进）

更准确的方法是：
1. 对于每个阈值，运行一个简化的优化，找到使 POF ≈ eps_target 的注入率
2. 读取此时的 CVaR 值作为 gamma
3. 这会更耗时，但更准确

## 当前工作流

### 步骤 1: 生成 Gamma Table

```bash
julia src/threshold_sensitivity.jl \
  --idx_num 128 \
  --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
  --gamma_table_generate auto \
  --gamma_table_eps_list 0.01
```

**注意**：生成的 gamma 值是粗略估计，基于固定注入率的单次前向模拟。

### 步骤 2: 运行 POF-only（使用 eps = 0.01）

```bash
export EPS_POF=0.01
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_pof_only.sh
```

### 步骤 3: 运行 CVaR-only（使用相同的 eps = 0.01 查找 gamma）

```bash
export EPS_POF=0.01  # ⭐ 必须与 POF-only 相同
export GAMMA_TABLE_PATH=scripts/gamma_tables/gamma_table__sample=128__*.jld2
sbatch --array=1-5 scripts/shell/submit_threshold_sensitivity_cvar_only.sh
```

### 步骤 4: 验证对应关系

运行完成后，检查结果：

```julia
# 在 Julia 中
using JLD2

# 加载 POF-only 结果
pof_data = JLD2.load("data/DT_control/exp_name=step1/threshold_sensitivity/summary__POF__sample=128.jld2")
println("POF-only final POF: ", pof_data["final_pof_hard"])
println("POF-only final CVaR: ", pof_data["final_cvar"])

# 加载 CVaR-only 结果
cvar_data = JLD2.load("data/DT_control/exp_name=step1/threshold_sensitivity/summary__CVaR__sample=128.jld2")
println("CVaR-only final POF: ", cvar_data["final_pof_hard"])
println("CVaR-only final CVaR: ", cvar_data["final_cvar"])
```

**理想情况**：
- POF-only: `final_pof ≈ 0.01`, `final_cvar ≈ gamma_from_table`
- CVaR-only: `final_pof ≈ 0.01`, `final_cvar ≈ gamma_from_table`

如果差异较大，说明 gamma table 的估计不够准确，需要调整。

## 改进建议

### 短期（当前可用）

1. **确保使用相同的 eps**：POF-only 和 CVaR-only 都使用 `EPS_POF=0.01`
2. **验证结果**：运行后检查最终的 POF 和 CVaR 值
3. **手动调整**：如果发现不对齐，手动设置更准确的 gamma 值

### 长期（未来改进）

1. **改进 gamma table 生成**：使用迭代方法找到使 POF = eps 的注入率
2. **后处理校准**：运行优化后，基于实际结果更新 gamma table
3. **自动对齐**：在优化过程中自动调整 gamma，使 POF ≈ eps

## 总结

**当前实现**：
- ✅ 使用相同的 `eps_pof` 确保两个方法目标一致
- ✅ Gamma table 提供每个阈值对应的 gamma 估计值
- ⚠️  Gamma 值是粗略估计，不是严格对应关系

**建议**：
- 运行后验证最终结果
- 如果发现不对齐，手动调整 gamma 值
- 在论文/报告中说明 gamma 值的来源和限制

