# Solver 的约束处理：soft penalty 与 hard constraint

核对日期：2026-10-02。本文依据当前 `src/optim_inject.jl` 和提交脚本整理，解释实际实现；没有重新运行优化，也没有修改 solver。

**当前 solver 使用有限差分梯度下降、非负投影和回溯线搜索。hard constraint 决定候选解是否可接受，soft penalty 决定可接受范围内如何权衡注入收益与风险。常用的 PoF / CVaR 提交配置同时开启两者。**

| 概念 | 实际作用 |
|---|---|
| hard constraint | 未平滑的风险指标超过阈值时，目标返回 `Inf`，供线搜索拒绝该候选点 |
| soft penalty | 把平滑风险指标加入目标函数，用有限权重与注入收益进行权衡 |
| `--cvar_soft` | 平滑用于 penalty 的 CVaR 内部计算；不关闭 hard constraint |
| `proj(x) = max.(x, 0)` | 将优化的注入率终点投影到非负范围 |

## 1. 优化变量与基础目标

当前直接优化的是一个标量，即注入计划终点 $q$。`inj_start` 固定，代码生成长度为 12 的线性注入计划：

$$
q_i(q)=q_{\mathrm{start}}+\frac{i-1}{11}(q-q_{\mathrm{start}}),
\qquad i=1,\ldots,12.
$$

这 12 个值不是独立优化变量。每次评估候选终点，都要生成整条计划并运行 forward simulation。当前每段模拟 80 天，每段输出 10 个子时间步；风险统计使用全部 120 个预测输出，总预测时长为 960 天。

基础目标是注入 CO₂ 质量的负值：

$$
J_{\mathrm{base}}(q)=-M_{\mathrm{CO_2}}(q).
$$

最小化这个目标会倾向于增加注入量；风险 penalty 和 hard constraint 限制这种增加。

统计分析中使用的长度为 12 的计划第 6 个元素为 $q_6=q_{\mathrm{start}}+5(q-q_{\mathrm{start}})/11$。固定 `inj_start` 后，它与终点存在一一对应关系，不是独立的信息；也不能把终点直接当成第 6 个元素。

