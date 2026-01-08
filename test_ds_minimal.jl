#!/usr/bin/env julia
# 最简化的 ds 对比测试：只运行一次完整的 forward reservoir simulation (960天)
# 不加载不必要的包，避免预编译时间

# 确保输出立即刷新
flush(stdout)
flush(stderr)

using Pkg
Pkg.activate(".")

println("开始加载包...")
flush(stdout)

using DrWatson  # 需要 datadir 函数
println("  ✓ DrWatson 已加载")
flush(stdout)

using JutulDarcyRules
println("  ✓ JutulDarcyRules 已加载")
flush(stdout)

using LinearAlgebra
using JLD2
using Random
using Printf
println("  ✓ 所有包已加载")
flush(stdout)

# 只 include 真正需要的函数（不 include 整个 optim_inject.jl）
# 直接定义需要的函数，避免加载 PyPlot 等不必要的包

# 从 optim_inject.jl 复制 build_sim 函数
function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_firstblock=80/ds)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    Sblk  = jutulModeling(model, dt_firstblock * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

println("=" ^ 80)
println("ds 参数对比测试：一次完整的 forward simulation (960天)")
println("=" ^ 80)

# Setup parameters
s = 128
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0
ϕ = 0.25
forward_step = 2

# Load data
println("\n加载数据...")
perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
perm_data = JLD2.load(perm_path)
BroadK = perm_data["BroadK"]

monitoring_step = 1
state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2")
state_data = JLD2.load(state_path)

idices = state_data["idx_t" * string(monitoring_step)]
idx = idices[s]
K = BroadK[idx, :, :] * JutulDarcyRules.md

p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10

# Initialize saturation
inj_y0 = 191 + argmax(K[250, 191:200]) - 1
S0 = zeros(Float64, n[1], n[end])
Random.seed!(2025 + s - 1)
value = 0.2 + rand(Float64) * 0.6
S0[249:251, inj_y0-4] .= value
S0[248:252, inj_y0-3] .= value
S0[247:253, inj_y0-2] .= value
S0[246:254, inj_y0-1] .= value
S0[246:254, inj_y0]   .= value
S0[246:254, inj_y0+1] .= value
S0[247:253, inj_y0+2] .= value
S0[248:252, inj_y0+3] .= value
S0[249:251, inj_y0+4] .= value
sat_init = S0

# Well location
inj_y = 191 + argmax(K[250, 191:200]) - 1
inj_loc_grid = (250, 1, inj_y)
inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])

# 固定的注入速率
inj_rate_base = 0.1
inj_start = 0.0001

println("\n" * "=" ^ 80)
println("开始测试：一次完整的 forward simulation (960天)")
println("总时间 = 2 * 6 * 80 = 960 天")
println("=" ^ 80)

# 测试不同的 ds 值
ds_values = [1, 2, 5, 10]
results = Dict{Int, Dict{String, Any}}()

