#!/usr/bin/env julia
# Minimal ds comparison: one full forward reservoir simulation (960 days) per setting.
# Avoid unnecessary packages and their precompilation cost.

# Flush output promptly
flush(stdout)
flush(stderr)

using Pkg
Pkg.activate(".")

println("Loading packages...")
flush(stdout)

using DrWatson  # Provides datadir
println("  ✓ DrWatson loaded")
flush(stdout)

using JutulDarcyRules
println("  ✓ JutulDarcyRules loaded")
flush(stdout)

using LinearAlgebra
using JLD2
using Random
using Printf
println("  ✓ All packages loaded")
flush(stdout)

# Include only required functions, not the full optim_inject.jl entry point.
# Define the helpers directly to avoid loading unused packages such as PyPlot.

# Copy of build_sim from optim_inject.jl
function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_firstblock=80/ds)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    Sblk  = jutulModeling(model, dt_firstblock * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

println("=" ^ 80)
println("ds comparison: one full forward simulation (960 days) per setting")
println("=" ^ 80)

# Setup parameters
s = 128
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0
ϕ = 0.25
forward_step = 2

# Load data
println("\nLoading data...")
perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
perm_data = JLD2.load(perm_path)
BroadK = perm_data["BroadK"]

monitoring_step = 1
state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2")
state_data = JLD2.load(state_path)

idices = state_data["idx_t" * string(monitoring_step)]
idx = idices[s]
K = BroadK[idx, :, :] * JutulDarcyRules.md

p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10

# Initialize saturation
inj_y0 = 191 + argmax(K[250, 191:200]) - 1
S0 = zeros(Float64, n[1], n[end])
Random.seed!(2025 + s - 1)
value = 0.2 + rand(Float64) * 0.6
S0[249:251, inj_y0-4] .= value
S0[248:252, inj_y0-3] .= value
S0[247:253, inj_y0-2] .= value
S0[246:254, inj_y0-1] .= value
S0[246:254, inj_y0]   .= value
S0[246:254, inj_y0+1] .= value
S0[247:253, inj_y0+2] .= value
S0[248:252, inj_y0+3] .= value
S0[249:251, inj_y0+4] .= value
sat_init = S0

# Well location
inj_y = 191 + argmax(K[250, 191:200]) - 1
inj_loc_grid = (250, 1, inj_y)
inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])

# Fixed injection rate
inj_rate_base = 0.1
inj_start = 0.0001

println("\n" * "=" ^ 80)
println("Starting test: one full forward simulation (960 days)")
println("Total duration = 2 * 6 * 80 = 960 days")
println("=" ^ 80)

# Test different ds settings
ds_values = [1, 2, 5, 10]
results = Dict{Int, Dict{String, Any}}()

