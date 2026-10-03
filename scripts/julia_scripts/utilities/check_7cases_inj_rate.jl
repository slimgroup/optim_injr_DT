#!/usr/bin/env julia
# Read final injection rates for the seven recovery cases.

using Pkg
Pkg.activate(".")
using JLD2
using Statistics
using Printf

# Paths for the seven cases
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
println("Injection-rate analysis for seven cases (m³/s)")
println("=" ^ 80)
println("Historical diagnostic: average the last nonzero rate with inj_start (0.0001)")
println("")

const INJ_START = 0.0001  # Injection rate at the first schedule step

# Read the last nonzero rate, following collect_all_injection_rates.jl.
function last_nonzero_inj_rate(inj_rate_arr)
    col1 = vec(inj_rate_arr[:, 1])  # First column
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
        
        # Take the last nonzero injection rate
        last_nonzero = last_nonzero_inj_rate(inj_rate_arr)
        
        # Average with inj_start
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
println("Statistics (last nonzero rates):")
if length(inj_rates_last) > 0
    println(@sprintf("  Minimum: %.6f", minimum(inj_rates_last)))
    println(@sprintf("  Maximum: %.6f", maximum(inj_rates_last)))
    println(@sprintf("  Mean: %.6f", mean(inj_rates_last)))
    println(@sprintf("  Median: %.6f", median(inj_rates_last)))
    println(@sprintf("  Standard deviation: %.6f", std(inj_rates_last)))
end
println("")
println("Statistics (rates averaged with inj_start):")
if length(inj_rates_avg) > 0
    println(@sprintf("  Minimum: %.6f", minimum(inj_rates_avg)))
    println(@sprintf("  Maximum: %.6f", maximum(inj_rates_avg)))
    println(@sprintf("  Mean: %.6f", mean(inj_rates_avg)))
    println(@sprintf("  Median: %.6f", median(inj_rates_avg)))
    println(@sprintf("  Standard deviation: %.6f", std(inj_rates_avg)))
end
println("=" ^ 80)

# Compare with the historical reference interval.
# inj_start=0.0001 and inj_guess=0.25 define this diagnostic interval, not a solver bound.
println("\nHistorical reference range (averaged rates; inj_start=0.0001, inj_guess=0.25):")
println("-" ^ 80)
normal_min = 0.0001
normal_max = 0.25
for (desc, last_rate, avg_rate) in case_info
    if avg_rate < normal_min
        status = "⚠️  Below reference minimum"
    elseif avg_rate > normal_max
        status = "⚠️  Above reference maximum"
    else
        status = "✓ Within reference range"
    end
    println(@sprintf("%-50s:", desc))
    println(@sprintf("  Averaged rate: %.6f  %s", avg_rate, status))
end

# Compare with other samples of the same case if data are available.
println("\n" * "=" ^ 80)
println("Tip: run collect_all_injection_rates.jl for statistics across all CVaR cases")
println("=" ^ 80)

