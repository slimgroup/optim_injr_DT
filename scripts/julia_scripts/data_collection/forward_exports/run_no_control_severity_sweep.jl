#!/usr/bin/env julia
# Ground-truth no-control rate sweep. Each Slurm array task runs one rate.

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using JLD2
using Printf
using Random

include(srcdir("utils.jl"))
setup_pycall()

const N_GRID = (512, 1, 256)
const D_CELL = (6.25, 100.0, 6.25)
const H_TOP = 0.0
const PHI = 0.25
const DS = 10
const DT = 8.0
const N_PERIODS = 6
const THRESHOLD = 4.0
const GT_IDX = 2000
const RATES = [0.10, 0.15, 0.20]

function build_sim(K)
    model = jutulModel(N_GRID, D_CELL, PHI, K1to3(K; kvoverkh=0.36); h=H_TOP)
    Sblk = jutulModeling(model, DT * ones(DS))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

function initial_saturation(inj_y)
    S0 = zeros(Float64, N_GRID[1], N_GRID[end])
    Random.seed!(2025)
    for (rows, col_off) in [
        (249:251, -4), (248:252, -3), (247:253, -2), (246:254, -1),
        (246:254, 0), (246:254, 1), (247:253, 2), (248:252, 3), (249:251, 4)]
        S0[rows, inj_y + col_off] .= 0.5
    end
    return S0
end

function main()
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", get(ENV, "RATE_TASK_ID", "0")))
    0 <= task_id < length(RATES) || error("RATE_TASK_ID must be 0:$(length(RATES)-1)")
    rate = RATES[task_id + 1]

    BroadK = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"), "BroadK")
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    sim = build_sim(K)

    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 1e6
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * D_CELL[1], D_CELL[2], inj_y * D_CELL[3])
    S0 = initial_saturation(inj_y)

    nt = N_PERIODS * DS
    sat_all = zeros(N_GRID[1], N_GRID[end], nt)
    pres_all = zeros(N_GRID[1], N_GRID[end], nt)
    prev = nothing

    println("No-control severity sweep: rate=$rate m3/s, GT=BroadK[$GT_IDX,:,:]")
    for period in 1:N_PERIODS
        well = jutulVWell(rate, [(inj_loc[1], inj_loc[2])];
                          startz=[inj_loc[3]], endz=[inj_loc[3] + 6 * D_CELL[3]])
        if period == 1
            state0 = jutulSimpleState(sim.model)
            state0[1:N_GRID[1]*N_GRID[3]] = vec(S0)
            states = sim.Sblk(sim.logTrans, well; state0=state0)
        else
            states = sim.Sblk(sim.logTrans, well; state0=prev)
        end
        prev = states.states[end]
        for substep in 1:DS
            idx = (period - 1) * DS + substep
            sat_all[:, :, idx] = reshape(states.states[substep][1:N_GRID[1]*N_GRID[3]], N_GRID[1], N_GRID[end])
            pres_all[:, :, idx] = reshape(states.states[substep][N_GRID[1]*N_GRID[3]+1:end], N_GRID[1], N_GRID[end])
        end
    end

    min_margin = [minimum((p_max .- pres_all[:, :, idx]) ./ p_max) for idx in axes(pres_all, 3)]
    fractured_cells = [count((p_max .- pres_all[:, :, idx]) ./ p_max .< 0) for idx in axes(pres_all, 3)]
    worst_idx = argmin(min_margin)
    tag = replace(@sprintf("%.2f", rate), "." => "p")
    out_path = plotsdir("paper_figures", "no_control_severity_rate_$(tag).jld2")
    JLD2.save(
        out_path,
        "rate", rate,
        "ground_truth_idx", GT_IDX,
        "dt_days", DT,
        "p0", collect(p0),
        "p_max", collect(p_max),
        "sat_all", sat_all,
        "pres_all", pres_all,
        "min_margin_by_substep", min_margin,
        "fractured_cells_by_substep", fractured_cells,
        "worst_substep", worst_idx,
        "worst_day", worst_idx * DT,
    )
    println("Worst day=$(worst_idx * DT), min(r)=$(min_margin[worst_idx]), fractured_cells=$(fractured_cells[worst_idx])")
    println("Day 480: min(r)=$(min_margin[end]), fractured_cells=$(fractured_cells[end])")
    println("Saved: $out_path")
end

main()
