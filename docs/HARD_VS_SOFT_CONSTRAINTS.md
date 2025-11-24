# 硬约束 vs 软约束 - 详细对比

## 📊 数学表达

### 硬约束 (Hard Constraint)
```
if POF > ε:
    objective = +∞  (不可行)
else:
    objective = base_objective
```

### 软约束 (Soft Penalty)
```
objective = base_objective + λ × penalty(violation)
where penalty(x) = softplus(x - threshold) - softplus(0)
```

---

## 🔍 代码实现对比

### 硬约束实现（第 511-528 行）

```julia
# 硬约束：如果违反，直接返回 Inf
if risk.use_pof && risk.pof_as_constraint && (pof_hard_hat > risk.ε + 1e-12)
    return Inf, obj, 0.0, 0.0, 0.0, ...  # 目标函数 = +∞
end

if risk.use_cvar && risk.cvar_as_constraint && (cvar_eval > risk.γ + 1e-12)
    return Inf, obj, 0.0, 0.0, 0.0, ...  # 目标函数 = +∞
end
```

**特点**：
- ✅ **严格不等式**：`POF ≤ ε` 或 `CVaR ≤ γ`（带容差 1e-12）
- ✅ **不可行 = 无穷大**：违反约束时 `objective = Inf`
- ✅ **二元性**：要么可行（正常优化），要么不可行（Inf）

### 软约束实现（第 530-535 行）

```julia
# 软罚：使用 softplus 函数，零基线
pen_pof  = risk.use_pof  ? risk.λ_pof  * (softplus(pof_smooth_hat - risk.ε; κ=κ_pof)  - softplus(0.0; κ=κ_pof))  : 0.0
pen_cvar = risk.use_cvar ? risk.λ_cvar * (softplus(cvar_smooth     - risk.γ; κ=κ_cvar) - softplus(0.0; κ=κ_cvar)) : 0.0
penalty  = pen_pof + pen_cvar

obj_total = obj_base + penalty
```

**特点**：
- ✅ **连续惩罚**：违反程度越大，惩罚越大
- ✅ **零基线**：`softplus(x - ε) - softplus(0)`，当 `x ≤ ε` 时惩罚 ≈ 0
- ✅ **可微**：softplus 函数平滑可微，优化友好

---

## 📈 Softplus 函数详解

### 定义（第 184-188 行）

```julia
function softplus(x; κ::Float64 = 50.0)
    y = κ * x
    y = clamp(y, -50.0, 50.0)
    return log1p(exp(y)) / κ
end
```

### 数学形式

```
softplus(x; κ) = (1/κ) × log(1 + exp(κ×x))
```

### 性质

1. **当 x < 0**：`softplus(x) ≈ 0`（接近 0）
2. **当 x = 0**：`softplus(0) = log(2)/κ ≈ 0.014/κ`（很小）
3. **当 x > 0**：`softplus(x) ≈ x`（线性增长）

### 零基线惩罚

```julia
penalty = softplus(violation - threshold) - softplus(0)
```

**行为**：
- `violation ≤ threshold`：惩罚 ≈ 0（满足约束）
- `violation > threshold`：惩罚 ≈ `violation - threshold`（线性惩罚）

### 可视化

```
violation = POF - ε (或 CVaR - γ)

penalty(violation):
  |
  |     /  (线性增长)
  |    /
  |   /
  |__/___________ violation
  0  threshold
```

---

## ⚖️ 对比表格

| 特性 | 硬约束 | 软约束 |
|------|--------|--------|
| **数学形式** | `POF ≤ ε` (严格) | `obj = base + λ×penalty` |
| **违反时** | `objective = +∞` | `penalty > 0` (连续) |
| **可行性** | 二元（可行/不可行） | 连续（总是可行） |
| **梯度** | 在边界处不连续 | 平滑可微 |
| **优化难度** | 困难（需要可行初始点） | 容易（总是有梯度） |
| **边界探索** | 无法探索边界外 | 可以探索边界附近 |
| **保证性** | ✅ 严格满足约束 | ⚠️ 可能轻微违反 |
| **适用场景** | 最终验证、严格合规 | 探索性优化、敏感性分析 |

---

## 🎯 实际例子

### 场景：POF 阈值 ε = 0.01

#### 硬约束
```julia
if pof_hard_hat > 0.01 + 1e-12:
    return Inf  # 不可行
```

**结果**：
- POF = 0.009 → ✅ 可行，正常优化
- POF = 0.010 → ✅ 可行（在容差内）
- POF = 0.011 → ❌ 不可行，objective = Inf

#### 软约束（λ = 1e6, κ = 50）
```julia
penalty = 1e6 × (softplus(0.011 - 0.01; κ=50) - softplus(0.0; κ=50))
        ≈ 1e6 × (softplus(0.001; κ=50) - 0.014/50)
        ≈ 1e6 × 0.001  # 当 violation 小时，softplus ≈ violation
        ≈ 1000
```

**结果**：
- POF = 0.009 → penalty ≈ 0
- POF = 0.010 → penalty ≈ 0
- POF = 0.011 → penalty ≈ 1000（可优化，但会被惩罚）

---

## 🔧 参数影响

### 软约束参数

1. **λ (lambda)**：惩罚权重
   - `λ` 大 → 惩罚重 → 更接近硬约束行为
   - `λ` 小 → 惩罚轻 → 允许更多违反

2. **κ (kappa)**：softplus 的锐度
   - `κ` 大 → 更接近线性（hinge-like）
   - `κ` 小 → 更平滑（sigmoid-like）

### 硬约束参数

1. **ε (eps)**：POF 阈值（严格）
2. **γ (gamma)**：CVaR 阈值（严格）
3. **容差 1e-12**：数值容差，避免浮点误差

---

## 💡 选择建议

### 使用硬约束当：
- ✅ 需要**严格保证**满足约束
- ✅ 最终验证阶段
- ✅ 法规/合规要求
- ✅ 约束是物理不可行的（如压力不能超过破裂压力）

### 使用软约束当：
- ✅ **探索性优化**（如敏感性分析）
- ✅ 需要**平滑梯度**
- ✅ 允许**轻微违反**以换取更好的目标值
- ✅ 约束边界**不确定**，需要探索

---

## 🔄 组合使用策略

### 推荐工作流程

1. **阶段 1：探索（软约束）**
   ```bash
   --use_pof --eps_pof 0.01 --lambda_pof 1e6
   --use_cvar --gamma_cvar 0.02 --lambda_cvar 1e6
   ```
   - 找到大致的最优解
   - 了解约束边界的行为

2. **阶段 2：验证（硬约束）**
   ```bash
   --use_pof --eps_pof 0.01 --pof_as_constraint
   --use_cvar --gamma_cvar 0.02 --cvar_as_constraint
   ```
   - 验证解是否严格满足约束
   - 如果满足，说明软约束的 λ 设置合适

3. **阶段 3：生产（硬约束）**
   - 使用硬约束确保最终部署方案满足要求

---

## 📝 总结

- **硬约束** = 严格不等式，违反 = Inf，保证满足但优化困难
- **软约束** = 连续惩罚，违反 = 增加惩罚，优化容易但可能轻微违反
- **零基线 softplus** = 满足约束时惩罚 ≈ 0，违反时线性增长
- **推荐**：探索用软约束，验证/生产用硬约束

