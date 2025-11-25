#!/usr/bin/env julia
# Quick script to view gamma lookup table contents

using Pkg
Pkg.activate(".")

using JLD2
using Printf

if length(ARGS) < 1
    println("Usage: julia view_gamma_table.jl <path_to_gamma_table.jld2>")
    exit(1)
end

table_path = ARGS[1]

if !isfile(table_path)
    println("ERROR: File not found: $table_path")
    exit(1)
end

data = JLD2.load(table_path)

println("=" ^ 80)
println("Gamma Lookup Table Contents")
println("=" ^ 80)
println("File: $table_path")
println()

thresholds = data["thresholds"]
eps_values = data["eps_values"]
entries = data["gamma_entries"]
meta = data["meta"]

println("Metadata:")
println("  Sample index: $(meta.idx)")
println("  Alpha (tail level): $(meta.alpha)")
println("  Injection guess: $(meta.inj_guess)")
println("  Timestamp: $(meta.timestamp)")
println()

println("Thresholds: $thresholds")
println("Eps values: $eps_values")
println()

println("=" ^ 80)
println("Gamma Values (threshold, eps) → gamma")
println("=" ^ 80)

for eps in eps_values
    println("\nEps = $eps:")
    println("  " * "-" ^ 76)
    println("  " * @sprintf("%-12s %-15s %-15s %-15s", "Threshold", "Gamma", "POF (hard)", "CVaR"))
    println("  " * "-" ^ 76)
    
    per_eps = entries[eps]
    for thresh in thresholds
        entry = per_eps[thresh]
        println("  " * @sprintf("%-12.2f %-15.6e %-15.6f %-15.6e", 
                               thresh, entry.gamma, entry.pof, entry.cvar))
    end
end

println("\n" * "=" ^ 80)
println("Total entries: $(length(thresholds) * length(eps_values))")
println("=" ^ 80)

