#!/usr/bin/env julia
# Check what data is actually collected for each case

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

include("scripts/julia_scripts/plotting/legacy_step1/plot_three_panels.jl")

const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"

# Test collecting data for specific cases
test_cases = [
    ("CVaR", "0.1", "0.0"),
    ("CVaR", "0.1", "0.01"),
    ("CVaR", "0.1", "0.05"),
    ("CVaR", "0.2", "0.0"),
    ("CVaR", "0.2", "0.01"),
    ("CVaR", "0.2", "0.05"),
]

println("=" ^ 80)
println("Checking collected data for each case")
println("=" ^ 80)

for (case_type, gamma, alpha) in test_cases
    println("\n" * "-" ^ 80)
    println("Case: CVaR g=$gamma a=$alpha")
    println("-" ^ 80)
    
    if case_type == "CVaR"
        df = collect_cvar_from_dirs(ROOT, alpha, gamma)
        if nrow(df) > 0
            df_ok = df[df.status .== "ok_final", :]
            data = collect(skipmissing(df_ok.last_inj_rate))
            println("  Collected $(length(data)) samples")
            if length(data) > 0
                println("  Min: $(minimum(data))")
                println("  Max: $(maximum(data))")
                println("  Mean: $(mean(data))")
                println("  First 5 values: $(data[1:min(5, length(data))])")
                println("  Last 5 values: $(data[max(1, length(data)-4):end])")
            end
        else
            println("  No data collected!")
        end
    end
end

