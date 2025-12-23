#!/usr/bin/env julia
# Check which thresholds are in each summary file

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2

sample_num = 128
data_root = datadir("DT_control", "exp_name=step1", "threshold_sensitivity")

println("=" ^ 80)
println("Checking Summary Files for Thresholds")
println("=" ^ 80)
println()

# Check POF files
println("POF Summary Files:")
for i in 1:5
    for pattern in ["summary_POF_sample=$(sample_num)_#$i.jld2", 
                    "summary_POF__sample=$(sample_num)_#$i.jld2"]
        file = joinpath(data_root, pattern)
        if isfile(file)
            data = JLD2.load(file)
            thresh = haskey(data, "thresholds") ? data["thresholds"] : "N/A"
            println("  $pattern: thresholds = $thresh")
        end
    end
end

println()

# Check CVaR files
println("CVaR Summary Files:")
for i in 1:5
    for pattern in ["summary_CVaR_sample=$(sample_num)_#$i.jld2",
                    "summary_CVaR__sample=$(sample_num)_#$i.jld2"]
        file = joinpath(data_root, pattern)
        if isfile(file)
            data = JLD2.load(file)
            thresh = haskey(data, "thresholds") ? data["thresholds"] : "N/A"
            println("  $pattern: thresholds = $thresh")
        end
    end
end

println()

# Check merged files
println("Merged Summary Files:")
for pattern in ["summary__POF__sample=$(sample_num).jld2",
                "summary__CVaR__sample=$(sample_num).jld2"]
    file = joinpath(data_root, pattern)
    if isfile(file)
        data = JLD2.load(file)
        thresh = haskey(data, "thresholds") ? data["thresholds"] : "N/A"
        println("  $pattern: thresholds = $thresh")
    end
end

