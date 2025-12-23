# Gamma 计算方法说明

## ✅ 确认：CVaR的gamma从gamma table中获取

在 `submit_threshold_sensitivity_separate.sh` 中，CVaR-only cases使用：
- `--gamma_table_path`: 指定gamma table文件路径
- `--gamma_table_eps 0.01`: 指定从gamma table中查找eps=0.01对应的条目

代码流程（`threshold_sensitivity.jl` 第1425-1428行）：
```julia
entry = gamma_lookup_entry(table_data, gamma_table_eps_target, thresh)
gamma_overrides[thresh] = (gamma=entry.gamma, eps=entry.eps, source=resolved_path)
```

然后在优化时（第1682-1689行）：
```julia
override_entry = get(gamma_overrides, thresh, nothing)
gamma_override_val = override_entry === nothing ? nothing : override_entry.gamma
result = run_optimization_for_threshold(thresh, args; gamma_override=gamma_override_val, ...)
```

**确认：CVaR的gamma值确实是从gamma table中获取的！**

---

## 📊 Gamma的计算方法

### 核心思想

**Gamma是在POF≈eps时对应的CVaR值**

### 计算步骤（`calibrate_gamma_for_eps`函数）

1. **目标**：对于给定的threshold和eps（例如eps=0.01），找到对应的gamma值

2. **方法**：二分搜索找到使POF≈eps的注入速率
   ```julia
   # 二分搜索找到inj_rate，使得POF ≈ eps_target
   function evaluate_pof(inj_rate_val)
       # 运行一次前向模拟
       pof_hard, cvar, pof_smooth = objective(...)
       return pof_hard, cvar, pof_smooth
   end
   ```

3. **计算gamma**：
   - 在找到的注入速率下运行前向模拟
   - 计算此时的POF和CVaR
   - **gamma = 此时的CVaR值**
   - 返回：`suggested_gamma = cvar`

### 具体流程

```
对于每个(threshold, eps)对：
  1. 初始化注入速率范围 [inj_low, inj_high]
  
  2. 二分搜索：
     while |POF - eps| > tolerance:
         inj_mid = (inj_low + inj_high) / 2
         运行前向模拟，计算 POF 和 CVaR
         if POF > eps:
             inj_high = inj_mid  # 降低注入速率
         else:
             inj_low = inj_mid   # 提高注入速率
     
  3. 当 POF ≈ eps 时：
     gamma = 此时的CVaR值
     保存到gamma table: (threshold, eps) → gamma
```

### 数学关系

- **POF (Probability of Failure)**: 
  - POF = Σ w[i] where r[i] < 0
  - 表示违反概率（相对压力为负的概率）

- **CVaR (Conditional Value at Risk)**:
  - CVaR = E[L | L >= Q_α]
  - 其中 L = max(0, -r) 是损失
  - 表示在尾部α水平下的条件期望损失

- **对应关系**:
  - 当POF = eps时，计算此时的CVaR值
  - 这个CVaR值就是对应的gamma值
  - **gamma = CVaR | POF=eps**

---

## 🔗 POF和CVaR的对应关系

### 在gamma table生成时

对于每个threshold：
- 找到使POF≈0.01的注入速率
- 计算此时的CVaR值
- 保存：`(threshold=2.0, eps=0.01) → gamma=0.00287`

### 在threshold sensitivity分析时

**POF-only cases**:
- 使用 `eps_pof = 0.01`
- 约束：POF ≤ 0.01

**CVaR-only cases**:
- 使用 `gamma_table_eps = 0.01` 从gamma table查找
- 获取对应的gamma值（例如threshold=2.0时，gamma=0.00287）
- 约束：CVaR ≤ gamma

**对应关系**：
- POF-only的eps = 0.01
- CVaR-only的gamma = gamma_table中eps=0.01对应的值
- **两者对应到相同的风险水平**（POF≈0.01时的CVaR值）

---

## 📝 示例

假设threshold=2.0 MPa：

1. **生成gamma table时**：
   - 二分搜索找到：inj_rate=0.0453时，POF≈0.01
   - 此时计算CVaR = 0.00287
   - 保存：`(threshold=2.0, eps=0.01) → gamma=0.00287`

2. **运行POF-only优化时**：
   - 使用 `eps_pof = 0.01`
   - 约束：POF ≤ 0.01

3. **运行CVaR-only优化时**：
   - 从gamma table查找：`(threshold=2.0, eps=0.01) → gamma=0.00287`
   - 约束：CVaR ≤ 0.00287

**结果**：两者都对应到POF≈0.01的风险水平，因此可以公平对比！

