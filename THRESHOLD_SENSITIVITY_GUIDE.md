# Threshold Sensitivity Analysis - 完整指南

## 📋 代码逻辑检查 Summary

### ✅ 核心逻辑正确性

1. **阈值循环逻辑** ✓
   - 正确遍历不同的 threshold 值
   - 每个阈值独立运行优化
   - 结果正确收集和保存

2. **POF/CVaR 计算** ✓
   - 即使禁用，POF 和 CVaR 仍会被计算（用于敏感性分析）
   - 计算逻辑与 `optim_inject.jl` 一致
   - 值正确保存到结果文件

3. **结果保存** ✓
   - 每个阈值的详细结果保存到独立目录
   - 汇总结果保存到 `summary__sample=<idx>.jld2`
   - 风险参数单独保存到 `risk_params__sample=<idx>.jld2`
   - 所有数据包含完整的元数据

4. **可视化** ✓
   - 生成 5 个敏感性分析图
   - 包含综合视图（2x2 subplot）
   - 图表正确标注和保存

### ⚠️ 需要注意的点

1. **校准功能**：`calibrate_gamma_for_eps()` 函数提供粗略估算，建议手动校准更准确
2. **内存管理**：每个阈值优化后调用 `GC.gc()`，但大量阈值可能仍需注意内存
3. **错误处理**：单个阈值失败不会中断整个分析，会记录 NaN 并继续

---

## 🔗 (eps, gamma) 对齐机制

### 当前对齐方式

**默认值（不对齐）**：
- `eps_pof` = 0.01 (1%)
- `gamma_cvar` = 0.0

**问题**：`gamma = 0.0` 通常过于严格，与 `eps = 0.01` 不对齐。

### 对齐方法

#### 方法 1: 自动校准（快速估算）

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
    --use_pof --eps_pof 0.01 \
    --use_cvar --alpha 0.05 \
    --calibrate_gamma
```

**工作原理**：
- 在第一个阈值上运行一次前向仿真
- 计算此时的 POF 和 CVaR
- 使用该 CVaR 值作为 `gamma_cvar` 的建议值
- 如果 `gamma_cvar = 0.0`，自动更新为建议值

**局限性**：这是粗略估算，基于初始猜测的注入速率，不是优化后的值。

#### 方法 2: 手动校准（推荐，更准确）

**步骤 1**：在参考阈值上运行完整优化
```bash
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --pof_as_constraint \
    --use_cvar --alpha 0.05 \
    --niterations 20
```

**步骤 2**：查看结果文件中的 (POF, CVaR) 对
```julia
using JLD2
data = load("data/DT_control/.../final.jld2")
println("POF (hard) = ", data["pof_hard_iter"][end])
println("CVaR = ", data["cvar_iter"][end])
```

**步骤 3**：使用该 CVaR 值作为 `gamma_cvar`
```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
    --use_pof --eps_pof 0.01 \
    --use_cvar --gamma_cvar <从步骤2得到的值> --alpha 0.05
```

#### 方法 3: 基于风险容忍度手动设置

如果你知道：
- `eps = 0.01` 表示允许 1% 的违反概率
- 那么 `gamma` 应该是对应这个概率水平下的条件期望损失

经验值（仅供参考）：
- `eps = 0.01` → `gamma ≈ 0.01-0.02`
- `eps = 0.05` → `gamma ≈ 0.05-0.10`

---

## 🚀 如何运行

### 基本用法（无风险约束，仅敏感性分析）

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 \
    --threshold_max 6.0 \
    --threshold_num 5
```

**说明**：
- 测试 5 个阈值：2.0, 3.0, 4.0, 5.0, 6.0 MPa
- 不应用风险约束（只最大化注入量）
- POF 和 CVaR 仍会被计算和保存（用于分析）

