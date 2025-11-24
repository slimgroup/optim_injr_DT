# 优化时的硬/软约束选择指南

## 🔍 Softplus 函数的作用

### 为什么需要 Softplus？

**问题**：如果直接用 `max(0, violation)`（hinge 函数）会怎样？

```julia
# 简单 hinge 函数
penalty = λ × max(0, POF - ε)
```

**问题**：
- ❌ 在 `POF = ε` 处**不可微**（梯度不连续）
- ❌ 梯度在边界处突然跳跃（从 0 跳到 λ）
- ❌ 有限差分梯度计算不稳定
- ❌ 优化器难以收敛

### Softplus 的解决方案

```julia
softplus(x; κ) = (1/κ) × log(1 + exp(κ×x))
penalty = λ × (softplus(POF - ε) - softplus(0))
```

**优势**：
- ✅ **处处可微**：平滑过渡，没有跳跃
- ✅ **梯度连续**：从 0 平滑增长到 λ
- ✅ **数值稳定**：有限差分计算更准确
- ✅ **优化友好**：梯度下降更容易收敛

### 可视化对比

```
Hinge 函数 (max):
  |
λ |     ┌───────  (在 ε 处不可微)
  |    /
  |   /
  |__/___________ POF
  0  ε

Softplus 函数:
  |
λ |     ╱───────  (平滑过渡，处处可微)
  |    ╱
  |   ╱
  |__╱___________ POF
  0  ε
```

### 零基线的作用

```julia
penalty = softplus(POF - ε) - softplus(0)
```

**目的**：确保满足约束时惩罚 ≈ 0

- `POF ≤ ε`：`POF - ε ≤ 0` → `softplus(负值) ≈ 0` → 惩罚 ≈ 0
- `POF > ε`：`POF - ε > 0` → `softplus(正值) ≈ POF - ε` → 惩罚 ≈ `POF - ε`

---

## 🎯 实际优化时的选择策略

### 决策树

```
开始优化
  │
  ├─ 需要严格保证满足约束？
  │   │
  │   ├─ 是 → 使用硬约束
  │   │      └─ 最终验证、合规要求
  │   │
  │   └─ 否 → 继续判断
  │
  ├─ 约束边界不确定？
  │   │
  │   ├─ 是 → 使用软约束
  │   │      └─ 探索性优化、敏感性分析
  │   │
  │   └─ 否 → 继续判断
  │
  ├─ 优化经常失败（找不到可行解）？
  │   │
  │   ├─ 是 → 使用软约束
  │   │      └─ 允许轻微违反，找到近似解
  │   │
  │   └─ 否 → 继续判断
  │
  └─ 需要快速收敛？
      │
      ├─ 是 → 使用软约束
      │      └─ 梯度平滑，收敛更快
      │
      └─ 否 → 使用硬约束
             └─ 如果约束合理，硬约束也可以
```

---

## 📋 具体场景建议

### 场景 1: 探索性优化（推荐：软约束）

**目标**：找到大致最优解，了解系统行为

```bash
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --lambda_cvar 1e6 \
    --niterations 20
```

**为什么**：
- ✅ 可以探索边界附近的行为
- ✅ 梯度平滑，收敛快
- ✅ 即使初始解违反约束也能优化

### 场景 2: 阈值敏感性分析（推荐：软约束）

**目标**：分析不同阈值下的最优解

```bash
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 2.0 --threshold_max 6.0 --threshold_num 5 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --lambda_cvar 1e6 \
    --calibrate_gamma
```

**为什么**：
- ✅ 需要连续探索不同阈值
- ✅ 硬约束可能在某些阈值下找不到可行解
- ✅ 可以看到惩罚项如何变化

### 场景 3: 最终验证（推荐：硬约束）

**目标**：确保最终方案严格满足要求

```bash
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --pof_as_constraint \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --cvar_as_constraint \
    --niterations 20
```

**为什么**：
- ✅ 严格保证满足约束
- ✅ 如果满足，说明软约束的 λ 设置合适
- ✅ 用于最终部署前的验证

### 场景 4: 参数调优（推荐：软约束 → 硬约束）

**阶段 1：调参（软约束）**
```bash
# 尝试不同的 λ 值，找到合适的惩罚强度
julia src/optim_inject.jl --use_pof --eps_pof 0.01 --lambda_pof 1e5
julia src/optim_inject.jl --use_pof --eps_pof 0.01 --lambda_pof 1e6
julia src/optim_inject.jl --use_pof --eps_pof 0.01 --lambda_pof 1e7
```

