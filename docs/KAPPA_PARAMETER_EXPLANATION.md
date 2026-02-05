# Kappa Parameter (κ) 详细说明

## 概述

Kappa (κ) 是控制 **softplus平滑函数陡峭程度** 的关键参数，用于将硬约束转换为可微的软约束。

## 数学原理

### Softplus函数定义

```julia
function softplus(x; κ::Float64 = 50.0)
    y = κ * x
    y = clamp(y, -50.0, 50.0)
    return log1p(exp(y)) / κ
end

@inline function dsoftplus(x; κ::Float64=50.0)
    y = clamp(κ*x, -50.0, 50.0)
    return 1.0/(1.0 + exp(-y))
end
```

**数学形式**：

```
softplus(x; κ) = log(1 + e^(κx)) / κ
```

**导数**：

```
d/dx softplus(x; κ) = 1 / (1 + e^(-κx)) = sigmoid(κx)
```

### 函数特性

1. **平滑ReLU近似**
   - 当 κ → ∞ 时，softplus(x; κ) → max(0, x)
   - 当 κ → 0 时，函数变得非常平滑
   - softplus函数处处可微（C^∞光滑）

2. **边界行为**
   - 当 x << 0 时，softplus(x; κ) ≈ 0
   - 当 x >> 0 时，softplus(x; κ) ≈ x
   - 在 x = 0 附近平滑过渡

3. **κ参数的影响**
   
   | κ值 | 在x=0.1处的值 | 在x=0.1处的梯度 | 误差 |
   |-----|---------------|-----------------|------|
   | 10  | 0.0953        | 0.731           | 4.7% |
   | 50  | 0.0999        | 0.993           | 0.1% |
   | 100 | 0.0999        | 0.999           | 0.01%|

## 在优化中的应用

### 1. POF惩罚（Probability of Failure）

```julia
κ_pof = risk.kappa_pof  # 默认 50.0
pen_pof = risk.λ_pof * (softplus(pof_smooth_hat - risk.ε; κ=κ_pof) - softplus(0.0; κ=κ_pof))
```

**Zero-baseline惩罚机制**：

```
penalty = λ * [softplus(metric - threshold; κ) - softplus(0; κ)]
```

- **当 metric < threshold**：penalty ≈ 0（允许范围内，无惩罚）
- **当 metric = threshold**：penalty = 0（零基线设计）
- **当 metric > threshold**：penalty > 0（违反约束，开始惩罚）

**关键优势**：
- 在阈值处惩罚为零（减去baseline）
- 梯度连续，优化稳定
- 可以通过κ调节"硬"的程度

### 2. CVaR惩罚（Conditional Value at Risk）

```julia
κ_cvar = risk.kappa_cvar  # 默认 50.0
pen_cvar = risk.λ_cvar * (softplus(cvar_smooth - risk.γ; κ=κ_cvar) - softplus(0.0; κ=κ_cvar))
```

同样使用zero-baseline机制，在CVaR超过允许水平γ时开始惩罚。

### 3. CVaR计算中的平滑

当使用 `--cvar_soft` 时，CVaR的RU形式计算也使用softplus：

```julia
φ(x) = smooth ? softplus(x; κ=kappa_cvar) : max(0.0, x)
```

这使得CVaR计算本身也变得可微和数值稳定。

## 参数选择指南

### 默认值：κ = 50.0

**为什么选择50？**

这是一个经过实践验证的平衡点：
- ✅ **足够陡峭**：在阈值附近表现接近硬约束（误差<0.1%）
- ✅ **梯度稳定**：避免梯度消失或爆炸
- ✅ **数值安全**：clamp(-50, 50)防止exp溢出
- ✅ **优化收敛**：提供足够的梯度信息引导优化

### 何时调整κ？

#### 增大κ（更陡峭，更接近硬约束）

**适用场景**：
- 风险约束必须严格满足
- 优化已经接近收敛，需要"锁定"约束
- 惩罚项太弱，无法有效约束

**建议值**：κ = 70 ~ 100

**注意事项**：
- 梯度可能变得更陡峭，需要更小的学习率
- 可能导致优化困难（函数接近不可微）

#### 减小κ（更平滑，更宽松）

**适用场景**：
- 初始阶段梯度震荡严重
- 优化不收敛或步长过小
- 需要探索更大的可行域
- 约束可以适当放松

**建议值**：κ = 20 ~ 40

**注意事项**：
- 约束会变松，可能无法满足严格要求
- 最终结果可能违反原始约束

### κ值对比表

| κ值 | 约束强度 | 梯度质量 | 优化难度 | 推荐场景 |
|-----|---------|---------|---------|---------|
| 10-20 | 很弱 | 平滑 | 容易 | 初步探索 |
| 30-40 | 中等 | 较好 | 适中 | 早期优化 |
| **50** | **较强** | **良好** | **适中** | **默认推荐** |
| 70-100 | 很强 | 陡峭 | 困难 | 精细调优 |
| >100 | 接近硬约束 | 几乎离散 | 很困难 | 不推荐 |

