#!/usr/bin/env julia
# Check gamma=0.0 data matching

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2

const ROOT = get(ENV, "DT_CONTROL_ROOT", abspath(joinpath(@__DIR__, "..", "..", "..", "..", "data", "DT_control", "exp_name=step1")))

# Check what directories match gamma=0.0
risk_dirs = filter(d ->
    isdir(joinpath(ROOT, d)) &&
    occursin("CVaR", d) &&
    d != "geo" &&
    !startswith(d, ".")
, readdir(ROOT))

println("Checking gamma=0.0 matching:")
println("=" ^ 80)

target_gamma = "0.0"
target_alpha = "0.0"

for risk_name in risk_dirs
    # More precise matching
    alpha_pattern = r"alpha=([0-9.]+)"
    gamma_pattern = r"gamma=([0-9.]+)"
    
    alpha_match = false
    gamma_match = false
    
    if (m = match(alpha_pattern, risk_name)) !== nothing
        alpha_val = parse(Float64, m.captures[1])
        target_alpha_val = parse(Float64, target_alpha)
        if target_alpha_val == 0.0 && alpha_val == 0.001
            alpha_match = true
        else
            alpha_match = abs(alpha_val - target_alpha_val) < 1e-6
        end
    end
    
    if (m = match(gamma_pattern, risk_name)) !== nothing
        gamma_val = parse(Float64, m.captures[1])
        target_gamma_val = parse(Float64, target_gamma)
        gamma_match = abs(gamma_val - target_gamma_val) < 1e-6
    end
    
    if alpha_match && gamma_match
        println("MATCH: $risk_name")
        # Check sample 1
        final_path = joinpath(ROOT, risk_name, "sample=1", "final.jld2")
        if isfile(final_path)
            data = load(final_path)
            if haskey(data, "inj_rate_arr")
                inj_arr = data["inj_rate_arr"]
                col1 = ndims(inj_arr) == 1 ? collect(inj_arr) : vec(view(inj_arr, :, 1))
                clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
                idx = findlast(!iszero, clean)
                if idx !== nothing
                    println("  Last nonzero at index $idx: $(clean[idx])")
                    println("  First element (inj_rate[1]): $(col1[1])")
                end
            end
        end
    end
end

println("\n" * "=" ^ 80)
println("Checking all gamma values:")
for risk_name in sort(risk_dirs)
    if (m = match(r"gamma=([0-9.]+)", risk_name)) !== nothing
        gamma_val = m.captures[1]
        if (m2 = match(r"alpha=([0-9.]+)", risk_name)) !== nothing
            alpha_val = m2.captures[1]
            println("gamma=$gamma_val, alpha=$alpha_val: $risk_name")
        end
    end
end
