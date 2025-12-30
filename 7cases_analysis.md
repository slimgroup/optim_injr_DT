# 7个Missing Samples详细分析

## 1. 7个Samples的具体数值（可直接复制）

```
gamma=0.01, alpha=0.02, sample=64: Last nonzero=0.762500, Averaged=0.381300
gamma=0.01, alpha=0.05, sample=17: Last nonzero=0.145750, Averaged=0.072925
gamma=0.02, alpha=0.01, sample=64: Last nonzero=0.762500, Averaged=0.381300
gamma=0.05, alpha=0.02, sample=42: Last nonzero=0.336500, Averaged=0.168300
gamma=0.05, alpha=0.05, sample=1:  Last nonzero=0.299000, Averaged=0.149550
gamma=0.05, alpha=0.05, sample=21: Last nonzero=0.249000, Averaged=0.124550
gamma=0.05, alpha=0.05, sample=64: Last nonzero=1.301562, Averaged=0.650831
```

**表格格式：**

| Case | Sample | Last Nonzero (m³/s) | Averaged (m³/s) |
|------|--------|---------------------|-----------------|
| gamma=0.01, alpha=0.02 | 64 | 0.762500 | 0.381300 |
| gamma=0.01, alpha=0.05 | 17 | 0.145750 | 0.072925 |
| gamma=0.02, alpha=0.01 | 64 | 0.762500 | 0.381300 |
| gamma=0.05, alpha=0.02 | 42 | 0.336500 | 0.168300 |
| gamma=0.05, alpha=0.05 | 1 | 0.299000 | 0.149550 |
| gamma=0.05, alpha=0.05 | 21 | 0.249000 | 0.124550 |
| gamma=0.05, alpha=0.05 | 64 | 1.301562 | 0.650831 |

## 2. 失败原因详细分析

### 问题1: UndefVarError: stp not defined

**原始代码 (optim_inject.jl, lines 935-950):**
```julia
stp = ex_step_size
try
    stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
catch e
    # If line search fails completely, try a very small step
    println("Warning: line search failed at iteration $j: ", e)
    println("  Trying very small step size: 0.001")
    stp = 0.001
    obj = θ(stp)
    if !isfinite(obj) || obj == Inf
        println("  Small step also failed, breaking optimization")
        break
    end
end
ex_step_size = stp
```

**问题分析：**
1. **如果`ls()`抛出异常**：进入catch块，`stp`被设置为0.001
2. **但是`obj = θ(stp)`也可能抛出异常**：
   - 如果`θ(stp)`在catch块内部抛出异常（没有被内层try-catch捕获）
   - `break`语句可能不会执行
   - `stp`的值可能没有被正确设置
   - 或者在某些边缘情况下，`stp`的值可能未定义

3. **更严重的情况**：
   - 如果`θ(stp)`抛出异常，Julia会继续向上传播异常
   - 如果外层没有捕获，程序会崩溃
   - 即使有外层try-catch，`stp`的值可能处于不一致状态

**修复后的代码 (optim_inject_7cases_fix.jl, lines 935-961):**
```julia
# Initialize stp to avoid UndefVarError if ls() doesn't return properly
stp = ex_step_size
obj_valid = false
try
    stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
    obj_valid = isfinite(obj) && obj != Inf
catch e
    # If line search fails completely, try a very small step
    println("Warning: line search failed at iteration $j: ", e)
    println("  Trying very small step size: 0.001")
    stp = 0.001  # Ensure stp is always defined
    try
        obj = θ(stp)
        obj_valid = isfinite(obj) && obj != Inf
    catch e2
        println("  Small step evaluation also failed: ", e2)
        obj_valid = false
    end
end

# If objective is invalid, break the optimization loop
if !obj_valid
    println("  Optimization failed: unable to find valid step size, breaking")
    # Ensure stp is defined before break (for potential use after loop)
    stp = ex_step_size
    break
end

ex_step_size = stp
```

**修复的关键点：**
1. **初始化`stp`**：在try块之前就初始化`stp = ex_step_size`，确保`stp`总是有值
2. **引入`obj_valid`标志**：明确跟踪objective函数是否有效，而不是依赖隐式的异常处理
3. **嵌套try-catch**：内层try-catch专门捕获`θ(stp)`的异常，避免异常向上传播
4. **统一的错误处理**：无论哪个路径失败，都通过`obj_valid`标志统一处理
5. **break前再次确保stp有值**：在break之前再次设置`stp = ex_step_size`，确保即使break后使用stp也不会出错

