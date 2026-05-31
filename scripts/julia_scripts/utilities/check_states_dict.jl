# Diagnostic script: inspect reservoir simulation output states dictionary
# and compare BHP with reservoir pressure at well grid points.

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using JLD2
using Random
using Printf

# ── Domain ──
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0
ϕ = 0.25
ds = 10

# ── Load permeability ──
perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
perm_data = JLD2.load(perm_path)
BroadK = perm_data["BroadK"]

state_path = datadir("state/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2")
state_data = JLD2.load(state_path)
idices = state_data["idx_t1"]

s = 128
idx = idices[s]
K = BroadK[idx, :, :] * JutulDarcyRules.md

# ── Pressure bounds ──
p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
p_max = p0' .+ 4.0 * 10^6

# ── Initial saturation ──
inj_y = 191 + argmax(K[250, 191:200]) - 1
S0 = zeros(Float64, n[1], n[end])
Random.seed!(2025 + s - 1)
value = 0.2 + rand(Float64) * 0.6
S0[249:251, inj_y-4] .= value
S0[248:252, inj_y-3] .= value
S0[247:253, inj_y-2] .= value
S0[246:254, inj_y-1] .= value
S0[246:254, inj_y]   .= value
S0[246:254, inj_y+1] .= value
S0[247:253, inj_y+2] .= value
S0[248:252, inj_y+3] .= value
S0[249:251, inj_y+4] .= value

# ── Build simulation ──
model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
Sblk  = jutulModeling(model, (80.0 / ds) * ones(ds))
Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
logTrans = log.(Trans)

# ── Well setup ──
inj_loc_grid = (250, 1, inj_y)
inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])

println("=" ^ 70)
println("WELL LOCATION")
println("=" ^ 70)
println("  inj_y (z-index) = $inj_y")
println("  inj_loc_grid    = $inj_loc_grid")
println("  inj_loc (m)     = $inj_loc")
println("  well startz     = $(inj_loc[3]) m  (z-index $(inj_y))")
println("  well endz       = $(inj_loc[3] + 6*d[3]) m  (z-index $(inj_y + 6))")
println()

# ── Run single forward simulation with moderate injection rate ──
inj_rate_test = 0.05
println("Using moderate injection rate = $inj_rate_test")
println()

f = jutulVWell(inj_rate_test, [(inj_loc[1], inj_loc[2])];
               startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])

state0 = jutulSimpleState(model)
state0[1:n[1]*n[3]] = vec(S0)

println("Running forward simulation (1 block, $ds timesteps of $(80.0/ds) days each)...")
states = Sblk(logTrans, f; state0=state0)
println("Simulation complete!")
println()

# ═══════════════════════════════════════════════════════════════════════════════
# PART 1: Inspect the states dictionary structure
# ═══════════════════════════════════════════════════════════════════════════════
println("=" ^ 70)
println("PART 1: STATES DICTIONARY STRUCTURE")
println("=" ^ 70)

println("\ntypeof(states) = ", typeof(states))
println("fieldnames(states) = ", fieldnames(typeof(states)))
println("Number of timesteps: length(states.states) = ", length(states.states))
println()

st1 = states.states[1]
println("--- Inspecting states.states[1] ---")
println("typeof(states.states[1]) = ", typeof(st1))
println("length(states.states[1]) = ", length(st1))
println()

if hasproperty(st1, :state)
    println("states.states[1].state exists")
    println("typeof(.state) = ", typeof(st1.state))
    if isa(st1.state, AbstractDict)
        println("Keys in .state: ", collect(keys(st1.state)))
        for k in keys(st1.state)
            v = st1.state[k]
            println("  :$k => typeof=$(typeof(v))")
            if isa(v, AbstractDict)
                println("    Sub-keys: ", collect(keys(v)))
                for sk in keys(v)
                    sv = v[sk]
                    println("    :$sk => typeof=$(typeof(sv)), size/length=$(isa(sv, AbstractArray) ? size(sv) : length(sv))")
                end
            elseif isa(v, AbstractArray)
                println("    size=$(size(v)), length=$(length(v))")
            end
        end
    else
        println("  .state is not a Dict, trying to iterate fields...")
        for fn in fieldnames(typeof(st1.state))
            println("  field :$fn => typeof=$(typeof(getfield(st1.state, fn)))")
        end
    end
else
    println("states.states[1] does not have a .state property")
    println("Trying fieldnames: ", fieldnames(typeof(st1)))
end
println()

# Also try to print available properties/methods
println("--- Trying different access patterns ---")
try
    bhp = st1.state[:Injector][:Pressure]
    println("st1.state[:Injector][:Pressure] => length=$(length(bhp)), values=$bhp")
catch e
    println("st1.state[:Injector][:Pressure] failed: $e")
end
println()

# ═══════════════════════════════════════════════════════════════════════════════
# PART 2: BHP vs Reservoir Pressure at well grid points
# ═══════════════════════════════════════════════════════════════════════════════
println("=" ^ 70)
println("PART 2: BHP vs RESERVOIR PRESSURE COMPARISON")
println("=" ^ 70)

for k in 1:ds
    stk = states.states[k]
    pres_flat = stk[n[1]*n[3]+1:end]
    pres_2d = reshape(pres_flat, n[1], n[end])

    bhp = stk.state[:Injector][:Pressure]
    println("\n--- Timestep $k ---")
    println("BHP vector: length = $(length(bhp))")

    x_idx = 250
    println("\nReservoir pressure at well column (x=$x_idx, z=inj_y-1 to inj_y+8):")
    z_range = max(1, inj_y-2):min(n[3], inj_y+9)
    for z in z_range
        p_res = pres_2d[x_idx, z]
        marker = (z >= inj_y && z <= inj_y + length(bhp) - 1) ? " <-- well" : ""
        @printf("  z=%3d: pres = %.4f MPa%s\n", z, p_res/1e6, marker)
    end

    println("\nBHP vs Reservoir Pressure at corresponding grid points:")
    println(@sprintf("  %-5s  %-15s  %-15s  %-15s  %-8s", "idx", "BHP (MPa)", "P_res (MPa)", "Diff (MPa)", "BHP < P?"))
    println("  " * "-"^65)

    for (j, bhp_j) in enumerate(bhp)
        z_well = inj_y + j - 1
        if z_well >= 1 && z_well <= n[3]
            p_res = pres_2d[x_idx, z_well]
            diff = bhp_j - p_res
            lt = bhp_j < p_res ? "YES" : "NO"
            @printf("  %-5d  %-15.6f  %-15.6f  %-15.6f  %-8s\n", j, bhp_j/1e6, p_res/1e6, diff/1e6, lt)
        end
    end

    println("\n  p_max (fracture) at well column for reference:")
    for j in 1:length(bhp)
        z_well = inj_y + j - 1
        if z_well >= 1 && z_well <= n[3]
            @printf("  z=%3d: p_max = %.4f MPa\n", z_well, p_max[z_well, x_idx]/1e6)
        end
    end

    if k == ds
        println("\n\n=== SUMMARY (last timestep) ===")
        all_less = true
        for (j, bhp_j) in enumerate(bhp)
            z_well = inj_y + j - 1
            if z_well >= 1 && z_well <= n[3]
                p_res = pres_2d[x_idx, z_well]
                if bhp_j >= p_res
                    all_less = false
                end
            end
        end
        println("All BHP < reservoir pressure? ", all_less ? "YES" : "NO")
    end
end

println("\n\nDone!")
