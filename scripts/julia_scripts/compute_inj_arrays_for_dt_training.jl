#!/usr/bin/env julia
# Compute injection rate arrays for 4 selected cases for digital twin training
# Cases:
# 1-1: POF eps = 0.0
# 1-2: CVaR gamma = 0.0, alpha = 0.0
# 2-1: POF eps = 0.01
# 2-2: CVaR gamma = 0.1, alpha = 0.01

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames
using KernelDensity
using Distributions
using JLD2

# Config
const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const NUM_GRID = 16000
const CONF_LEVEL = 0.95
const FRACTURE_PROB_THRESHOLD = 0.01
const FORWARD_STEP = 2
const INJ_START = 0.0001

# Helper function to get data from JLD2
_get(data, k::AbstractString) = haskey(data, k) ? data[k] : (haskey(data, Symbol(k)) ? data[Symbol(k)] : nothing)

# ========== Collect POF data from directories ==========
function collect_pof_from_dirs(root::AbstractString, target_eps::String)
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4, inj_start::Float64=0.0001, forward_step::Int=FORWARD_STEP)
        raw = _get(data, "inj_rate_arr")
        raw === nothing && return (init_rate + inj_start) / 2.0
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        
        idx = findlast(!iszero, clean)
        if idx === nothing
            return (init_rate + inj_start) / 2.0
        end
        
        last_nonzero = clean[idx]
        inj_rate_full = collect(range(inj_start, last_nonzero, forward_step * 6))
        if length(inj_rate_full) >= 6
            inj_rate_at_index6 = inj_rate_full[6]
            return (inj_rate_at_index6 + inj_start) / 2.0
        else
            return (last_nonzero + inj_start) / 2.0
        end
    end
    
    rows = NamedTuple[]
    seen_samples = Set{Int}()
    risk_dirs = filter(d ->
        isdir(joinpath(root, d)) &&
        occursin("POF", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(root))
    
    for risk_name in risk_dirs
        if !occursin("eps=$target_eps", risk_name) && !occursin("eps=$(parse(Float64, target_eps))", risk_name)
            continue
        end
        
        risk_dir = joinpath(root, risk_name)
        for s in 1:128
            if s in seen_samples
                continue
            end
            
            sdir = joinpath(risk_dir, "sample=$(s)")
            final_path = joinpath(sdir, "final.jld2")
            
            if isfile(final_path)
                status = "ok_final"
                last_inj = NaN
                try
                    data = load(final_path)
                    last_inj = last_nonzero_inj_rate(data; init_rate=1e-4)
                catch err
                    status = "load_error"
                    continue
                end
                push!(rows, (
                    case_tag = "POF_eps=$target_eps",
                    risk_dir = risk_name,
                    sample = s,
                    status = status,
                    last_inj_rate = last_inj,
                    file_used = final_path,
                    note = ""
                ))
                push!(seen_samples, s)
            end
        end
    end
    
    return DataFrame(rows)
end

# ========== Collect CVaR data from directories ==========
function collect_cvar_from_dirs(root::AbstractString, target_alpha::String, target_gamma::String)
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4, inj_start::Float64=0.0001, forward_step::Int=FORWARD_STEP)
        raw = _get(data, "inj_rate_arr")
        raw === nothing && return (init_rate + inj_start) / 2.0
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        
        idx = findlast(!iszero, clean)
        if idx === nothing
            return (init_rate + inj_start) / 2.0
        end
        
        last_nonzero = clean[idx]
        inj_rate_full = collect(range(inj_start, last_nonzero, forward_step * 6))
        if length(inj_rate_full) >= 6
            inj_rate_at_index6 = inj_rate_full[6]
            return (inj_rate_at_index6 + inj_start) / 2.0
        else
            return (last_nonzero + inj_start) / 2.0
        end
    end
    
    rows = NamedTuple[]
    seen_samples = Set{Int}()
    risk_dirs = filter(d ->
        isdir(joinpath(root, d)) &&
        occursin("CVaR", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(root))
    
    alpha_0_dir_exists = false
    if target_gamma == "0.0" && target_alpha == "0.0"
        gamma_pattern = r"gamma=([0-9.]+)"
        alpha_pattern = r"alpha=([0-9.]+)"
        for d in risk_dirs
            if (gm = match(gamma_pattern, d)) !== nothing && 
               (am = match(alpha_pattern, d)) !== nothing &&
               abs(parse(Float64, gm.captures[1]) - 0.0) < 1e-6 &&
               abs(parse(Float64, am.captures[1]) - 0.0) < 1e-6
                alpha_0_dir_exists = true
                break
            end
        end
    end
    
    for risk_name in risk_dirs
        alpha_pattern = r"alpha=([0-9.]+)"
        alpha_match = false
        alpha_val_matched = nothing
        if (m = match(alpha_pattern, risk_name)) !== nothing
            alpha_val = parse(Float64, m.captures[1])
            target_alpha_val = parse(Float64, target_alpha)
            if target_alpha_val == 0.0
                if alpha_0_dir_exists
                    alpha_match = abs(alpha_val - 0.0) < 1e-6
                else
                    alpha_match = (alpha_val == 0.001 || abs(alpha_val - 0.0) < 1e-6)
                end
            else
                alpha_match = abs(alpha_val - target_alpha_val) < 1e-6
            end
            if alpha_match
                alpha_val_matched = alpha_val
            end
        end
        
        gamma_pattern = r"gamma=([0-9.]+)"
        gamma_match = false
        if (m = match(gamma_pattern, risk_name)) !== nothing
            gamma_val = parse(Float64, m.captures[1])
            target_gamma_val = parse(Float64, target_gamma)
            gamma_match = abs(gamma_val - target_gamma_val) < 1e-6
        end
        
        if !alpha_match || !gamma_match
            continue
        end
        
        case_tag = "CVaR_g=$(target_gamma)_a=$(target_alpha)"
        risk_dir = joinpath(root, risk_name)
        for s in 1:128
            if s in seen_samples
                continue
            end
            
            sdir = joinpath(risk_dir, "sample=$(s)")
            final_path = joinpath(sdir, "final.jld2")
            
            if isfile(final_path)
                status = "ok_final"
                last_inj = NaN
                try
                    data = load(final_path)
                    last_inj = last_nonzero_inj_rate(data; init_rate=1e-4)
                catch err
                    status = "load_error"
                    continue
                end
                push!(rows, (
                    case_tag = case_tag,
                    risk_dir = risk_name,
                    sample = s,
                    status = status,
                    last_inj_rate = last_inj,
                    file_used = final_path,
                    note = ""
                ))
                push!(seen_samples, s)
            end
        end
    end
    
    return DataFrame(rows)
end

# Compute CDF and CI
function compute_cdf_ci(data::Vector{Float64}; kde_bandwidth=nothing, num_grid::Int=NUM_GRID, conf_level::Float64=CONF_LEVEL)
    if isempty(data) || length(data) < 2
        error("Need at least 2 data points")
    end
    
    kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
    
    x_min = minimum(data)
    x_max = maximum(data)
    x_grid = collect(range(x_min, stop=x_max, length=num_grid))
    dx = x_grid[2] - x_grid[1]
    
    pdf_vals = pdf(kde_result, x_grid)
    cdf_vals = cumsum(pdf_vals) .* dx
    cdf_vals = cdf_vals ./ cdf_vals[end]
    
    n = length(data)
    z = quantile(Normal(), 1 - (1 - conf_level) / 2)
    
    ci_lower = zeros(length(x_grid))
    ci_upper = zeros(length(x_grid))
    
    for i in eachindex(cdf_vals)
        p_hat = cdf_vals[i]
        se = sqrt(p_hat * (1 - p_hat) / n)
        ci_lower[i] = max(0.0, p_hat - z * se)
        ci_upper[i] = min(1.0, p_hat + z * se)
    end
    
    return x_grid, cdf_vals, ci_lower, ci_upper
end

# Find threshold crossings
function find_threshold_crossings(x_grid::Vector{Float64}, cdf::Vector{Float64}, 
                                  ci_lower::Vector{Float64}, ci_upper::Vector{Float64},
                                  threshold::Float64)
    idx_cdf = findfirst(x -> x >= threshold, cdf)
    x_cdf = idx_cdf !== nothing ? x_grid[idx_cdf] : nothing
    
    idx_upper = findfirst(x -> x >= threshold, ci_upper)
    x_left_ci = idx_upper !== nothing ? x_grid[idx_upper] : nothing
    
    idx_lower = findfirst(x -> x >= threshold, ci_lower)
    x_right_ci = idx_lower !== nothing ? x_grid[idx_lower] : nothing
    
    return x_left_ci, x_cdf, x_right_ci
end

# Collect data for a specific case
function get_case_data(case_type::String, eps::Union{String, Nothing}=nothing, 
                      gamma::Union{String, Nothing}=nothing, alpha::Union{String, Nothing}=nothing)
    if case_type == "POF"
        @assert eps !== nothing "POF case requires eps"
        return collect_pof_from_dirs(ROOT, eps)
    elseif case_type == "CVaR"
        @assert gamma !== nothing && alpha !== nothing "CVaR case requires gamma and alpha"
        return collect_cvar_from_dirs(ROOT, alpha, gamma)
    else
        error("Unknown case type: $case_type")
    end
end

# Main: Compute left_CI for each case
cases = [
    ("Case 1-1", "POF", "0.0", nothing, nothing),
    ("Case 1-2", "CVaR", nothing, "0.0", "0.0"),
    ("Case 2-1", "POF", "0.01", nothing, nothing),
    ("Case 2-2", "CVaR", nothing, "0.1", "0.01")
]

results = Dict{String, Any}()

for (case_name, case_type, eps, gamma, alpha) in cases
    println("\n" * "="^60)
    println("Processing $case_name: $case_type")
    if case_type == "POF"
        println("  eps = $eps")
    else
        println("  gamma = $gamma, alpha = $alpha")
    end
    println("="^60)
    
    # Collect data
    df = get_case_data(case_type, eps, gamma, alpha)
    df_ok = df[df.status .== "ok_final", :]
    
    if nrow(df_ok) == 0
        @warn "No data found for $case_name"
        continue
    end
    
    # Extract injection rates
    data = collect(skipmissing(df_ok.last_inj_rate))
    println("  Collected $(length(data)) samples")
    
    # Compute CDF and CI
    x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data)
    
    # Find threshold crossings
    x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, FRACTURE_PROB_THRESHOLD)
    
    println("  Left CI:  $(x_left_ci !== nothing ? round(x_left_ci, digits=5) : "N/A")")
    println("  CDF:      $(x_cdf !== nothing ? round(x_cdf, digits=5) : "N/A")")
    println("  Right CI: $(x_right_ci !== nothing ? round(x_right_ci, digits=5) : "N/A")")
    
    if x_left_ci === nothing
        @warn "Could not find left_CI for $case_name"
        continue
    end
    
    # Compute injection rate array
    inj_rate_array = collect(range(INJ_START, x_left_ci, 6))
    
    results[case_name] = Dict(
        "case_type" => case_type,
        "eps" => eps,
        "gamma" => gamma,
        "alpha" => alpha,
        "left_CI" => x_left_ci,
        "cdf" => x_cdf,
        "right_CI" => x_right_ci,
        "inj_start" => INJ_START,
        "inj_rate_array" => inj_rate_array,
        "n_samples" => length(data)
    )
