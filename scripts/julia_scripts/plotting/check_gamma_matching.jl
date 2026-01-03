#!/usr/bin/env julia
# Check what directories are being matched for gamma=0.1 and gamma=0.2

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"

function check_matching(target_gamma::String, target_alpha::String)
    println("\n" * "=" ^ 80)
    println("Checking matching for gamma=$target_gamma, alpha=$target_alpha")
    println("=" ^ 80)
    
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
            target_alpha_val = parse(Float64, target_alpha)
            if target_alpha_val == 0.0
                alpha_match = (alpha_val == 0.001 || abs(alpha_val - 0.0) < 1e-6)
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
            push!(matched_dirs, risk_name)
            println("MATCHED: $risk_name")
        end
    end
    
    return matched_dirs
end

# Check gamma=0.1 cases
println("\n" * "=" ^ 80)
println("GAMMA=0.1 CASES")
println("=" ^ 80)
for alpha in ["0.0", "0.01", "0.05"]
    dirs = check_matching("0.1", alpha)
    println("  alpha=$alpha: $(length(dirs)) directories matched")
end

# Check gamma=0.2 cases
println("\n" * "=" ^ 80)
println("GAMMA=0.2 CASES")
println("=" ^ 80)
for alpha in ["0.0", "0.01", "0.05"]
    dirs = check_matching("0.2", alpha)
    println("  alpha=$alpha: $(length(dirs)) directories matched")
end

