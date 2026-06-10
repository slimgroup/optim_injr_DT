#!/usr/bin/env julia
# Advance saved ground-truth controlled states from day 720 to day 728.

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using JLD2

const N_GRID = (512, 1, 256)
const D_CELL = (6.25, 100.0, 6.25)
const H_TOP = 0.0
const PHI = 0.25
const DT = 8.0
const GT_IDX = 2000
const SOURCE_PERIOD = 9
const TARGET_PERIOD = 10
const CASES = ["POF_eps0", "CVaR_g01_a001"]

function main()
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", "0"))
    0 <= task_id < length(CASES) || error("SLURM_ARRAY_TASK_ID must be 0:$(length(CASES)-1)")
    case_key = CASES[task_id + 1]

    BroadK = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"), "BroadK")
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    model = jutulModel(N_GRID, D_CELL, PHI, K1to3(K; kvoverkh=0.36); h=H_TOP)
    Sblk = jutulModeling(model, [DT])
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))

    source = JLD2.load(plotsdir("paper_figures", "forward_sim_four_steps_base_data.jld2"))
    sat720 = source["$(case_key)_sat_snaps"][:, :, SOURCE_PERIOD]
    pres720 = source["$(case_key)_pres_snaps"][:, :, SOURCE_PERIOD]
    rates = source["$(case_key)_rates"]
    rate728 = rates[TARGET_PERIOD]

    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * D_CELL[1], D_CELL[2], inj_y * D_CELL[3])
    well = jutulVWell(rate728, [(inj_loc[1], inj_loc[2])];
                      startz=[inj_loc[3]], endz=[inj_loc[3] + 6 * D_CELL[3]])

    state0 = jutulSimpleState(model)
    ncells = N_GRID[1] * N_GRID[3]
    state0[1:ncells] = vec(sat720)
    state0[ncells+1:end] = vec(pres720)
    states = Sblk(log.(Trans), well; state0=state0)
    state728 = states.states[end]
    sat728 = reshape(state728[1:ncells], N_GRID[1], N_GRID[end])
    pres728 = reshape(state728[ncells+1:end], N_GRID[1], N_GRID[end])
    p_max = source["p_max"]
    margin728 = (p_max .- pres728) ./ p_max

    out_path = plotsdir("paper_figures", "controlled_day728_$(case_key).jld2")
    JLD2.save(
        out_path,
        "case_key", case_key,
        "rates", rates,
        "rate_at_day728", rate728,
        "ground_truth_idx", GT_IDX,
        "day", 728.0,
        "p0", source["p0"],
        "p_max", p_max,
        "sat", sat728,
        "pres", pres728,
        "min_margin", minimum(margin728),
        "fractured_cells", count(margin728 .< 0),
    )
    println("case=$case_key, day=728, rate=$rate728, min(r)=$(minimum(margin728)), fractured_cells=$(count(margin728 .< 0))")
    println("Saved: $out_path")
end

main()
