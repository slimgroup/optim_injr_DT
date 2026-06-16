# Step Size 说明

在 `src/optim_inject.jl` 中有两种不同的"步长"概念，容易混淆：

## 1. 物理仿真时间步长 (Physical Simulation Time Step)

**参数**: `ds` 和 `dt_firstblock`

**位置**: `build_sim` 函数 (第 411-416 行)

```julia
function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_firstblock=80/ds)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    Sblk  = jutulModeling(model, dt_firstblock * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end
```

**说明**:
- `ds`: 控制每个注入周期内的子时间步数（默认 `ds=10`）
- `dt_firstblock = 80/ds`: 每个子时间步的物理时间长度（天）
  - 当 `ds=10` 时，`dt_firstblock = 8` 天
  - 当 `ds=1` 时，`dt_firstblock = 80` 天
- **总物理时间**: 每个 `Sblk` 调用总是模拟 80 天（`ds * dt_firstblock = ds * (80/ds) = 80`）

**影响**:
- 控制 reservoir simulation 的时间分辨率
- 更小的 `ds` 意味着更大的时间步长，但总模拟时间不变
- 测试表明：`ds` 对总仿真时间影响很小（约 18%），因为小时间步收敛更快

## 2. 优化算法步长 (Optimization Step Size)

**参数**: `ex_step_size`

**位置**: `main` 函数中的优化循环 (第 924-934 行)

```julia
ls = BackTracking(order=3, iterations=15)
step_arr = zeros(niterations)
if risk_opts.pof_as_constraint
    ex_step_size = 0.15
elseif risk_opts.cvar_as_constraint
    ex_step_size = 0.2
else
    ex_step_size = 0.2
end
```

**说明**:
- `ex_step_size`: 梯度下降算法中初始的步长（用于 line search）
- 用于更新注入速率：`inj_rate = proj(inj_rate + step * p)`
- 根据不同的风险约束模式，使用不同的初始步长：
  - PoF 约束：`0.15`
  - CVaR 约束：`0.2`
  - 其他情况：`0.2`

**影响**:
- 控制优化算法的收敛速度和稳定性
- 太小：收敛慢
- 太大：可能不收敛或震荡

## 总结

| 类型 | 参数 | 作用 | 影响范围 |
|------|------|------|----------|
| **物理时间步长** | `ds`, `dt_firstblock` | 控制 reservoir simulation 的时间分辨率 | 仿真精度和数值稳定性 |
| **优化步长** | `ex_step_size` | 控制梯度下降的步长 | 优化收敛速度和稳定性 |

**关键区别**:
- `ds` 影响的是**物理仿真**的时间步长
- `ex_step_size` 影响的是**优化算法**的步长
- 两者完全独立，互不影响

