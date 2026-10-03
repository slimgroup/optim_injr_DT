#!/usr/bin/env julia
# Flag unusual injection rates among the seven recovered samples.
# Compare with statistics for the matching risk case.

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

# Read the last nonzero injection rate
function last_nonzero_inj_rate(inj_rate_arr)
    col1 = vec(inj_rate_arr[:, 1])
    clean = filter(x -> isfinite(x) && !isnan(x), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? INJ_START : clean[idx]
end

# Seven previously missing samples
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
println("Injection-rate diagnostics for seven previously missing samples")
println("=" ^ 80)

# Read group statistics
stats_file = joinpath(ROOT, "inj_rate_stats_20251105_012313.csv")
if isfile(stats_file)
    stats_df = CSV.read(stats_file, DataFrame)
    println("\nReading matching-case means and standard deviations from the statistics file:")
    println(stats_file)
else
    println("\nWarning: statistics file not found; using fallback values")
    stats_df = DataFrame()
end

# Collect data for the seven samples
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
println("Injection rates for the seven samples:")
println("=" ^ 80)
for d in missing_data
    println(@sprintf("%-50s:", d.desc))
    println(@sprintf("  Last nonzero: %.6f", d.last))
    println(@sprintf("  Averaged:     %.6f", d.avg))
end

# Compare with the matching cases
println("\n" * "=" ^ 80)
println("Outlier diagnostic (mean ± 2*std reference interval):")
println("=" ^ 80)

if nrow(stats_df) > 0
    for d in missing_data
        # Find the matching statistics
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
                println("  ⚠️  Outside the reference interval; review required")
                if d.avg < lower_bound
                    println(@sprintf("     (Below the lower bound by %.6f)", lower_bound - d.avg))
                else
                    println(@sprintf("     (Above the upper bound by %.6f)", d.avg - upper_bound))
                end
            else
                println("  ✓ Within the reference interval")
            end
        else
            println("\n$(d.case_tag):")
            println("  ⚠️  No matching statistics found")
        end
    end
else
    println("Cannot perform outlier diagnostics: missing statistics")
end

# Summarize
println("\n" * "=" ^ 80)
println("Summary:")
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
    println(@sprintf("Of the seven samples, %d lie outside mean ± 2*std", outlier_count))
    if outlier_count > 0
        println("\nReview flagged samples; this heuristic alone does not justify excluding completed results from a histogram")
    else
        println("\nAll seven samples lie within the reference interval; apply the established completion and validity rules")
    end
else
    println("Cannot summarize: missing statistics")
end
