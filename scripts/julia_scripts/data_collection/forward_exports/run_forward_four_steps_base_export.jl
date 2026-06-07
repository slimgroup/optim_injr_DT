#!/usr/bin/env julia
# Four-step forward simulation on ground-truth permeability.
# Uses documented base-rate schedules without visualization multipliers.

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using JLD2
using Random

include(srcdir("utils.jl"))
setup_pycall()

const N_GRID  = (512, 1, 256)
const D_CELL  = (6.25, 100.0, 6.25)
const H_TOP   = 0.0
const PHI     = 0.25
const DS      = 10
const DT      = 8.0
const PERIOD_DAYS = DS * DT
const THRESHOLD = 4.0
const GT_IDX  = 2000
const MULT    = 1.0

# Arrays are copied directly from docs/injection_rate_arrays.md.
cases = Dict(
    "POF_eps0" => [
        0.00010, 0.00534, 0.01058, 0.01582, 0.02106, 0.02630,
        0.02630, 0.03002, 0.03373, 0.03745, 0.04117, 0.04489,
        0.04489, 0.04831, 0.05174, 0.05516, 0.05859, 0.06201,
        0.06201, 0.06425, 0.06650, 0.06874, 0.07099, 0.07323,
    ],
    "POF_eps0p01" => [
        0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530,
        0.04530, 0.05087, 0.05645, 0.06203, 0.06760, 0.07317,
        0.07317, 0.07458, 0.07599, 0.07741, 0.07882, 0.08023,
        0.08023, 0.08041, 0.08059, 0.08078, 0.08096, 0.08114,
    ],
    "CVaR_g01_a001" => [
        0.00010, 0.01502, 0.02994, 0.04486, 0.05978, 0.07470,
        0.07470, 0.08282, 0.09094, 0.09906, 0.10717, 0.11529,
        0.11529, 0.11596, 0.11664, 0.11731, 0.11798, 0.11866,
        0.11866, 0.11897, 0.11928, 0.11960, 0.11991, 0.12022,
    ],
    # Non-optimized baseline: constant uncontrolled injection with no artificial shutdown.
    # The forward simulation determines the actual fracture onset.
    "No_Control" => fill(0.1, 24),
)
case_order = ["POF_eps0", "POF_eps0p01", "CVaR_g01_a001", "No_Control"]

function build_sim(n, d, phi, K; h=0.0, ds=DS, dt=DT)
    model = jutulModel(n, d, phi, K1to3(K; kvoverkh=0.36); h=h)
    Sblk  = jutulModeling(model, dt * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

function run_forward(sim, K, inj_rates; n=N_GRID, d=D_CELL, h=H_TOP, ds=DS)
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250*d[1], 1*d[2], inj_y*d[3])

    S0 = zeros(Float64, n[1], n[end])
    Random.seed!(2025)
    v = 0.5
    for (rows, col_off) in [
        (249:251, -4), (248:252, -3), (247:253, -2), (246:254, -1),
        (246:254,  0), (246:254,  1), (247:253,  2), (248:252,  3), (249:251, 4)]
        S0[rows, inj_y + col_off] .= v
    end

    np = length(inj_rates)
    nt = np * ds
    sat_all  = zeros(n[1], n[end], nt)
    pres_all = zeros(n[1], n[end], nt)

    prev = nothing
    for i in 1:np
        f = jutulVWell(inj_rates[i], [(inj_loc[1], inj_loc[2])];
                       startz=[inj_loc[3]], endz=[inj_loc[3]+6*d[3]])
        if i == 1
            s0 = jutulSimpleState(sim.model)
            s0[1:n[1]*n[3]] = vec(S0)
            states = sim.Sblk(sim.logTrans, f; state0=s0)
        else
            states = sim.Sblk(sim.logTrans, f; state0=prev)
        end
        prev = states.states[end]
        for j in 1:ds
            idx = (i-1)*ds + j
            sat_all[:,:,idx]  = reshape(states.states[j][1:n[1]*n[3]], n[1], n[end])
            pres_all[:,:,idx] = reshape(states.states[j][n[1]*n[3]+1:end], n[1], n[end])
        end
    end
    return sat_all, pres_all
end

function first_fracture_index(p_max, pres_all)
    for idx in axes(pres_all, 3)
        if any((p_max .- pres_all[:,:,idx]) ./ p_max .< 0)
            return idx
        end
    end
    return 0
end

function main()
    println("Loading ground-truth permeability: BroadK[$GT_IDX, :, :]")
    perm_data = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"))
    BroadK = perm_data["BroadK"]
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md

    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 1e6
    sim = build_sim(N_GRID, D_CELL, PHI, K)

    out_path = plotsdir("paper_figures", "forward_sim_four_steps_base_data.jld2")
    mkpath(dirname(out_path))
    results = Dict{String,Any}(
        "p0" => collect(p0),
        "p_max" => collect(p_max),
        "period_days" => PERIOD_DAYS,
        "rate_multiplier" => MULT,
        "ground_truth_idx" => GT_IDX,
    )

    for ckey in case_order
        rates = cases[ckey] .* MULT
        println("\nCase: $ckey rates (base, m3/s): ", round.(rates; digits=5))
        sat_all, pres_all = run_forward(sim, K, rates)
        nt = size(sat_all, 3)
        snap_idx = collect(DS:DS:nt)
        frac_idx = first_fracture_index(p_max, pres_all)
        frac_day = frac_idx == 0 ? NaN : frac_idx * DT

        results["$(ckey)_rates"] = rates
        results["$(ckey)_snap_idx"] = snap_idx
        results["$(ckey)_sat_snaps"] = sat_all[:,:,snap_idx]
        results["$(ckey)_pres_snaps"] = pres_all[:,:,snap_idx]
        results["$(ckey)_first_fracture_substep"] = frac_idx
        results["$(ckey)_first_fracture_day"] = frac_day

        r_final = (p_max .- pres_all[:,:,end]) ./ p_max
        println("  first fracture day: $frac_day")
        println("  final min(r): $(minimum(r_final))")
        println("  final fractured cells: $(count(r_final .< 0)) / $(length(r_final))")
    end

    JLD2.save(out_path, results)
    println("\nSaved: $out_path")
end

main()
