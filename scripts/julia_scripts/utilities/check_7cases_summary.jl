#!/usr/bin/env julia
# Summarize values and failure context for seven previously missing samples.

using Pkg
Pkg.activate(".")

using JLD2
using Printf

const INJ_START = 0.0001

function last_nonzero_inj_rate(inj_rate_arr)
    col1 = vec(inj_rate_arr[:, 1])
    clean = filter(x -> isfinite(x) && !isnan(x), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? INJ_START : clean[idx]
end

# Seven previously missing samples
missing_cases = [
    ("gamma=0.01, alpha=0.02, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("gamma=0.01, alpha=0.05, sample=17", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=17/final.jld2"),
    ("gamma=0.02, alpha=0.01, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.02__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("gamma=0.05, alpha=0.02, sample=42", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=42/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=1",  "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=1/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=21", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=21/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
]

println("=" ^ 80)
println("Recorded values for seven previously missing samples")
println("=" ^ 80)
println()

for (desc, path) in missing_cases
    if isfile(path)
        data = JLD2.load(path)
        inj_rate_arr = data["inj_rate_arr"]
        last_nonzero = last_nonzero_inj_rate(inj_rate_arr)
        avg_rate = (last_nonzero + INJ_START) / 2.0
        
        println(desc)
        println(@sprintf("  Last nonzero injection rate: %.6f m³/s", last_nonzero))
        println(@sprintf("  Averaged rate (mean with inj_start=%.6f): %.6f m³/s", INJ_START, avg_rate))
        println()
    else
        println("⚠️  $desc: final.jld2 does not exist")
        println()
    end
end