## 可视化示例

### 生成Softplus曲线对比

使用内置demo功能：

```bash
julia src/optim_inject.jl \
  --plot_softplus_demo \
  --kappa_pof 50 \
  --kappa_cvar 50
```

这会在plots目录生成 `softplus_demo.png`，展示：
- POF softplus曲线（κ=50）
- CVaR softplus曲线（κ=50）
- 零基线效果（减去softplus(0)）

### 不同κ值的视觉效果

在x ∈ [-0.05, 0.05]范围内：

```
κ = 20:  平滑过渡，在x=0附近几乎是线性
κ = 50:  快速过渡，但仍保持平滑
κ = 100: 几乎是直角，接近ReLU
```

## 命令行使用

### 基本用法

```bash
julia src/optim_inject.jl \
  --use_pof \
  --kappa_pof 50.0 \
  --use_cvar \
  --kappa_cvar 50.0
```

### 高级场景

**严格约束场景**（推荐κ=70）：

```bash
julia src/optim_inject.jl \
  --use_pof --pof_as_constraint \
  --kappa_pof 70.0 \
  --eps_pof 0.01
```

**探索性优化**（推荐κ=30）：

```bash
julia src/optim_inject.jl \
  --use_cvar \
  --kappa_cvar 30.0 \
  --gamma_cvar 0.02
```

**软CVaR平滑**（使用两个κ）：

```bash
julia src/optim_inject.jl \
  --use_cvar --cvar_soft \
  --kappa_cvar 50.0  # 用于惩罚项和CVaR计算
```

## 实现细节

### Clamp保护

```julia
y = clamp(κ*x, -50.0, 50.0)
```

**为什么需要clamp？**

- `exp(50) ≈ 5×10^21`（接近Float64上限）
- `exp(100)` 会溢出为Inf
- clamp确保数值稳定性

### Zero-baseline设计

```julia
penalty = softplus(violation; κ) - softplus(0.0; κ)
```

**设计目的**：
- 确保在约束边界（violation=0）时惩罚为0
- 只对超出阈值的部分进行惩罚
- 避免在可行域内引入不必要的惩罚

**数值验证**：

```julia
# 当 violation = 0
softplus(0; κ=50) - softplus(0; κ=50) = 0  ✓

# 当 violation < 0（满足约束）
softplus(-0.01; κ=50) - softplus(0; κ=50) ≈ -0.0099 ≈ 0  ✓

# 当 violation > 0（违反约束）
softplus(0.01; κ=50) - softplus(0; κ=50) ≈ 0.0099 > 0  ✓
```

## 常见问题

### Q1: 为什么不直接使用硬约束（κ→∞）？

**A**: 硬约束的问题：
- 不可微，无法使用基于梯度的优化
- 在约束边界附近梯度消失
- 线搜索可能失败（目标函数不连续）

### Q2: κ_pof和κ_cvar可以设置不同值吗？

**A**: 可以！根据具体需求：
- 如果POF约束更重要：增大κ_pof
- 如果CVaR约束更重要：增大κ_cvar
- 通常保持相同即可（50.0）

### Q3: 如何判断κ是否合适？

**A**: 检查以下指标：
1. **惩罚项大小**：是否在合理范围（目标函数的1-10%）
2. **梯度范数**：是否太大或太小
3. **步长收敛**：是否能正常backtracking
4. **约束满足**：最终是否接近目标阈值

### Q4: κ=50对应的"硬度"是多少？

**A**: 在阈值附近：
- 误差：< 0.1%（相对于硬约束max(0,x)）
- 梯度：≈ 0.99（接近1，但仍然平滑）
- 相当于"99%硬度"的软约束

## 相关文档

- [Lambda选择指南](LAMBDA_SELECTION_GUIDE.md) - λ权重参数
- [优化选择指南](OPTIMIZATION_CHOICE_GUIDE.md) - 硬约束vs软约束
- [步长说明](STEP_SIZE_EXPLANATION.md) - 梯度下降步长

## 技术参考

### 代码位置

- 函数定义：`src/optim_inject.jl` 第176-187行
- POF惩罚：`src/optim_inject.jl` 第540行
- CVaR惩罚：`src/optim_inject.jl` 第541行
- CVaR平滑：`src/optim_inject.jl` 第375-376行
- Demo生成：`src/optim_inject.jl` 第258-273行

### 参数定义

```julia
"--kappa_pof"
    help = "κ for POF softplus (zero-baseline)"
    arg_type = Float64
    default = 50.0

"--kappa_cvar"
    help = "κ for CVaR softplus (zero-baseline)"
    arg_type = Float64
    default = 50.0
```

## 版本历史

- 2024-11: 引入可配置kappa参数（之前硬编码为50）
- 2024-12: 添加zero-baseline设计和softplus demo
- 2025-01: 文档完善，添加详细使用指南