**为什么原始代码会在某些情况下fail：**
- 当line search遇到数值问题时（比如梯度方向导致目标函数无法计算），`ls()`可能抛出`LineSearchException`
- 在catch块中尝试`θ(0.001)`时，如果这个步长仍然导致simulation失败，`θ()`可能抛出其他异常
- 原始代码没有内层try-catch，异常会继续向上传播，可能导致程序崩溃或`stp`未定义

### 问题2: final.jld2未保存

**原始代码 (optim_inject.jl, lines 1066-1084):**
```julia
# final
@tagsave(joinpath(out_root, "final.jld2"),
Dict(
    "inj_rate_arr"  => inj_rate_arr,
    ...
    );
safe=true)
```

**问题分析：**
1. **目录不存在**：`out_root`目录可能不存在，导致`@tagsave`失败
   - 虽然代码中有`mkpath(out_root)`（line 727），但可能在优化过程中目录被删除或清理
   - 或者在某些情况下`mkpath`失败但没有检查

2. **`@tagsave`失败但无提示**：
   - `safe=true`参数使得保存失败时不会抛出异常，而是静默失败
   - 没有错误日志，用户无法知道保存是否成功
   - 没有检查文件是否真的被创建

3. **磁盘空间或权限问题**：
   - 如果磁盘空间不足或没有写权限，`@tagsave`会失败但不会报告

**修复后的代码 (optim_inject_7cases_fix.jl, lines 1079-1112):**
```julia
# final
# Ensure directory exists before saving
if !isdir(out_root)
    println("Warning: out_root directory does not exist, creating: $out_root")
    mkpath(out_root)
end
final_path = joinpath(out_root, "final.jld2")
try
    @tagsave(final_path,
    Dict(
        "inj_rate_arr"  => inj_rate_arr,
        ...
        );
    safe=true)
    if isfile(final_path)
        println("✓ Successfully saved final.jld2 to: $final_path")
    else
        @warn "final.jld2 save may have failed: file does not exist after @tagsave" final_path
    end
catch e
    @error "Failed to save final.jld2" exception=(e, catch_backtrace()) final_path out_root
end
```

**修复的关键点：**
1. **显式检查目录**：在保存之前检查`out_root`是否存在，不存在则创建
2. **try-catch包装**：虽然`safe=true`应该防止异常，但添加try-catch可以捕获其他潜在问题
3. **验证文件存在**：保存后检查文件是否真的被创建，提供明确的成功/失败反馈
4. **详细的错误日志**：使用`@warn`和`@error`记录详细的错误信息，包括文件路径和异常堆栈

**为什么原始代码会fail：**
- 优化完成后，虽然代码执行到了保存步骤，但如果目录不存在或保存失败，没有错误提示
- 用户只能通过检查文件是否存在来判断是否成功，但原始代码没有这个检查
- 在某些情况下（比如网络文件系统的延迟、权限问题），`@tagsave`可能静默失败

## 3. Mean和Std的计算方法

**是的，是按照case分组计算的！**

代码位置：`scripts/julia_scripts/data_collection/collect_all_injection_rates.jl`

```julia
# Group statistics (OK samples only), single sample std=0.0
function group_stats(df::DataFrame)
    g = groupby(df, :case_tag)  # ← 按照case_tag分组
    combine(g,
        nrow => :count,
        :last_inj_rate => mean => :mean,  # ← 对每组计算mean
        :last_inj_rate => (v -> (length(v) > 1 ? std(v) : 0.0)) => :std,  # ← 对每组计算std
    )
end
```

**计算流程：**
1. **数据收集**：扫描所有case目录，读取每个sample的`final.jld2`，计算`last_nonzero_inj_rate`（与inj_start=0.0001平均）
2. **按case_tag分组**：使用`groupby(df, :case_tag)`将数据按照`case_tag`（即相同的gamma和alpha组合）分组
3. **每组统计**：
   - `count`：该组中成功完成的sample数量
   - `mean`：该组所有samples的averaged rate的平均值
   - `std`：该组所有samples的averaged rate的标准差（如果只有1个sample，std=0.0）

**示例：**
- `CVaR_g=0.05_a=0.05`组有61个成功samples
- 计算这61个samples的averaged rate的mean和std
- mean = 0.465198, std = 0.263584
- 正常范围 = mean ± 2*std = [-0.061971, 0.992366]

**重要说明：**
- 这7个missing samples之前**没有**被包含在统计中（因为它们之前没有final.jld2）
- 所以mean和std是基于**其他成功完成的samples**计算的
- 现在这7个samples完成了，如果重新运行`collect_all_injection_rates.jl`，统计数据会更新，包含这7个samples