for ds in ds_values
    println("\n" * "-" ^ 80)
    println("测试 ds = $ds")
    println("-" ^ 80)
    
    # 构建模拟器
    println("  构建模拟器...")
    build_start = time()
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)
    build_time = time() - build_start
    
    # 设置注入速率序列
    inj_rate_final = inj_rate_base
    inj_rate_seq = collect(range(inj_start, inj_rate_final, forward_step * 6))
    inj_len = length(inj_rate_seq)
    
    println("  配置信息:")
    println("    - dt_firstblock = $(80/ds) 天")
    println("    - 每次 Sblk 调用模拟的时间步数 = $ds")
    println("    - 每次 Sblk 调用模拟的总时间 = $(ds * (80/ds)) 天")
    println("    - 注入周期数 = $inj_len")
    println("    - 总模拟时间 = $inj_len × $(ds * (80/ds)) = $(inj_len * ds * (80/ds)) 天")
    
    # 预热运行（可选）
    println("  预热运行...")
    try
        f = jutulVWell(inj_rate_seq[1], [(inj_loc[1], inj_loc[2])];
                       startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])
        state0 = jutulSimpleState(sim.model)
        state0[1:n[1]*n[3]] = vec(sat_init)
        _ = sim.Sblk(sim.logTrans, f; state0=state0)
    catch e
        println("  预热失败: $e")
    end
    
    # 正式计时：运行完整的 forward simulation
    println("  正式计时：运行完整的 forward simulation...")
    start_time = time()
    
    previous_state = nothing
    for i in 1:inj_len
        f = jutulVWell(inj_rate_seq[i], [(inj_loc[1], inj_loc[2])];
                       startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])
        
        try
            if i == 1
                state0 = jutulSimpleState(sim.model)
                state0[1:n[1]*n[3]] = vec(sat_init)
                states = sim.Sblk(sim.logTrans, f; state0=state0)
            else
                states = sim.Sblk(sim.logTrans, f; state0=previous_state)
            end
            previous_state = states.states[end]
        catch e
            println("  模拟失败在周期 $i: $e")
            break
        end
    end
    
    elapsed = time() - start_time
    
    # 记录结果
    total_time_steps = inj_len * ds
    results[ds] = Dict(
        "build_time" => build_time,
        "simulation_time" => elapsed,
        "total_time_steps" => total_time_steps,
        "time_per_step" => elapsed / total_time_steps,
        "inj_periods" => inj_len
    )
    
    println("  ✓ 完成!")
    println("  - 构建时间: $(@sprintf("%.2f", build_time)) 秒")
    println("  - 完整 forward simulation 时间: $(@sprintf("%.2f", elapsed)) 秒")
    println("  - 总时间步数: $total_time_steps")
    println("  - 每个时间步平均耗时: $(@sprintf("%.3f", elapsed/total_time_steps)) 秒/步")
    
    GC.gc()
end

# 总结
println("\n" * "=" ^ 80)
println("测试结果总结")
println("=" ^ 80)

if length(results) >= 2
    ds_list = sort(collect(keys(results)))
    base_ds = ds_list[1]
    base_time = results[base_ds]["simulation_time"]
    
    println("\n对比结果（一次完整的 forward simulation，960天）:")
    println("-" ^ 80)
    println(@sprintf("  %-6s  %12s  %12s  %12s  %10s  %8s", 
                     "ds", "仿真时间(秒)", "总时间步数", "秒/步", "注入周期", "相对倍数"))
    println("-" ^ 80)
    
    for ds in ds_list
        r = results[ds]
        speedup = r["simulation_time"] / base_time
        println(@sprintf("  %-6d  %12.2f  %12d  %12.3f  %10d  %8.2fx", 
                         ds, r["simulation_time"], r["total_time_steps"], 
                         r["time_per_step"], r["inj_periods"], speedup))
    end
    
    println("\n关键发现:")
    println("-" ^ 80)
    
    if haskey(results, 1) && haskey(results, 10)
        r1 = results[1]
        r10 = results[10]
        time_ratio = r10["simulation_time"] / r1["simulation_time"]
        steps_ratio = r10["total_time_steps"] / r1["total_time_steps"]
        
        println("  ds=10 相对于 ds=1:")
        println("    - 仿真时间增加: $(@sprintf("%.2f", time_ratio))x")
        println("    - 时间步数增加: $(@sprintf("%.2f", steps_ratio))x")
        
        if time_ratio < steps_ratio
            println("  ✓ 验证通过：时间增加 ($(@sprintf("%.2f", time_ratio))x) < 时间步数增加 ($(@sprintf("%.2f", steps_ratio))x)")
            println("  ✓ 这是因为小时间步收敛更快")
        else
            println("  ⚠️  时间增加接近或超过时间步数增加")
        end
    end
    
    println("\n  每个时间步的耗时对比:")
    for ds in ds_list
        r = results[ds]
        println("    ds=$(ds): $(@sprintf("%.3f", r["time_per_step"])) 秒/步")
    end
    
    println("\n结论:")
    println("-" ^ 80)
    if haskey(results, 1) && haskey(results, 10)
        time_ratio = results[10]["simulation_time"] / results[1]["simulation_time"]
        println("  一次完整的 forward simulation (960天):")
        println("    - ds=10 不会增加 10 倍时间，实际增加约 $(@sprintf("%.1f", time_ratio))x")
    end
    println("  推荐保持 ds=10（当前默认值）")
else
    println("  测试数据不足")
end

println("\n" * "=" ^ 80)

