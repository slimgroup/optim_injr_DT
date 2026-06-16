#!/usr/bin/env julia
# First-step ground-truth substeps for a common-time real fracture comparison.

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using JLD2
using Random

const N_GRID = (512, 1, 256)
const D_CELL = (6.25, 100.0, 6.25)
const H_TOP = 0.0
const PHI = 0.25
const DS = 10
const DT = 8.0
const THRESHOLD = 4.0
const GT_IDX = 2000

const CASES = [
    ("POF_eps0", [0.00010, 0.00534, 0.01058, 0.01582, 0.02106, 0.02630]),
    ("CVaR_g01_a001", [0.00010, 0.01502, 0.02994, 0.04486, 0.05978, 0.07470]),
]

function build_sim(K)
    model = jutulModel(N_GRID, D_CELL, PHI, K1to3(K; kvoverkh=0.36); h=H_TOP)
    Sblk = jutulModeling(model, DT * ones(DS))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

function main()
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", "0"))
    0 <= task_id < length(CASES) || error("SLURM_ARRAY_TASK_ID must be 0:$(length(CASES)-1)")
    case_key, rates = CASES[task_id + 1]

    BroadK = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"), "BroadK")
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    sim = build_sim(K)
    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 1e6
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * D_CELL[1], D_CELL[2], inj_y * D_CELL[3])

    S0 = zeros(Float64, N_GRID[1], N_GRID[end])
    Random.seed!(2025)
    for (rows, col_off) in [
        (249:251, -4), (248:252, -3), (247:253, -2), (246:254, -1),
        (246:254, 0), (246:254, 1), (247:253, 2), (248:252, 3), (249:251, 4)]
        S0[rows, inj_y + col_off] .= 0.5
    end

    nt = length(rates) * DS
    sat_all = zeros(N_GRID[1], N_GRID[end], nt)
    pres_all = zeros(N_GRID[1], N_GRID[end], nt)
    prev = nothing
    println("First-step substeps: case=$case_key, rates=$rates")
    for period in eachindex(rates)
        well = jutulVWell(rates[period], [(inj_loc[1], inj_loc[2])];
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

    margins = [(p_max .- pres_all[:, :, idx]) ./ p_max for idx in axes(pres_all, 3)]
    min_margin = minimum.(margins)
    fractured_cells = count.(x -> x < 0, margins)
    out_path = plotsdir("paper_figures", "first_step_substeps_$(case_key).jld2")
    JLD2.save(
        out_path,
        "case_key", case_key,
        "rates", rates,
        "ground_truth_idx", GT_IDX,
        "dt_days", DT,
        "p0", collect(p0),
        "p_max", collect(p_max),
        "sat_all", sat_all,
        "pres_all", pres_all,
        "min_margin_by_substep", min_margin,
        "fractured_cells_by_substep", fractured_cells,
    )
    println("Worst day=$(argmin(min_margin) * DT), min(r)=$(minimum(min_margin))")
    println("Saved: $out_path")
end

main()
