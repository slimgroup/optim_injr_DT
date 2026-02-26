#!/usr/bin/env julia
# Forward simulation on ground truth K → export as JLD2 for Python plotting
# 3 cases: POF eps=0 | CVaR g=0.1 a=0.01 | No Control
# Uses 3x rate multiplier (consistent with video scripts)

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
const THRESHOLD = 4.0
const GT_IDX  = 2000
const MULT    = 3.0

cases = Dict(
    "POF_eps0"      => [0.000100, 0.003468, 0.006836, 0.010204, 0.013572, 0.016940],
    "CVaR_g01_a001" => [0.000100, 0.007584, 0.015068, 0.022552, 0.030036, 0.037520],
    "No_Control"    => collect(range(0.0, 0.1, length=6)),
)
case_order = ["POF_eps0", "CVaR_g01_a001", "No_Control"]

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

function main()
    println("Loading permeability...")
    perm_data = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"))
    BroadK = perm_data["BroadK"]
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    println("  K shape: $(size(K)),  GT idx: $GT_IDX")

    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 1e6

    println("Building simulation...")
    sim = build_sim(N_GRID, D_CELL, PHI, K)

    out_path = plotsdir("paper_figures", "forward_sim_data.jld2")
    mkpath(dirname(out_path))

    results = Dict{String,Any}(
        "p0"    => collect(p0),
        "p_max" => collect(p_max),
    )

    for ckey in case_order
        rates = cases[ckey] .* MULT
        println("\nCase: $ckey  rates(x$MULT): ", round.(rates; digits=5))

        sat_all, pres_all = run_forward(sim, K, rates)
        nt = size(sat_all, 3)

        r_final = (p_max .- pres_all[:,:,end]) ./ p_max
        println("  min(r)=$(minimum(r_final)),  frac cells=$(count(r_final .< 0))/$(length(r_final))")

        results["$(ckey)_rates"]      = rates
        results["$(ckey)_sat_final"]  = sat_all[:,:,end]
        results["$(ckey)_pres_final"] = pres_all[:,:,end]

        # Save snapshots at every 10th sub-step (= end of each injection period)
        snap_idx = collect(DS:DS:nt)
        results["$(ckey)_snap_idx"]   = snap_idx
        results["$(ckey)_sat_snaps"]  = sat_all[:,:,snap_idx]
        results["$(ckey)_pres_snaps"] = pres_all[:,:,snap_idx]
    end

    JLD2.save(out_path, results)
    println("\nSaved: $out_path  ($(filesize(out_path) / 1e6) MB)")
end

main()