end

# Generate markdown file
md_content = """# Injection Rate Arrays for Digital Twin Training

This document contains the injection rate arrays for 4 selected cases based on panel3 CDF CI zoom analysis.

## Methodology

For each case:
- **inj_start**: 0.0001 m³/s (for the first monitoring step)
- **left_CI**: Left confidence interval value at 1% fracture probability threshold (from panel3)
- **inj_rate_array**: 6-element array generated as `collect(range(inj_start, left_CI, 6))`

---

"""

for (case_name, case_type, eps, gamma, alpha) in cases
    if !haskey(results, case_name)
        md_content *= "## $case_name\n\n**Status**: No data available\n\n---\n\n"
        continue
    end
    
    r = results[case_name]
    
    md_content *= "## $case_name\n\n"
    
    if case_type == "POF"
        md_content *= "- **Type**: POF (Probability of Fracture)\n"
        md_content *= "- **Parameter**: ε (eps) = $(eps)\n"
    else
        md_content *= "- **Type**: CVaR (Conditional Value at Risk)\n"
        md_content *= "- **Parameters**: γ (gamma) = $(gamma), α (alpha) = $(alpha)\n"
    end
    
    md_content *= "- **Number of samples**: $(r["n_samples"])\n"
    md_content *= "- **inj_start**: $(r["inj_start"]) m³/s\n"
    md_content *= "- **left_CI**: $(round(r["left_CI"], digits=5)) m³/s\n"
    if r["cdf"] !== nothing
        md_content *= "- **CDF point estimate**: $(round(r["cdf"], digits=5)) m³/s\n"
    end
    if r["right_CI"] !== nothing
        md_content *= "- **right_CI**: $(round(r["right_CI"], digits=5)) m³/s\n"
    end
    
    md_content *= "\n### Injection Rate Array (length = 6)\n\n"
    md_content *= "```julia\n"
    md_content *= "inj_rate = ["
    for (i, val) in enumerate(r["inj_rate_array"])
        md_content *= "$(round(val, digits=6))"
        if i < length(r["inj_rate_array"])
            md_content *= ", "
        end
    end
    md_content *= "]\n"
    md_content *= "```\n\n"
    
    md_content *= "**Values (m³/s)**:\n"
    for (i, val) in enumerate(r["inj_rate_array"])
        md_content *= "- Index $(i): $(round(val, digits=6))\n"
    end
    
    md_content *= "\n---\n\n"
end

md_content *= """
## Notes

- All injection rates are in units of m³/s
- The arrays are generated for the first monitoring step
- Left CI values are extracted from panel3 CDF CI zoom plots
- The injection rate array spans from `inj_start` (0.0001) to `left_CI` with 6 evenly spaced points
"""

# Write to file
output_file = joinpath(ROOT, "injection_rate_arrays_for_dt_training.md")
open(output_file, "w") do f
    write(f, md_content)
end

println("\n" * "="^60)
println("Generated markdown file: $output_file")
println("="^60)

