#!/usr/bin/env julia
# Compare iteration times between old and new CVaR cases

using JLD2
using DrWatson
@quickactivate "optim_injr_DT"

# New cases: from logs (already extracted)
new_cases_times = [
    46.2,  # alpha=0.01, gamma=0.0
    45.7,  # alpha=0.02, gamma=0.0
    45.7,  # alpha=0.05, gamma=0.0
    46.0,  # alpha=0.0, gamma=0.0
    45.9,  # alpha=0.0, gamma=0.01
    46.6,  # alpha=0.0, gamma=0.02
    46.1,  # alpha=0.0, gamma=0.05
    45.5,  # alpha=0.001, gamma=0.0
    45.8,  # alpha=0.001, gamma=0.01
    45.9,  # alpha=0.001, gamma=0.02
    46.0,  # alpha=0.001, gamma=0.05
]

println("=== 新跑的11个case的iteration时间 ===")
println("平均: $(round(mean(new_cases_times), digits=1))分钟/iteration")
println("范围: $(round(minimum(new_cases_times), digits=1)) - $(round(maximum(new_cases_times), digits=1))分钟/iteration")
println()

# Old cases: try to read from final.jld2 files
old_cases_dirs = [
    "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.02__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "data/DT_control/exp_name=step1/CVaR__SOFT__alpha=0.001__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "data/DT_control/exp_name=step1/CVaR__SOFT__alpha=0.001__gamma=0.02__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "data/DT_control/exp_name=step1/CVaR__SOFT__alpha=0.001__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
]

println("=== 查找老的CVaR cases的timing信息 ===")
old_times = Float64[]
for case_dir in old_cases_dirs
    case_name = basename(case_dir)
    
    # Try sample=128 first
    final_file = joinpath(case_dir, "sample=128", "final.jld2")
    if !isfile(final_file)
        # Try to find any sample directory
        sample_dirs = filter(isdir, [joinpath(case_dir, d) for d in readdir(case_dir) if startswith(d, "sample=")])
        if !isempty(sample_dirs)
            final_file = joinpath(sample_dirs[1], "final.jld2")
        end
    end
    
    if isfile(final_file)
        try
            data = load(final_file)
            println("\n$case_name:")
            println("  File: $final_file")
            println("  Keys: ", keys(data))
            
            # Look for timing information
            for key in keys(data)
                if occursin("time", lowercase(string(key))) || occursin("wall", lowercase(string(key))) || occursin("iter", lowercase(string(key)))
                    val = data[key]
                    println("    $key: ", typeof(val))
                    if val isa AbstractArray && length(val) > 0
                        println("      Length: ", length(val))
                        if length(val) <= 10
                            println("      Values: ", val)
                        end
                    elseif !(val isa AbstractArray)
                        println("      Value: ", val)
                    end
                end
            end
            
            # Try to infer from file modification time or other metadata
            # If we have iterations array, we can estimate
            if haskey(data, "iterations") || haskey(data, "inj_rate")
                println("  (Note: No explicit timing found, but data exists)")
            end
        catch e
            println("  Error reading file: $e")
        end
    else
        println("\n$case_name: final.jld2 not found")
    end
end

println("\n=== 对比总结 ===")
println("新cases (11个):")
println("  平均: $(round(mean(new_cases_times), digits=1))分钟/iteration")
println("  范围: $(round(minimum(new_cases_times), digits=1)) - $(round(maximum(new_cases_times), digits=1))分钟/iteration")
println()
println("老的cases:")
if isempty(old_times)
    println("  无法从final.jld2中提取timing信息")
    println("  根据之前的经验，老的cases可能是5-6小时/iteration")
    println("  如果这样，加速比约为: $(round((5.5 * 60) / mean(new_cases_times), digits=1))x")
else
    println("  平均: $(round(mean(old_times), digits=1))分钟/iteration")
    println("  范围: $(round(minimum(old_times), digits=1)) - $(round(maximum(old_times), digits=1))分钟/iteration")
    println("  加速比: $(round(mean(old_times) / mean(new_cases_times), digits=1))x")
end

