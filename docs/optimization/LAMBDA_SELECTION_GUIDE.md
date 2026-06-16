# Lambda Penalty Term 选择分析

## 概述

本文档分析了之前提交的 PoF 和 CVaR cases 中 penalty term lambda 的选择。

## Lambda 值总结

### PoF Cases
- **lambda_pof = 8.5e8** (8.5 × 10⁸ = 850,000,000)
- 使用场景：所有 PoF cases（包括 submit_pof_cases_smart.sh）
- 相关参数：
  - `--pof_as_constraint` (硬约束)
  - `--tau_pof 0.05` (平滑温度)
  - `--kappa_pof 50` (softplus 锐度参数)

### CVaR Cases
- **lambda_cvar = 3.0e9** (3.0 × 10⁹ = 3,000,000,000)
- 使用场景：所有 CVaR cases（包括 submit_20_cases_samples_65_128_smart.sh）
- 相关参数：
  - `--cvar_as_constraint` (硬约束)
  - `--cvar_soft` (使用 softplus 平滑的 CVaR)
  - `--kappa_cvar 50` (softplus 锐度参数)

## Lambda 值对比

| 指标 | PoF | CVaR | 比例 |
|------|-----|------|------|
| Lambda 值 | 8.5e8 | 3.0e9 | 1:3.53 |
| 数量级 | 10⁸ | 10⁹ | CVaR 约 3.5 倍 |

**观察**：CVaR 的 lambda 值约为 PoF 的 3.5 倍，说明 CVaR 惩罚项需要更强的权重。

## 使用场景

### PoF Cases 提交
- **脚本**: `scripts/shell/submit/submit_pof_cases_smart.sh`
- **总任务数**: 832 jobs
  - 5 cases (eps=0.0,0.001,0.01,0.02,0.05) × 64 samples (65-128) = 320 jobs
  - 4 cases (eps=0.002,0.003,0.005,0.03) × 96 samples (33-128) = 384 jobs
  - 1 case (eps=0.1) × 128 samples (1-128) = 128 jobs
- **Lambda 设置**: `--lambda_pof 8.5e8`

### CVaR Cases 提交
- **脚本**: `scripts/shell/submit/submit_20_cases_samples_65_128_smart.sh`
- **总任务数**: 1280 jobs (20 cases × 64 samples)
- **Lambda 设置**: `--lambda_cvar 3.0e9`
- **20 个 cases 组合**:
  - 8 cases: alpha=0.0 或 0.001, 配合 gamma=0.0, 0.01, 0.02, 0.05
  - 3 cases: alpha=0.01, 0.02, 0.05, gamma=0.0
  - 9 cases: alpha=0.01, 0.02, 0.05, 配合 gamma=0.01, 0.02, 0.05

## 约束模式

### 硬约束 (Hard Constraint)
所有提交的 cases 都使用了 `--pof_as_constraint` 或 `--cvar_as_constraint`，这意味着：
- 如果违反约束（PoF > ε 或 CVaR > γ），目标函数直接返回 `Inf`
- Lambda 值主要用于软约束场景，但在硬约束模式下仍作为参考值保留

### 软约束 (Soft Penalty)
虽然使用了硬约束，但 lambda 值仍然定义在代码中，用于：
- 软约束场景的参考
- 未来可能的软约束实验

## Lambda 选择原理

根据代码实现（`src/optim_inject.jl` 第 540-541 行）：

```julia
pen_pof  = risk.use_pof  ? risk.λ_pof  * (softplus(pof_smooth_hat - risk.ε; κ=κ_pof)  - softplus(0.0; κ=κ_pof))  : 0.0
pen_cvar = risk.use_cvar ? risk.λ_cvar * (softplus(cvar_smooth     - risk.γ; κ=κ_cvar) - softplus(0.0; κ=κ_cvar)) : 0.0
```

### 选择原则
1. **数量级匹配**：Lambda 需要与基础目标函数的数量级相匹配
2. **惩罚强度**：确保违反约束时有足够的惩罚，但不过度影响优化
3. **经验调优**：这些值可能是通过实验调优得到的

### 为什么 CVaR 的 lambda 更大？
- CVaR 是条件期望值，通常数值范围可能更大
- CVaR 的违反可能比 PoF 的违反更严重（涉及尾部风险）
- 需要更强的惩罚来确保约束满足

## 相关文件

### 提交脚本
- `scripts/shell/submit/submit_pof_cases_smart.sh` - PoF cases 提交
- `scripts/shell/submit/submit_20_cases_samples_65_128_smart.sh` - CVaR cases 提交
- `scripts/shell/submit/submit_all.sh` - 早期提交脚本（也使用相同 lambda 值）

### 代码实现
- `src/optim_inject.jl` - 主要优化代码，包含 lambda 使用逻辑
- `docs/optimization/OPTIMIZATION_CHOICE_GUIDE.md` - 优化选择指南（含硬约束 vs 软约束说明）

## 建议

1. **保持一致性**：在未来的提交中，建议继续使用这些经过验证的 lambda 值
2. **文档化**：如果进行 lambda 调优，建议记录调优过程和结果
3. **验证**：可以通过检查优化结果中的 penalty share 来验证 lambda 是否合适

## 日志文件

提交日志记录了实际的提交情况（位于 `logs/submit/`）：
- `logs/submit/submit_pof_cases_simple.log`（或历史 `submit_pof_cases.log`）- PoF cases 提交日志
- `logs/submit/submit_20_cases_65_128.log` - CVaR cases 提交日志（部分）
- `logs/submit/submit_20_cases_65_128_continue.log` - CVaR cases 继续提交日志

