#!/usr/bin/env julia
# Debug why gamma=0.1 and gamma=0.2 have same data

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using DataFrames

const ROOT = get(ENV, "DT_CONTROL_ROOT", abspath(joinpath(@__DIR__, "..", "..", "..", "..", "data", "DT_control", "exp_name=step1")))

# Test collecting data for gamma=0.1, alpha=0.0, 0.01, 0.05
println("=" ^ 80)
println("Testing gamma=0.1 data collection")
println("=" ^ 80)

for alpha in ["0.0", "0.01", "0.05"]
    println("\n--- alpha=$alpha ---")
    
    # Simulate the collection logic
    risk_dirs = filter(d ->
        isdir(joinpath(ROOT, d)) &&
        occursin("CVaR", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(ROOT))
    
    matched_dirs = String[]
    for risk_name in risk_dirs
        alpha_pattern = r"alpha=([0-9.]+)"
        gamma_pattern = r"gamma=([0-9.]+)"
        
        alpha_match = false
        gamma_match = false
        
        if (m = match(alpha_pattern, risk_name)) !== nothing
            alpha_val = parse(Float64, m.captures[1])
            target_alpha_val = parse(Float64, alpha)
            if target_alpha_val == 0.0
                alpha_match = (alpha_val == 0.001 || abs(alpha_val - 0.0) < 1e-6)
            else
                alpha_match = abs(alpha_val - target_alpha_val) < 1e-6
            end
        end
        
        if (m = match(gamma_pattern, risk_name)) !== nothing
            gamma_val = parse(Float64, m.captures[1])
            gamma_match = abs(gamma_val - 0.1) < 1e-6
        end
        
        if alpha_match && gamma_match
            push!(matched_dirs, risk_name)
        end
    end
    
    println("Matched directories: $matched_dirs")
    
    # Check sample 1 data from each matched directory
    for dir in matched_dirs
        final_path = joinpath(ROOT, dir, "sample=1", "final.jld2")
        if isfile(final_path)
            data = load(final_path)
            inj_arr = data["inj_rate_arr"]
            col1 = vec(view(inj_arr, :, 1))
            clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
            idx = findlast(!iszero, clean)
            if idx !== nothing
                last_nonzero = clean[idx]
                println("  $dir: last_nonzero=$last_nonzero (at index $idx)")
            end
        end
    end
end

println("\n" * "=" ^ 80)
println("Testing gamma=0.2 data collection")
println("=" ^ 80)

for alpha in ["0.0", "0.01", "0.05"]
    println("\n--- alpha=$alpha ---")
    
    risk_dirs = filter(d ->
        isdir(joinpath(ROOT, d)) &&
        occursin("CVaR", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(ROOT))
    
    matched_dirs = String[]
    for risk_name in risk_dirs
        alpha_pattern = r"alpha=([0-9.]+)"
        gamma_pattern = r"gamma=([0-9.]+)"
        
        alpha_match = false
        gamma_match = false
        
        if (m = match(alpha_pattern, risk_name)) !== nothing
            alpha_val = parse(Float64, m.captures[1])
            target_alpha_val = parse(Float64, alpha)
            if target_alpha_val == 0.0
                alpha_match = (alpha_val == 0.001 || abs(alpha_val - 0.0) < 1e-6)
            else
                alpha_match = abs(alpha_val - target_alpha_val) < 1e-6
            end
        end
        
        if (m = match(gamma_pattern, risk_name)) !== nothing
            gamma_val = parse(Float64, m.captures[1])
            gamma_match = abs(gamma_val - 0.2) < 1e-6
        end
        
        if alpha_match && gamma_match
            push!(matched_dirs, risk_name)
        end
    end
    
    println("Matched directories: $matched_dirs")
    
    # Check sample 1 data from each matched directory
    for dir in matched_dirs
        final_path = joinpath(ROOT, dir, "sample=1", "final.jld2")
        if isfile(final_path)
            data = load(final_path)
            inj_arr = data["inj_rate_arr"]
            col1 = vec(view(inj_arr, :, 1))
            clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
            idx = findlast(!iszero, clean)
            if idx !== nothing
                last_nonzero = clean[idx]
                println("  $dir: last_nonzero=$last_nonzero (at index $idx)")
            end
        end
    end
end