**阶段 2：验证（硬约束）**
```bash
# 用硬约束验证最终解
julia src/optim_inject.jl --use_pof --eps_pof 0.01 --pof_as_constraint
```

---

## 🔧 软约束参数设置

### λ (lambda) 的选择

**原则**：让惩罚项在目标函数中占适当比例

**经验值**：
- `λ = 1e5`：轻惩罚，允许较多违反
- `λ = 1e6`：中等惩罚（推荐起点）
- `λ = 1e7`：重惩罚，接近硬约束行为

**调参方法**：
1. 从 `λ = 1e6` 开始
2. 运行优化，查看 `penalty share`（惩罚占比）
3. 如果惩罚占比 < 1%：增加 λ
4. 如果惩罚占比 > 10%：减少 λ
5. 目标：惩罚占比在 1-5% 之间

### κ (kappa) 的选择

**作用**：控制 softplus 的锐度

- `κ = 10`：很平滑（sigmoid-like）
- `κ = 50`：默认值（推荐）
- `κ = 100`：更锐利（接近线性）

**建议**：保持默认 `κ = 50`，除非有特殊需求

---

## 📊 实际工作流程

### 完整优化流程

#### 步骤 1: 无约束基线
```bash
# 先运行无约束优化，了解系统能力
julia src/optim_inject.jl --idx_num 128 --niterations 20
```

#### 步骤 2: 软约束探索
```bash
# 使用软约束，找到大致最优解
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --lambda_cvar 1e6 \
    --niterations 20
```

**检查**：
- 查看最终的 POF 和 CVaR 值
- 如果接近阈值，说明 λ 设置合适
- 如果远小于阈值，可以减小 λ 或增加注入速率

#### 步骤 3: 校准 (eps, gamma)
```bash
# 如果同时使用 POF 和 CVaR，校准 gamma
julia src/threshold_sensitivity.jl \
    --idx_num 128 \
    --threshold_min 4.0 --threshold_max 4.0 --threshold_num 1 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --alpha 0.05 --lambda_cvar 1e6 \
    --calibrate_gamma
```

#### 步骤 4: 硬约束验证
```bash
# 用硬约束验证解是否满足要求
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --pof_as_constraint \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --cvar_as_constraint \
    --niterations 20
```

**如果硬约束优化失败**：
- 说明约束太严格
- 回到步骤 2，调整 `eps` 或 `gamma`
- 或者增加 `λ` 使软约束更严格

---

## ⚠️ 常见问题

### Q1: 软约束的 λ 应该多大？

**A**: 从 `1e6` 开始，根据惩罚占比调整：
- 惩罚占比 < 1% → 增加 λ
- 惩罚占比 > 10% → 减少 λ
- 目标：1-5%

### Q2: 硬约束优化失败怎么办？

**A**: 
1. 检查约束是否合理（`eps`/`gamma` 是否太严格）
2. 先用软约束找到可行解
3. 如果软约束下 POF/CVaR 远小于阈值，说明约束太严格
4. 调整 `eps`/`gamma` 或增加 `λ`

### Q3: 可以同时用硬约束和软约束吗？

**A**: 技术上可以，但不推荐：
- 硬约束已经保证满足，软约束是多余的
- 建议：探索用软约束，验证用硬约束

### Q4: 如何知道软约束是否足够严格？

**A**: 
1. 运行软约束优化
2. 检查最终 POF/CVaR 是否接近阈值
3. 如果接近（在 10% 以内），说明 λ 合适
4. 用硬约束验证，如果通过，说明软约束有效

---

## 📝 快速参考

### 软约束命令模板

```bash
# 基本软约束
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --lambda_pof 1e6 \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --lambda_cvar 1e6 \
    --niterations 20
```

### 硬约束命令模板

```bash
# 基本硬约束
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --pof_as_constraint \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --cvar_as_constraint \
    --niterations 20
```

### 混合使用（POF 硬约束 + CVaR 软约束）

```bash
julia src/optim_inject.jl \
    --idx_num 128 \
    --use_pof --eps_pof 0.01 --pof_as_constraint \
    --use_cvar --gamma_cvar 0.02 --alpha 0.05 --lambda_cvar 1e6 \
    --niterations 20
```

---

## 🎯 总结

**Softplus 的作用**：
- 替代不可微的 hinge 函数
- 提供平滑的梯度，优化更稳定
- 零基线确保满足约束时惩罚 ≈ 0

**选择建议**：
- **探索/敏感性分析** → 软约束
- **最终验证/合规** → 硬约束
- **参数调优** → 软约束 → 硬约束验证

**关键原则**：
- 软约束：灵活、易优化、可能轻微违反
- 硬约束：严格、难优化、保证满足

