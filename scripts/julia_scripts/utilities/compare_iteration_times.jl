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

println("=== Iteration times for the 11 newer cases ===")
println("Mean: $(round(mean(new_cases_times), digits=1)) minutes/iteration")
println("Range: $(round(minimum(new_cases_times), digits=1)) - $(round(maximum(new_cases_times), digits=1)) minutes/iteration")
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

println("=== Searching older CVaR cases for timing information ===")
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

println("\n=== Comparison summary ===")
println("Newer cases (11):")
println("  Mean: $(round(mean(new_cases_times), digits=1)) minutes/iteration")
println("  Range: $(round(minimum(new_cases_times), digits=1)) - $(round(maximum(new_cases_times), digits=1)) minutes/iteration")
println()
println("Older cases:")
if isempty(old_times)
    println("  Could not extract timing information from final.jld2")
    println("  Historical estimate: older cases may have taken 5–6 hours/iteration")
    println("  Under that assumption, estimated speedup: $(round((5.5 * 60) / mean(new_cases_times), digits=1))x")
else
    println("  Mean: $(round(mean(old_times), digits=1)) minutes/iteration")
    println("  Range: $(round(minimum(old_times), digits=1)) - $(round(maximum(old_times), digits=1)) minutes/iteration")
    println("  Speedup: $(round(mean(old_times) / mean(new_cases_times), digits=1))x")
end