### 指定阈值列表

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_list "2.0,3.5,4.0,5.5,6.0"
```

### 带风险约束的敏感性分析

#### 选项 A: 使用自动校准

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --alpha 0.05 --lambda_cvar 1e6 \
    --calibrate_gamma
```

#### 选项 B: 手动设置对齐的 (eps, gamma)

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --lambda_cvar 1e6
```

#### 选项 C: 使用硬约束

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
    --use_pof --eps_pof 0.01 --pof_as_constraint \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --cvar_as_constraint
```

### 完整参数示例

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 \
    --threshold_max 6.0 \
    --threshold_num 5 \
    --use_pof \
    --eps_pof 0.01 \
    --tau_pof 0.05 \
    --kappa_pof 50.0 \
    --lambda_pof 1e6 \
    --use_cvar \
    --gamma_cvar 0.02 \
    --alpha 0.05 \
    --kappa_cvar 50.0 \
    --lambda_cvar 1e6 \
    --cvar_soft \
    --risk_mode relative \
    --weight_mode voltime \
    --niterations 20 \
    --inj_start 0.0001 \
    --inj_guess 0.05 \
    --save_plots \
    --plot_stride 5
```

---

## 📊 输出文件

### 1. 风险参数文件
`data/DT_control/exp_name=step1/threshold_sensitivity/risk_params__sample=<idx>.jld2`
- 包含所有风险参数设置
- 便于快速查看使用的 (eps, gamma) 值

### 2. 汇总结果
`data/DT_control/exp_name=step1/threshold_sensitivity/summary__sample=<idx>.jld2`
- 所有阈值的最终结果
- 包含 `risk_params` 字段

### 3. 各阈值详细结果
`data/DT_control/exp_name=step1/threshold_sensitivity/sample=<idx>__threshold=<value>/final.jld2`
- 每个阈值的完整优化历史
- 包含迭代过程中的 POF/CVaR 值

### 4. 可视化图表
`plots/DT_control/exp_name=step1/threshold_sensitivity/`
- `inj_rate_vs_threshold__sample=<idx>.png`
- `objective_vs_threshold__sample=<idx>.png`
- `pof_vs_threshold__sample=<idx>.png`
- `cvar_vs_threshold__sample=<idx>.png`
- `sensitivity_summary__sample=<idx>.png` (综合视图)

---

## ✅ 验证检查清单

运行前检查：
- [ ] 确定要测试的阈值范围
- [ ] 如果使用风险约束，确定 `eps` 值
- [ ] 如果同时使用 POF 和 CVaR，校准 `gamma` 值
- [ ] 检查数据文件路径是否正确

运行后检查：
- [ ] 查看控制台输出的风险参数设置
- [ ] 检查是否有对齐警告
- [ ] 查看汇总结果文件
- [ ] 检查可视化图表是否生成

---

## 🔍 常见问题

**Q: 如果 POF 和 CVaR 都禁用，还能做敏感性分析吗？**
A: 可以！即使禁用，POF 和 CVaR 仍会被计算和保存，可以分析它们对 threshold 的敏感性。

**Q: 自动校准的 gamma 准确吗？**
A: 这是粗略估算。更准确的方法是先运行完整优化，查看实际的 (POF, CVaR) 对。

**Q: 如何知道 (eps, gamma) 是否对齐？**
A: 运行时会打印警告。对齐意味着：当 POF ≈ eps 时，CVaR 应该 ≈ gamma。

**Q: 可以只启用 POF 或只启用 CVaR 吗？**
A: 可以。使用 `--use_pof` 或 `--use_cvar` 单独启用。

---

## 📝 总结

1. **代码逻辑**：✓ 正确，可以安全使用
2. **对齐机制**：提供自动校准和手动设置两种方式
3. **运行方式**：支持多种场景，从简单到复杂

**推荐工作流程**：
1. 先运行无约束版本，了解基本敏感性
2. 确定风险容忍度（eps）
3. 手动校准或使用自动校准确定 gamma
4. 运行带风险约束的完整敏感性分析