代码位置：[计划与质量目标](../../src/optim_inject.jl#L448)、[预测时间设置](../../src/optim_inject.jl#L671)。

## 2. 从压力场构造风险

压力阈值是静水压力加 4 MPa：

$$
p_{\max}(x)=p_{\mathrm{hyd}}(x)+4\,\mathrm{MPa}.
$$

常用参数 `--risk_mode relative` 对应相对安全余量：

$$
r(x,t)=\frac{p_{\max}(x)-p(x,t)}{p_{\max}(x)}.
$$

- $r>0$：压力低于阈值。
- $r=0$：压力达到阈值。
- $r<0$：发生超压。

`--weight_mode voltime` 按网格体积与时间长度加权，并归一化为 $\sum_i w_i=1$。下文的 $i$ 表示空间单元与预测时间的组合。

**单次优化的 PoF / CVaR 是当前地质样本的空间—时间统计，不是直接在 posterior 样本之间计算的破裂概率。** 后续跨样本的最优注入率 CDF / bootstrap 分析属于另一层统计，不能直接与这里的 `eps_pof` 或 `alpha` 混同。

代码位置：[压力阈值](../../src/optim_inject.jl#L636)、[风险分布及权重](../../src/optim_inject.jl#L295)。

## 3. PoF：hard 检查与 soft penalty 使用不同指标

未平滑的 PoF 是超压的空间—时间加权比例：

$$
P_{\mathrm{hard}}(q)=\sum_i w_i\,\mathbf{1}[r_i(q)<0].
$$

平滑版本用 sigmoid 替代指示函数：

$$
P_{\mathrm{smooth}}(q)=\sum_iw_i\,\sigma\!\left(-\frac{r_i(q)}{\tau}\right),
\qquad \sigma(z)=\frac{1}{1+e^{-z}}.
$$

| 变量 | 用途 |
|---|---|
| `pof_hard_hat` | 与 `eps_pof` 比较，决定 hard constraint 是否满足 |
| `pof_smooth_hat` | 进入 PoF 的 soft penalty |

`tau_pof` 控制指示函数的平滑宽度。较小的正 $\tau$ 使其更接近硬指示函数，但变化更陡。

例如，某单元恰好达到阈值时，hard 指示值是 0，因为判断条件是严格的 `r < 0`；smooth 指示值是 0.5。即使所有单元都没有超压，smooth PoF 仍然可能大于零，甚至超过 `eps_pof`。

**所以，hard PoF 满足约束而 soft PoF 产生正 penalty，是代码允许的正常情况。**

代码位置：[PoF 指标](../../src/optim_inject.jl#L344)。

## 4. CVaR：约束最差尾部的超压严重程度

CVaR 的输入是非负超压损失：

$$
L_i=\max(0,-r_i)
=\max\!\left(0,\frac{p_i-p_{\max,i}}{p_{\max,i}}\right).
$$

`alpha` 表示最差尾部的权重占比。`alpha=0.01` 表示最差的 1%，不是 1% 置信水平。

| 变量 | 计算方法与用途 |
|---|---|
| `cvar_eval` | 损失从大到小排序，取权重恰好为 $\alpha$ 的尾部平均值；用于 hard 检查和结果记录 |
| `cvar_smooth` | 用 RU 形式进行可选的平滑计算；用于 soft penalty |

RU 形式对应：

$$
C_\alpha(L)=\min_\eta\left[\eta+\frac{1}{\alpha}\sum_iw_i\max(0,L_i-\eta)\right].
$$

开启 `--cvar_soft` 后，RU 内部的 `max(0, L_i - η)` 使用 softplus 近似；关闭时使用原来的 hinge。**无论这个开关是否开启，hard 检查都使用 `cvar_clean` 返回的 `cvar_eval`。**

例如 `--alpha 0.01 --gamma_cvar 0.1` 表示最差 1% 空间—时间尾部的平均相对超压量不超过 0.1。这里的 0.1 是超压严重程度，不是破裂概率，也不是每个单元都必须遵守的局部上限。

实现上，两个 CVaR 函数将 $\alpha$ 限制到 $[10^{-6},0.9999]$；因此传入 `--alpha 0` 实际使用的是 $10^{-6}$ 尾部，不能直接解释为代码显式计算了全局最大损失。

代码位置：[严格尾部与 RU 计算](../../src/optim_inject.jl#L361)、[损失构造及指标调用](../../src/optim_inject.jl#L530)。

## 5. hard 与 soft 如何组成同一个目标

hard 检查的核心逻辑是：

```julia
if use_pof && pof_as_constraint && pof_hard > ε + 1e-12
    return Inf
end
if use_cvar && cvar_as_constraint && cvar_eval > γ + 1e-12
    return Inf
end
```

检查通过后，再计算 soft penalty。阈值附近的 softplus 为：

$$
s_\kappa(z)=\frac{\log(1+e^{\kappa z})}{\kappa}.
$$

两个 penalty 分别为：

$$
B_{\mathrm{PoF}}=\lambda_{\mathrm{PoF}}
\left[s_{\kappa_{\mathrm{PoF}}}(P_{\mathrm{smooth}}-\varepsilon)-s_{\kappa_{\mathrm{PoF}}}(0)\right],
$$

$$
B_{\mathrm{CVaR}}=\lambda_{\mathrm{CVaR}}
\left[s_{\kappa_{\mathrm{CVaR}}}(C_{\mathrm{smooth}}-\gamma)-s_{\kappa_{\mathrm{CVaR}}}(0)\right].
$$

只累加对应 `use_*` 开启的项。整个目标为：

$$
J(q)=\begin{cases}
+\infty, & \text{违反任一已启用的 hard constraint},\\
-M_{\mathrm{CO_2}}(q)+B_{\mathrm{PoF}}(q)+B_{\mathrm{CVaR}}(q), & \text{通过 hard 检查}.
\end{cases}
$$

模拟失败也可能返回 `Inf`，所以日志中的 `Inf` 不足以单独证明是风险超限。

**hard 限定可接受范围，soft 改变范围内的目标排序。** 两者同时开启时，`lambda` 仍然影响搜索及最终结果；更强的风险权重可能使解停在风险阈值以内。固定的 `lambda` 不会在迭代中自动更新，日志中的 `lambda suggestion` 仅打印建议。

`eps_pof=0.01` 的 hard constraint 允许最多约 1% 的空间—时间加权超压比例；“hard”并不等于所有单元都禁止超压。只有零风险阈值才对应更严格的要求，且检查仍受离散输出与数值容差限制。

代码位置：[hard 检查和 soft penalty](../../src/optim_inject.jl#L535)、[lambda 建议](../../src/optim_inject.jl#L779)。

## 6. zero-baseline 的真实含义

**zero-baseline 只保证平滑指标等于阈值时 penalty 为零；阈值以下的 penalty 实际为负。**

令 $z=\text{平滑指标}-\text{阈值}$，当 $\kappa=50$ 时：

| $z$ | $s_{50}(z)-s_{50}(0)$，尚未乘 $\lambda$ |
|---:|---:|
| -0.01 | -0.0043814 |
| 0 | 0 |
| +0.01 | +0.0056186 |

在最小化问题中，较低风险得到较低目标值。减去 $s_\kappa(0)$ 本身只是常数平移，不改变梯度或最优解。

未触发内部截断时：

$$
\frac{dB}{dz}=\lambda\sigma(\kappa z).
$$

在阈值处斜率是 $\lambda/2$。因此 penalty 数值为零，或者占基础目标的比例较小，都不意味着它对梯度影响很小。

代码的 `softplus` 实际先执行 `clamp(κ*x, -50, 50)`。上述通常的 softplus 公式适用于未触发截断的范围；对非常大的正输入，当前实现会饱和，不能按标准 softplus 的线性增长外推。

代码位置：[softplus 实现](../../src/optim_inject.jl#L196)。

## 7. 开关组合与当前常用配置

下表对 PoF / CVaR 分别适用：

| `use_*` | `*_as_constraint` | `lambda_*` | 对该风险指标的处理 |
|---|---|---:|---|
| 关闭 | 任意 | 任意 | 不参与目标或硬检查 |
| 开启 | 关闭 | $>0$ | 只有 soft penalty，可用收益换取风险超限 |
| 开启 | 开启 | 0 | 只有 hard constraint |
| 开启 | 开启 | $>0$ | hard constraint 与 soft penalty 同时生效 |
| 开启 | 关闭 | 0 | 不限制优化 |

`--cvar_soft` 单独控制 CVaR 内部平滑。关闭它不会自动移除外层 CVaR softplus penalty。`lambda_pof` 与 `lambda_cvar` 的 CLI 默认值均为 0；只写 `--use_*` 并不会自动赋予非零 penalty 权重。

当前 step-4 提交脚本的主要风险参数如下；这些是参数片段，不是独立的作业提交命令：

```text
PoF:
--use_pof --pof_as_constraint
--lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50
--eps_pof 0.0 或 0.01
--risk_mode relative --weight_mode voltime

CVaR:
--use_cvar --cvar_as_constraint --cvar_soft
--lambda_cvar 3.0e9 --kappa_cvar 50
--gamma_cvar 0.1 --alpha 0.01
--risk_mode relative --weight_mode voltime
```

所以这些 case 均同时启用 hard 与 soft。目录名 `HARD` 仅表示开启硬检查；`cvarsoft` 表示 CVaR 内部采用平滑，两者同时出现是正常的。

| 参数 | 控制内容 |
|---|---|
| `eps_pof` | PoF 阈值 |
| `gamma_cvar` | CVaR 阈值 |
| `alpha` | CVaR 最差尾部占比 |
| `tau_pof` | PoF 指示函数的平滑宽度 |
| `kappa_pof` | PoF 外层 penalty 的过渡锐度 |
| `kappa_cvar` | CVaR 外层 penalty 的锐度，以及开启 `cvar_soft` 时内部平滑的锐度 |
| `lambda_*` | 风险项相对注入收益的权重 |

代码位置：[step-4 配置](../../scripts/shell/submit/submit_step4_paired_all.sh#L39)、[风险选项](../../src/optim_case_config.jl#L120)、[目录命名](../../src/optim_output_paths.jl#L5)。

## 8. 一次优化更新如何执行

1. **找到初始可行点。** 首次目标为 `Inf` 时，将优化终点乘以 0.8 后重试，直到得到有限值；终点达到 `0.0001` 仍失败则报错。固定的 `inj_start` 不随之缩小，所以这不是把整条计划按比例缩小。
2. **有限差分求梯度。** CLI 默认中心差分，扰动 $\delta=10^{-8}$。常用 batch 脚本指定 `--grad_forward`，实际使用前向差分。差分调用完整目标，包含 hard 检查和 soft penalty。
3. **形成搜索方向。** $d=-g/\lVert g\rVert_\infty$。当前只有一个标量，有限非零梯度对应方向 $+1$ 或 $-1$。
4. **投影候选点。** $q_{\mathrm{trial}}=\max(0,q+a d)$。投影只保证终点非负，没有注入率上界；`inj_guess` 是初值，不是强制上界。
5. **回溯选择步长。** 试探点目标非有限时，正常路径先减半步长寻找有限值；随后检查充分下降条件，不满足则继续缩步。
6. **接受更新并检查停止条件。** 记录新目标和风险，重新求梯度；达到迭代上限、梯度恰好为零、步长过小或失败分支时停止。

两种有限差分分别为：

$$
g_{\mathrm{central}}\approx\frac{J(q+\delta)-J(q-\delta)}{2\delta},
\qquad
g_{\mathrm{forward}}\approx\frac{J(q+\delta)-J(q)}{\delta}.
$$

正常线搜索检查 Armijo 条件：

$$
J(q_{\mathrm{trial}})\leq J(q)+c_1a\,g^{\mathsf T}d,
\qquad c_1=10^{-4}.
$$

主循环使用 `BackTracking(order=3, iterations=15)`。PoF hard case 的首次搜索步长是 0.15，其余通常是 0.2；后续使用上次接受的步长作为初始试探。`iterations=15` 限制充分下降阶段的回溯迭代；依赖库最初寻找有限目标值的减半循环另有计数。

例如，当前终点为 0.05，沿增加注入方向试探到 0.07。若 hard PoF 超限，目标返回 `Inf`；缩步到 0.06 后即使通过硬检查，也要看增加的注入收益能否抵消 soft penalty，并满足充分下降条件，才会正常接受。

代码位置：[可行初值](../../src/optim_inject.jl#L732)、[差分梯度](../../src/optim_inject.jl#L576)、[主迭代](../../src/optim_inject.jl#L860)、[batch 参数](../../scripts/shell/run/optim_inject_pace.sh#L55)。回溯内部行为核对了当前 Manifest 对应的本地 `LineSearches 7.4.1/src/backtracking.jl`。

## 9. 实现限制与结果解读

以下是从当前代码确认的处理边界，不表示每次运行都会触发这些情况。

- **硬边界附近的差分可能非有限。** 当前点可行而 $q+\delta$ 不可行时，差分可能得到 `Inf`，归一化方向随后可能出现 `NaN`。梯度函数没有可行侧差分或自适应缩小差分扰动的专门处理。
- **线搜索异常兜底不检查充分下降。** 异常后尝试固定步长 `0.001`，仅检查目标是否有限。因此不能声称所有被接受的迭代都满足 Armijo 条件或目标单调下降。
- **`cvar_soft` 不代表整个目标全局光滑。** 损失 $L=\max(0,-r)$ 仍有折点；全部损失为零时 RU 函数直接返回零；外层 hard 检查还引入了 `Inf` 边界。
- **停止规则不提供“95% 正确率”证明。** 活跃的步长判断为 $a < [(q+q_{\mathrm{start}})/2]\,(0.05/0.95)$。这是实现中的停止规则；相关注释不足以证明最优性或概率保证。目标相对变化与小梯度阈值的补充判断在当前代码中仍被注释掉。
- **当前 BHP 上限仅用于记录和画图。** `BHP_max` 没有进入这套 PoF / CVaR 的目标或可行性判断；约束依据是储层压力风险。
- **硬检查的范围是模拟与离散风险指标。** 它不等于对连续空间—时间、所有 posterior 样本或真实地层风险的无条件保证。

代码位置：[异常兜底](../../src/optim_inject.jl#L887)、[停止条件](../../src/optim_inject.jl#L1013)、[BHP 用途](../../src/optim_inject.jl#L689)。

## 10. 查看输出时应该对照什么

| 输出字段 | 含义 | 检查方法 |
|---|---|---|
| `pof_hard_iter` | 未平滑 PoF | PoF hard 开启时，与 $\varepsilon+10^{-12}$ 比较 |
| `pof_iter` | 平滑 PoF | 用于理解 penalty，不能替代 hard 指标 |
| `cvar_iter` | 严格尾部计算的 `cvar_eval` | CVaR hard 开启时，与 $\gamma+10^{-12}$ 比较 |
| `pen_pof_arr` / `pen_cvar_arr` | 各 penalty 的历史 | 可以为负；结合风险指标、权重与基础目标理解 |
| `obj_base_arr` | 负注入质量 | 越负对应注入质量越大 |
| `obj_arr_niter` | 包含 penalty 的总目标 | 与基础目标区分，不能直接解释为注入质量 |
| `meta.risk_opts` | 保存的实际风险配置 | 核对开关、阈值、权重及平滑参数 |

只取实际完成迭代的记录；提前终止时，预分配数组的尾部可能仍然是 0 或 `NaN`。日志中的 `penalty share` 使用有符号的总目标作分母，而 penalty-share 图使用基础目标绝对值作分母，两者也不能直接当作相同的百分比。

代码位置：[指标记录](../../src/optim_inject.jl#L919)、[final 保存字段](../../src/optim_inject.jl#L1019)、[penalty-share 图](../../src/optim_inject.jl#L1040)。

## 11. 按优化目的选择 setup

三种模式都可以通过现有 CLI 配置，无需修改目标函数。`use_pof` / `use_cvar` 是对应风险指标的总开关；关闭它也会关闭该指标的 hard 检查。**要关闭 soft penalty，应设置 `lambda_* = 0`，同时保留 `use_*`；要关闭 hard，应移除 `*_as_constraint`。**

| 希望实现的目标 | 对应模式 | 需要理解的结果 |
|---|---|---|
| 在满足指定风险阈值的方案中，尽量增加注入质量 | hard-only | 可行点按注入质量排序，风险不再额外参与目标排序 |
| 允许违反风险阈值，以权衡注入收益和风险 | soft-only | 阈值是 penalty 的参考位置，不保证最终满足该阈值 |
| 满足风险阈值，同时进一步偏好低风险方案 | hard + soft | 在可行范围内继续权衡风险，可能牺牲部分注入量 |

这里的 hard-only 与最大注入量的约束优化目标一致，但当前有限差分和回溯实现并不因此获得全局最优性保证。边界附近的非有限梯度问题仍见第 9 节。

下面是传给 `src/optim_inject.jl` 的风险参数片段，可用于提交脚本中的 `RISK_ARGS` / `risk_args`。`monitoring_step`、`case_key`、`prior_mode`、样本和 case-level `inj_start` 仍按原实验设置保持一致。实际优化应通过 `sbatch` 或 `salloc` 运行。

PoF 示例固定 `eps_pof=0.01`。如果要求离散检查中不允许超压，则使用 `eps_pof=0.0` 并选择匹配的 case；改变 case 后，先验和起始注入率也应按该 case 的既定配置处理。

```text
# PoF：hard-only
--use_pof --eps_pof 0.01 --pof_as_constraint --lambda_pof 0
--tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime

# PoF：soft-only（参数中不出现 --pof_as_constraint）
--use_pof --eps_pof 0.01 --lambda_pof 8.5e8
--tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime

# PoF：hard + soft
--use_pof --eps_pof 0.01 --pof_as_constraint --lambda_pof 8.5e8
--tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime
```

CVaR 示例固定 `alpha=0.01`、`gamma_cvar=0.1`，即现有主要 CVaR case：

```text
# CVaR：hard-only
--use_cvar --alpha 0.01 --gamma_cvar 0.1 --cvar_as_constraint --lambda_cvar 0
--cvar_soft --kappa_cvar 50 --risk_mode relative --weight_mode voltime

# CVaR：soft-only（参数中不出现 --cvar_as_constraint）
--use_cvar --alpha 0.01 --gamma_cvar 0.1 --lambda_cvar 3.0e9
--cvar_soft --kappa_cvar 50 --risk_mode relative --weight_mode voltime

# CVaR：hard + soft
--use_cvar --alpha 0.01 --gamma_cvar 0.1 --cvar_as_constraint --lambda_cvar 3.0e9
--cvar_soft --kappa_cvar 50 --risk_mode relative --weight_mode voltime
```

hard-only 示例保留 `--cvar_soft`，是为了只改变 penalty 权重。有限的 CVaR penalty 计算结果乘以零后不参与目标；这个开关本身不启用 soft penalty。

这里的 `8.5e8` 和 `3.0e9` 是现有实验权重，不是对新实验自动校准的最优值。soft-only 中增大 `lambda` 通常会加强风险权衡，但不能替代 hard 检查，也不能承诺恰好满足阈值。

运行前需要核对两件具体事项：

- `*_as_constraint` 是存在即开启的布尔 flag。关闭时从完整参数列表中移除它，不写 `--pof_as_constraint false` 或 `--cvar_as_constraint false`；旧脚本中已拼入的 hard flag 也要移除。
- 当前输出目录名不包含 `lambda`。其他配置相同时，hard-only 与 hard + soft 会使用相同的 case/sample 目录；soft-only 的不同权重也会共用目录。正式做对比前需要隔离输出，避免混入既有实验。仅改变 shell 的 `CASE_TAG` 不会改变 Julia 的结果目录。

PoF 和 CVaR 也可分别选择处理模式；若同时开启两个 hard，候选解必须满足两者。对于 monitoring step 大于 1 的实验，同时启用两个指标时还需要明确 `case_key` 对应哪套先验和 case-level `inj_start`，不能把不同历史实验的状态来源自动混合。

## 12. 论文中如何区分这些数学问题

以下分类用于说明方法，不表示已运行了所有配置。令 $M(q)$ 为注入质量，$R(q)$ 为用于硬检查的未平滑风险指标，$\widetilde R(q)$ 为用于 penalty 的平滑风险指标，$b$ 为对应阈值。定义不含权重的 penalty：

$$
\Phi(q)=s_\kappa(\widetilde R(q)-b)-s_\kappa(0).
$$

对每一种风险指标，理论上有四种角色：

| 模式 | 数学问题 | 论文中的含义 |
|---|---|---|
| 不启用风险处理 | $\min_{q\geq0}-M(q)$ | 仅追求注入质量；当前代码没有注入率上界，不能默认这个问题有有限最优解 |
| soft-only | $\min_{q\geq0}[-M(q)+\lambda\Phi(q)]$，$\lambda>0$ | 风险惩罚优化，允许风险与收益权衡，阈值不是必须满足的可行性条件 |
| hard-only | $\min_{q\geq0}-M(q)$，满足 $R(q)\leq b$ | 风险约束下的最大注入量问题 |
| hard + soft | $\min_{q\geq0}[-M(q)+\lambda\Phi(q)]$，满足 $R(q)\leq b$，$\lambda>0$ | 同时包含硬风险限制和风险惩罚的约束优化 |

上述公式省略代码中 $10^{-12}$ 的可行性容差。若完全关闭两种风险，当前入口的 `case_key=auto` 也不能推断实验 case；这不是现有主要提交配置。

对 PoF，$R=P_{\mathrm{hard}}$、$\widetilde R=P_{\mathrm{smooth}}$、$b=\varepsilon$。对 CVaR，$R=C_{\mathrm{eval}}$、$\widetilde R=C_{\mathrm{smooth}}$、$b=\gamma$。PoF 和 CVaR 各自可选上述四种角色，目标函数与约束层面共有 $4\times4=16$ 种角色组合；这不表示仓库已经为全部组合提供独立的历史先验和 batch 实验配置。

论文需要明确以下区别：

- **hard + soft 定义了带风险惩罚的目标。** 它与 hard-only 通常是不同的优化问题。即使两个问题的可行集相同，也不能默认它们有相同最优解。
- **平滑指标和软约束不是同一个概念。** `cvar_soft` 只切换内部计算；真正启用 soft 风险项还需要 `use_cvar=true` 且 `lambda_cvar>0`。hard 可行性判断继续使用未平滑指标。
- **权重固定时，soft penalty 不是只用于梯度计算的辅助项。** 它同时出现在有限差分、线搜索目标比较与最终目标中。当前代码没有将 penalty 权重逐步降到零、再求解 hard-only 问题的阶段。
- **优化问题与数值求解方法应分别描述。** 问题按上表定义；求解方法是有限差分梯度、非负投影和回溯线搜索，硬约束通过对不可行试探点返回 `Inf` 处理。其数值限制见第 9 节，不能据此声称全局最优或“95% 正确率”。

因此，对于当前同时设置 `*_as_constraint` 和非零 `lambda_*` 的主要实验，方法部分应明确给出“负注入质量 + 风险 penalty”的目标，以及未平滑风险指标的硬约束。若论文只写“最大化注入质量，满足 PoF / CVaR 阈值”，就会遗漏实际参与优化的风险项。
