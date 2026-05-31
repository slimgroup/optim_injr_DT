#!/usr/bin/env julia
# 读取7个cases的最终injection rate

using Pkg
Pkg.activate(".")
using JLD2
using Statistics
using Printf

# 7个cases的路径
cases = [
    ("gamma=0.01, alpha=0.02, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("gamma=0.01, alpha=0.05, sample=17", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=17/final.jld2"),
    ("gamma=0.02, alpha=0.01, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.02__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("gamma=0.05, alpha=0.02, sample=42", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=42/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=1",  "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=1/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=21", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=21/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
]

println("=" ^ 80)
println("7个cases的injection rate分析 (m³/s)")
println("=" ^ 80)
println("逻辑: 取last nonzero injection rate，然后与inj_start(0.0001)取平均")
println("")

const INJ_START = 0.0001  # 第一个step的injection rate

# 读取last nonzero injection rate（参考collect_all_injection_rates.jl的逻辑）
function last_nonzero_inj_rate(inj_rate_arr)
    col1 = vec(inj_rate_arr[:, 1])  # 第一列
    clean = filter(x -> isfinite(x) && !isnan(x), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? INJ_START : clean[idx]
end

inj_rates_last = Float64[]  # last nonzero rates
inj_rates_avg = Float64[]   # averaged with inj_start
case_info = []

for (desc, path) in cases
    if isfile(path)
        data = JLD2.load(path)
        inj_rate_arr = data["inj_rate_arr"]
        
        # 取last nonzero injection rate
        last_nonzero = last_nonzero_inj_rate(inj_rate_arr)
        
        # 与inj_start取平均
        avg_rate = (last_nonzero + INJ_START) / 2.0
        
        push!(inj_rates_last, last_nonzero)
        push!(inj_rates_avg, avg_rate)
        push!(case_info, (desc, last_nonzero, avg_rate))
        
        println(@sprintf("%-50s:", desc))
        println(@sprintf("  Last nonzero: %.6f", last_nonzero))
        println(@sprintf("  Average (with inj_start=%.4f): %.6f", INJ_START, avg_rate))
    else
        println(@sprintf("%-50s: FILE NOT FOUND", desc))
    end
end

println("=" ^ 80)
println("统计信息 (Last nonzero rates):")
if length(inj_rates_last) > 0
    println(@sprintf("  最小值: %.6f", minimum(inj_rates_last)))
    println(@sprintf("  最大值: %.6f", maximum(inj_rates_last)))
    println(@sprintf("  平均值: %.6f", mean(inj_rates_last)))
    println(@sprintf("  中位数: %.6f", median(inj_rates_last)))
    println(@sprintf("  标准差: %.6f", std(inj_rates_last)))
end
println("")
println("统计信息 (Averaged rates with inj_start):")
if length(inj_rates_avg) > 0
    println(@sprintf("  最小值: %.6f", minimum(inj_rates_avg)))
    println(@sprintf("  最大值: %.6f", maximum(inj_rates_avg)))
    println(@sprintf("  平均值: %.6f", mean(inj_rates_avg)))
    println(@sprintf("  中位数: %.6f", median(inj_rates_avg)))
    println(@sprintf("  标准差: %.6f", std(inj_rates_avg)))
end
println("=" ^ 80)

# 判断是否在正常范围内
# 根据代码，inj_start=0.0001, inj_guess=0.25，正常范围应该在0.0001到0.25之间
println("\n正常范围判断 (基于averaged rates, 参考: inj_start=0.0001, inj_guess=0.25):")
println("-" ^ 80)
normal_min = 0.0001
normal_max = 0.25
for (desc, last_rate, avg_rate) in case_info
    if avg_rate < normal_min
        status = "⚠️  低于最小值"
    elseif avg_rate > normal_max
        status = "⚠️  超过最大值"
    else
        status = "✓ 正常"
    end
    println(@sprintf("%-50s:", desc))
    println(@sprintf("  Averaged rate: %.6f  %s", avg_rate, status))
end

# 与同类型其他cases比较（如果有数据的话）
println("\n" * "=" ^ 80)
println("提示: 可以运行 collect_all_injection_rates.jl 来获取所有CVaR cases的统计数据")
println("=" ^ 80)

