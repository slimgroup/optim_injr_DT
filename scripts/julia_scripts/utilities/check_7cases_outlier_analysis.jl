#!/usr/bin/env julia
# 检查7个missing samples的injection rate是否为outlier
# 与同类型其他cases的统计数据比较

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using CSV
using DataFrames
using Statistics
using Printf

const INJ_START = 0.0001
const ROOT = get(ENV, "DT_CONTROL_ROOT", abspath(joinpath(@__DIR__, "..", "..", "..", "data", "DT_control", "exp_name=step1")))

# 读取last nonzero injection rate
function last_nonzero_inj_rate(inj_rate_arr)
    col1 = vec(inj_rate_arr[:, 1])
    clean = filter(x -> isfinite(x) && !isnan(x), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? INJ_START : clean[idx]
end

# 7个missing samples
missing_cases = [
    ("CVaR_g=0.01_a=0.02", "gamma=0.01, alpha=0.02, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("CVaR_g=0.01_a=0.05", "gamma=0.01, alpha=0.05, sample=17", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=17/final.jld2"),
    ("CVaR_g=0.02_a=0.01", "gamma=0.02, alpha=0.01, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.02__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("CVaR_g=0.05_a=0.02", "gamma=0.05, alpha=0.02, sample=42", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=42/final.jld2"),
    ("CVaR_g=0.05_a=0.05", "gamma=0.05, alpha=0.05, sample=1",  "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=1/final.jld2"),
    ("CVaR_g=0.05_a=0.05", "gamma=0.05, alpha=0.05, sample=21", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=21/final.jld2"),
    ("CVaR_g=0.05_a=0.05", "gamma=0.05, alpha=0.05, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
]

println("=" ^ 80)
println("7个missing samples的injection rate检查与outlier分析")
println("=" ^ 80)

# 读取统计数据
stats_file = joinpath(ROOT, "inj_rate_stats_20251105_012313.csv")
if isfile(stats_file)
    stats_df = CSV.read(stats_file, DataFrame)
    println("\n从统计数据文件读取同类型cases的mean和std:")
    println(stats_file)
else
    println("\n警告: 找不到统计数据文件，将使用默认值")
    stats_df = DataFrame()
end

# 收集7个missing samples的数据
missing_data = []
for (case_tag, desc, path) in missing_cases
    if isfile(path)
        data = JLD2.load(path)
        inj_rate_arr = data["inj_rate_arr"]
        last_nonzero = last_nonzero_inj_rate(inj_rate_arr)
        avg_rate = (last_nonzero + INJ_START) / 2.0
        push!(missing_data, (case_tag=case_tag, desc=desc, last=last_nonzero, avg=avg_rate))
    end
end

println("\n" * "=" ^ 80)
println("7个missing samples的injection rate:")
println("=" ^ 80)
for d in missing_data
    println(@sprintf("%-50s:", d.desc))
    println(@sprintf("  Last nonzero: %.6f", d.last))
    println(@sprintf("  Averaged:     %.6f", d.avg))
end

# 与同类型cases比较
println("\n" * "=" ^ 80)
println("Outlier分析 (基于mean ± 2*std范围):")
println("=" ^ 80)

if nrow(stats_df) > 0
    for d in missing_data
        # 找到对应的统计数据
        case_stats = stats_df[stats_df.case_tag .== d.case_tag, :]
        if nrow(case_stats) > 0
            mean_val = case_stats.mean[1]
            std_val = case_stats.std[1]
            lower_bound = mean_val - 2 * std_val
            upper_bound = mean_val + 2 * std_val
            
            is_outlier = d.avg < lower_bound || d.avg > upper_bound
            
            println("\n$(d.case_tag):")
            println(@sprintf("  Missing sample averaged rate: %.6f", d.avg))
            println(@sprintf("  Same case type (mean ± 2*std): %.6f ± 2*%.6f = [%.6f, %.6f]", 
                    mean_val, std_val, lower_bound, upper_bound))
            if is_outlier
                println("  ⚠️  OUTLIER! 超出正常范围")
                if d.avg < lower_bound
                    println(@sprintf("     (低于下界 %.6f)", lower_bound - d.avg))
                else
                    println(@sprintf("     (高于上界 %.6f)", d.avg - upper_bound))
                end
            else
                println("  ✓ 在正常范围内")
            end
        else
            println("\n$(d.case_tag):")
            println("  ⚠️  找不到对应的统计数据")
        end
    end
else
    println("无法进行outlier分析：缺少统计数据")
end

# 总结
println("\n" * "=" ^ 80)
println("总结:")
println("=" ^ 80)
if nrow(stats_df) > 0
    outlier_count = 0
    for d in missing_data
        case_stats = stats_df[stats_df.case_tag .== d.case_tag, :]
        if nrow(case_stats) > 0
            mean_val = case_stats.mean[1]
            std_val = case_stats.std[1]
            lower_bound = mean_val - 2 * std_val
            upper_bound = mean_val + 2 * std_val
            if d.avg < lower_bound || d.avg > upper_bound
                outlier_count += 1
            end
        end
    end
    println(@sprintf("7个missing samples中，有 %d 个是outlier (超出mean ± 2*std)", outlier_count))
    if outlier_count > 0
        println("\n建议: 如果这些outlier值不合理，不应该将它们包含在distribution histogram中")
    else
        println("\n所有7个samples都在正常范围内，可以安全地包含在histogram中")
    end
else
    println("无法进行总结：缺少统计数据")
end
