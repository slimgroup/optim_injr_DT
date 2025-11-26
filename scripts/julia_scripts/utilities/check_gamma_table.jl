#!/usr/bin/env julia
# Check gamma table metadata and accuracy

# Set Julia depot path (same as submit scripts) - do this BEFORE loading Pkg
if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
    if !haskey(ENV, "JULIA_DEPOT_PATH")
        ENV["JULIA_DEPOT_PATH"] = get(ENV, "HOME", "") * "/julia-depot"
    end
    mkpath(ENV["JULIA_DEPOT_PATH"])
    println("Using Julia depot: $(ENV["JULIA_DEPOT_PATH"])")
end

using Pkg
Pkg.activate(".")

# Only instantiate if DrWatson is not available (avoid unnecessary reinstalls)
try
    using DrWatson
catch
    println("DrWatson not found, running Pkg.instantiate()...")
    Pkg.instantiate()
    using DrWatson
end

@quickactivate "optim_injr_DT"

using JLD2
using Printf

# PyCall setup (if needed)
if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
    include(joinpath(@__DIR__, "..", "..", "..", "src", "utils.jl"))
    setup_pycall()
end

function check_gamma_table(table_path::String)
    if !isfile(table_path)
        error("Gamma table not found: $(table_path)")
    end
    
    data = JLD2.load(table_path)
    
    println("=" ^ 80)
    println("Gamma Table Information")
    println("=" ^ 80)
    println("File: $(table_path)")
    println()
    
    # Check metadata
    meta = get(data, "meta", nothing)
    if meta !== nothing
        println("Metadata:")
        println("  Sample index: $(meta.idx)")
        println("  Alpha (tail level): $(meta.alpha)")
        println("  Timestamp: $(meta.timestamp)")
        println("  Injection rate guess: $(meta.inj_guess)")
        println()
    end
    
    # Check entries
    entries = get(data, "gamma_entries", nothing)
    if entries === nothing
        error("Gamma table missing 'gamma_entries' key")
    end
    
    eps_values = get(data, "eps_values", Float64[])
    thresholds = get(data, "thresholds", Float64[])
    
    println("Eps values in table: ", eps_values)
    println("Thresholds in table: ", thresholds)
    println()
    
    # Check accuracy for each (eps, threshold) pair
    println("=" ^ 80)
    println("Gamma Table Entries (checking POF accuracy)")
    println("=" ^ 80)
    println(@sprintf("%-8s %-10s %-12s %-12s %-12s %-15s", 
                     "Eps", "Threshold", "POF (hard)", "POF (smooth)", "CVaR", "Gamma"))
    println("-" ^ 80)
    
    for eps in eps_values
        per_eps = entries[eps]
        for thresh in thresholds
            entry = per_eps[thresh]
            pof_diff = abs(entry.pof - eps)
            pof_accuracy = pof_diff / eps * 100  # Percentage error
            
            status = pof_accuracy < 5.0 ? "✓" : "⚠️"
            println(@sprintf("%-8.4f %-10.2f %-12.6f %-12.6f %-12.6f %-15.6f %s (POF error: %.1f%%)",
                           eps, thresh, entry.pof, entry.pof, entry.cvar, entry.gamma, 
                           status, pof_accuracy))
        end
    end
    println("-" ^ 80)
    println()
    
    # Summary
    println("=" ^ 80)
    println("Summary")
    println("=" ^ 80)
    println("✓ = POF within 5% of target eps")
    println("⚠️  = POF error > 5% (may need regeneration with improved method)")
    println()
    println("Note: If you see many ⚠️, consider regenerating the gamma table")
    println("      with the improved binary search method for better accuracy.")
end

# Main
if length(ARGS) > 0
    table_path = ARGS[1]
else
    # Default path
    table_path = "scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2"
    println("No path provided, using default: $(table_path)")
    println()
end

check_gamma_table(table_path)