for ds in ds_values
    println("\n" * "-" ^ 80)
    println("Testing ds = $ds")
    println("-" ^ 80)
    
    # Build the simulator
    println("  Building simulator...")
    build_start = time()
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)
    build_time = time() - build_start
    
    # Configure the injection-rate schedule
    inj_rate_final = inj_rate_base
    inj_rate_seq = collect(range(inj_start, inj_rate_final, forward_step * 6))
    inj_len = length(inj_rate_seq)
    
    println("  Configuration:")
    println("    - dt_firstblock = $(80/ds) days")
    println("    - Time steps per Sblk call = $ds")
    println("    - Duration per Sblk call = $(ds * (80/ds)) days")
    println("    - Injection periods = $inj_len")
    println("    - Total duration = $inj_len × $(ds * (80/ds)) = $(inj_len * ds * (80/ds)) days")
    
    # Optional warmup
    println("  Warming up...")
    try
        f = jutulVWell(inj_rate_seq[1], [(inj_loc[1], inj_loc[2])];
                       startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])
        state0 = jutulSimpleState(sim.model)
        state0[1:n[1]*n[3]] = vec(sat_init)
        _ = sim.Sblk(sim.logTrans, f; state0=state0)
    catch e
        println("  Warmup failed: $e")
    end
    
    # Time the full forward simulation
    println("  Timing the full forward simulation...")
    start_time = time()
    
    previous_state = nothing
    for i in 1:inj_len
        f = jutulVWell(inj_rate_seq[i], [(inj_loc[1], inj_loc[2])];
                       startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])
        
        try
            if i == 1
                state0 = jutulSimpleState(sim.model)
                state0[1:n[1]*n[3]] = vec(sat_init)
                states = sim.Sblk(sim.logTrans, f; state0=state0)
            else
                states = sim.Sblk(sim.logTrans, f; state0=previous_state)
            end
            previous_state = states.states[end]
        catch e
            println("  Simulation failed in period $i: $e")
            break
        end
    end
    
    elapsed = time() - start_time
    
    # Record results
    total_time_steps = inj_len * ds
    results[ds] = Dict(
        "build_time" => build_time,
        "simulation_time" => elapsed,
        "total_time_steps" => total_time_steps,
        "time_per_step" => elapsed / total_time_steps,
        "inj_periods" => inj_len
    )
    
    println("  ✓ Completed")
    println("  - Build time: $(@sprintf("%.2f", build_time)) seconds")
    println("  - Full forward simulation: $(@sprintf("%.2f", elapsed)) seconds")
    println("  - Total time steps: $total_time_steps")
    println("  - Mean time per step: $(@sprintf("%.3f", elapsed/total_time_steps)) seconds/step")
    
    GC.gc()
end

# Summarize
println("\n" * "=" ^ 80)
println("Test results")
println("=" ^ 80)

if length(results) >= 2
    ds_list = sort(collect(keys(results)))
    base_ds = ds_list[1]
    base_time = results[base_ds]["simulation_time"]
    
    println("\nComparison (one full 960-day forward simulation):")
    println("-" ^ 80)
    println(@sprintf("  %-6s  %12s  %12s  %12s  %10s  %8s", 
                     "ds", "Runtime (s)", "Total steps", "s/step", "Periods", "Ratio"))
    println("-" ^ 80)
    
    for ds in ds_list
        r = results[ds]
        speedup = r["simulation_time"] / base_time
        println(@sprintf("  %-6d  %12.2f  %12d  %12.3f  %10d  %8.2fx", 
                         ds, r["simulation_time"], r["total_time_steps"], 
                         r["time_per_step"], r["inj_periods"], speedup))
    end
    
    println("\nFindings:")
    println("-" ^ 80)
    
    if haskey(results, 1) && haskey(results, 10)
        r1 = results[1]
        r10 = results[10]
        time_ratio = r10["simulation_time"] / r1["simulation_time"]
        steps_ratio = r10["total_time_steps"] / r1["total_time_steps"]
        
        println("  ds=10 relative to ds=1:")
        println("    - Runtime ratio: $(@sprintf("%.2f", time_ratio))x")
        println("    - Time-step count ratio: $(@sprintf("%.2f", steps_ratio))x")
        
        if time_ratio < steps_ratio
            println("  ✓ Runtime ratio ($(@sprintf("%.2f", time_ratio))x) < time-step ratio ($(@sprintf("%.2f", steps_ratio))x)")
            println("  Smaller-step solver convergence is a possible explanation; timing alone does not establish the cause")
        else
            println("  ⚠️  Runtime ratio is close to or above the time-step ratio")
        end
    end
    
    println("\n  Time per step:")
    for ds in ds_list
        r = results[ds]
        println("    ds=$(ds): $(@sprintf("%.3f", r["time_per_step"])) seconds/step")
    end
    
    println("\nSummary:")
    println("-" ^ 80)
    if haskey(results, 1) && haskey(results, 10)
        time_ratio = results[10]["simulation_time"] / results[1]["simulation_time"]
        println("  One full forward simulation (960 days):")
        println("    - ds=10 runtime ratio (nominal time-step ratio: 10x): $(@sprintf("%.1f", time_ratio))x")
    end
    println("  ds=10 is the reference setting; runtime alone does not validate time resolution")
else
    println("  Insufficient test data")
end

println("\n" * "=" ^ 80)

