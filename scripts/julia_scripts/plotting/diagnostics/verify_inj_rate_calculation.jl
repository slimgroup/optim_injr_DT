#!/usr/bin/env julia
# Verify injection rate calculation for all cases
# Check that we're not taking average twice

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using DataFrames

const ROOT = get(ENV, "DT_CONTROL_ROOT", abspath(joinpath(@__DIR__, "..", "..", "..", "..", "data", "DT_control", "exp_name=step1")))
const FORWARD_STEP = 2
const INJ_START = 0.0001

function last_nonzero_inj_rate_verbose(data; init_rate::Float64=1e-4, inj_start::Float64=INJ_START, forward_step::Int=FORWARD_STEP)
    raw = get(data, "inj_rate_arr", nothing)
    if raw === nothing
        result = (init_rate + inj_start) / 2.0
        return result, "no_data", nothing, nothing, nothing
    end
    
    col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    
    if idx === nothing
        result = (init_rate + inj_start) / 2.0
        return result, "all_zero", nothing, nothing, nothing
    end
    
    last_nonzero = clean[idx]
    println("  Last nonzero (at index $idx): $last_nonzero")
    
    # Reconstruct the full injection rate array
    inj_rate_full = collect(range(inj_start, last_nonzero, forward_step * 6))
    println("  Reconstructed array length: $(length(inj_rate_full))")
    println("  First element (inj_start): $(inj_rate_full[1])")
    println("  Last element: $(inj_rate_full[end])")
    
    if length(inj_rate_full) >= 7
        inj_rate_at_index6 = inj_rate_full[7]
        println("  Element at index 6 (inj_rate[7]): $inj_rate_at_index6")
        result = (inj_rate_at_index6 + inj_start) / 2.0
        println("  Final result (average): $result = ($inj_rate_at_index6 + $inj_start) / 2.0")
        return result, "ok", last_nonzero, inj_rate_at_index6, inj_rate_full
    else
        result = (last_nonzero + inj_start) / 2.0
        println("  Array too short, using last_nonzero: $result = ($last_nonzero + $inj_start) / 2.0")
        return result, "fallback", last_nonzero, nothing, inj_rate_full
    end
end

# Test cases
cases_to_test = [
    ("POF", "0.0", 1),
    ("POF", "0.01", 1),
    ("POF", "0.05", 1),
    ("CVaR", "0.0", "0.0", 1),
    ("CVaR", "0.0", "0.01", 1),
    ("CVaR", "0.0", "0.05", 1),
    ("CVaR", "0.1", "0.0", 1),
    ("CVaR", "0.1", "0.01", 1),
    ("CVaR", "0.1", "0.05", 1),
    ("CVaR", "0.2", "0.0", 1),
    ("CVaR", "0.2", "0.01", 1),
    ("CVaR", "0.2", "0.05", 1),
]

println("=" ^ 80)
println("Verifying injection rate calculation for all 12 cases")
println("=" ^ 80)

for case_info in cases_to_test
    if case_info[1] == "POF"
        eps_val = case_info[2]
        sample = case_info[3]
        case_tag = "POF_eps=$eps_val"
        
        println("\n" * "=" ^ 80)
        println("Testing: $case_tag, sample=$sample")
        println("=" ^ 80)
        
        # Find matching directory
        risk_dirs = filter(d ->
            isdir(joinpath(ROOT, d)) &&
            occursin("POF", d) &&
            occursin("eps=$eps_val", d) &&
            d != "geo" &&
            !startswith(d, ".")
        , readdir(ROOT))
        
        if isempty(risk_dirs)
            println("  No directory found for $case_tag")
            continue
        end
        
        risk_dir = joinpath(ROOT, risk_dirs[1])
        final_path = joinpath(risk_dir, "sample=$(sample)", "final.jld2")
        
        if !isfile(final_path)
            println("  File not found: $final_path")
            continue
        end
        
        println("  File: $final_path")
        data = load(final_path)
        result, status, last_nonzero, inj_at_index6, inj_full = last_nonzero_inj_rate_verbose(data; init_rate=1e-4)
        println("  Status: $status")
        println("  Final injection rate: $result")
        
    elseif case_info[1] == "CVaR"
        gamma_val = case_info[2]
        alpha_val = case_info[3]
        sample = case_info[4]
        case_tag = "CVaR_g=$(gamma_val)_a=$(alpha_val)"
        
        println("\n" * "=" ^ 80)
        println("Testing: $case_tag, sample=$sample")
        println("=" ^ 80)
        
        # Find matching directory
        risk_dirs = filter(d ->
            isdir(joinpath(ROOT, d)) &&
            occursin("CVaR", d) &&
            (occursin("gamma=$gamma_val", d) || occursin("gamma=$(parse(Float64, gamma_val))", d)) &&
            (occursin("alpha=$alpha_val", d) || occursin("alpha=$(parse(Float64, alpha_val))", d)) &&
            d != "geo" &&
            !startswith(d, ".")
        , readdir(ROOT))
        
        if isempty(risk_dirs)
            println("  No directory found for $case_tag")
            continue
        end
        
        risk_dir = joinpath(ROOT, risk_dirs[1])
        final_path = joinpath(risk_dir, "sample=$(sample)", "final.jld2")
        
        if !isfile(final_path)
            println("  File not found: $final_path")
            continue
        end
        
        println("  File: $final_path")
        data = load(final_path)
        result, status, last_nonzero, inj_at_index6, inj_full = last_nonzero_inj_rate_verbose(data; init_rate=1e-4)
        println("  Status: $status")
        println("  Final injection rate: $result")
    end
end

println("\n" * "=" ^ 80)
println("Verification complete!")
println("=" ^ 80)
println("\nKey points to verify:")
println("1. Each case should show: 'Final result (average): X = (Y + Z) / 2.0'")
println("2. Y should be inj_rate[7] (element at index 6)")
println("3. Z should be inj_start (0.0001)")
println("4. This average is taken ONCE, and the result is used directly in plots")
println("5. No additional averaging should occur in the plotting functions")
