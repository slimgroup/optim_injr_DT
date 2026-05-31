#!/usr/bin/env julia
# =============================================================================
# Check if POF cases have smaller injection rates compared to non-POF cases
# Compares POF cases with similar non-POF cases to see if injection rates are systematically smaller
# =============================================================================

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using DataFrames
using Statistics
using Printf

# ─────────────────────────────────────────────────────────────────────────────
# Parameters
# ─────────────────────────────────────────────────────────────────────────────
const ROOT = datadir("DT_control", "exp_name=step1")
const INIT_RATE = 1e-4

# ─────────────────────────────────────────────────────────────────────────────
# Utility functions
# ─────────────────────────────────────────────────────────────────────────────

function _get(data, k::AbstractString)
    if haskey(data, k)
        return data[k]
    elseif haskey(data, Symbol(k))
        return data[Symbol(k)]
    else
        return nothing
    end
end

function _first_column(v)
    if ndims(v) == 1
        return collect(v)
    elseif ndims(v) == 2
        return vec(view(v, :, 1))
    else
        error("inj_rate_arr has unexpected dimension: $(ndims(v))")
    end
end

function last_nonzero_inj_rate(data; init_rate::Float64=INIT_RATE)
    raw = _get(data, "inj_rate_arr")
    raw === nothing && return init_rate
    col1 = _first_column(raw)
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? init_rate : clean[idx]
end

# ─────────────────────────────────────────────────────────────────────────────
# Main: Collect all cases
# ─────────────────────────────────────────────────────────────────────────────
all_dirs = filter(d -> 
    isdir(joinpath(ROOT, d)) && 
    !startswith(d, ".") && 
    d != "geo"
, readdir(ROOT))

rows = NamedTuple[]

for risk_name in all_dirs
    risk_dir = joinpath(ROOT, risk_name)
    is_pof = occursin("POF", risk_name)
    
    # Check all samples (1-128)
    for s in 1:128
        sdir = joinpath(risk_dir, "sample=$(s)")
        final_path = joinpath(sdir, "final.jld2")
        
        if isfile(final_path)
            try
                data = JLD2.load(final_path)
                last_inj = last_nonzero_inj_rate(data; init_rate=INIT_RATE)
                
                # Extract eps if POF
                eps = NaN
                if is_pof
                    m = match(r"eps\s*=\s*((?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+\-]?\d+)?)", risk_name)
                    if m !== nothing
                        eps = parse(Float64, m.captures[1])
                    end
                end
                
                push!(rows, (
                    case_name = risk_name,
                    is_pof = is_pof,
                    eps = eps,
                    sample = s,
                    last_inj_rate = last_inj
                ))
            catch err
                # Skip load errors
            end
        end
    end
end

df = DataFrame(rows)
println("Total completed cases: ", nrow(df))
println("  POF cases: ", sum(df.is_pof))
println("  Non-POF cases: ", sum(.!df.is_pof))

# ─────────────────────────────────────────────────────────────────────────────
# Statistics: Compare POF vs Non-POF
# ─────────────────────────────────────────────────────────────────────────────
if sum(df.is_pof) > 0 && sum(.!df.is_pof) > 0
    pof_rates = df[df.is_pof, :last_inj_rate]
    non_pof_rates = df[.!df.is_pof, :last_inj_rate]
    
    println("\n" * "="^80)
    println("INJECTION RATE COMPARISON")
    println("="^80)
    println("\nPOF Cases:")
    println("  Count: ", length(pof_rates))
    println("  Mean:  ", @sprintf("%.6f", mean(pof_rates)))
    println("  Median:", @sprintf("%.6f", median(pof_rates)))
    println("  Min:   ", @sprintf("%.6f", minimum(pof_rates)))
    println("  Max:   ", @sprintf("%.6f", maximum(pof_rates)))
    println("  Std:   ", @sprintf("%.6f", std(pof_rates)))
    
    println("\nNon-POF Cases:")
    println("  Count: ", length(non_pof_rates))
    println("  Mean:  ", @sprintf("%.6f", mean(non_pof_rates)))
    println("  Median:", @sprintf("%.6f", median(non_pof_rates)))
    println("  Min:   ", @sprintf("%.6f", minimum(non_pof_rates)))
    println("  Max:   ", @sprintf("%.6f", maximum(non_pof_rates)))
    println("  Std:   ", @sprintf("%.6f", std(non_pof_rates)))
    
    mean_diff = mean(pof_rates) - mean(non_pof_rates)
    median_diff = median(pof_rates) - median(non_pof_rates)
    rel_diff_mean = 100 * mean_diff / mean(non_pof_rates)
    rel_diff_median = 100 * median_diff / median(non_pof_rates)
    
    println("\nDifference (POF - Non-POF):")
    println("  Mean difference:   ", @sprintf("%+.6f (%.1f%%)", mean_diff, rel_diff_mean))
    println("  Median difference: ", @sprintf("%+.6f (%.1f%%)", median_diff, rel_diff_median))
    
    if mean_diff < 0
        println("\n✓ POF cases have SMALLER injection rates on average")
        println("  Consider reducing ex_step_size and inj_guess for POF cases")
    else
        println("\n✗ POF cases do NOT have systematically smaller injection rates")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Statistics by POF eps value
# ─────────────────────────────────────────────────────────────────────────────
if sum(.!isnan.(df.eps)) > 0
    println("\n" * "="^80)
    println("POF CASES BY EPS VALUE")
    println("="^80)
    
    df_pof = df[df.is_pof .&& .!isnan.(df.eps), :]
    g = groupby(df_pof, :eps)
    
    stats_by_eps = combine(g,
        :last_inj_rate => mean => :mean_inj,
        :last_inj_rate => median => :median_inj,
        :last_inj_rate => std => :std_inj,
        :last_inj_rate => minimum => :min_inj,
        :last_inj_rate => maximum => :max_inj,
        nrow => :count
    )
    sort!(stats_by_eps, :eps)
    
    println("\nEps | Count | Mean      | Median    | Std       | Min       | Max")
    println("-"^80)
    for r in eachrow(stats_by_eps)
        @printf("%.4f | %5d | %9.6f | %9.6f | %9.6f | %9.6f | %9.6f\n",
                r.eps, r.count, r.mean_inj, r.median_inj, r.std_inj, r.min_inj, r.max_inj)
    end
end

println("\n" * "="^80)
println("Analysis complete!")
println("="^80)

