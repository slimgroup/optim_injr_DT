#!/usr/bin/env julia
# Final no-control baseline: ramp from 0 to 0.2 during step 1, then hold 0.2.

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
const GT_IDX = 2000
const FULL_RATES = vcat(collect(range(0.0, 0.2, length=6)), fill(0.2, 18))
const RUN_RATES = FULL_RATES[1:6]

function main()
    BroadK = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"), "BroadK")
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    model = jutulModel(N_GRID, D_CELL, PHI, K1to3(K; kvoverkh=0.36); h=H_TOP)
    Sblk = jutulModeling(model, DT * ones(DS))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    logTrans = log.(Trans)
    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ 4.0e6
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * D_CELL[1], D_CELL[2], inj_y * D_CELL[3])

    S0 = zeros(Float64, N_GRID[1], N_GRID[end])
    Random.seed!(2025)
    for (rows, col_off) in [
        (249:251, -4), (248:252, -3), (247:253, -2), (246:254, -1),
        (246:254, 0), (246:254, 1), (247:253, 2), (248:252, 3), (249:251, 4)]
        S0[rows, inj_y + col_off] .= 0.5
    end

    nt = length(RUN_RATES) * DS
    sat_all = zeros(N_GRID[1], N_GRID[end], nt)
    pres_all = zeros(N_GRID[1], N_GRID[end], nt)
    prev = nothing
    println("No-control mid-fracture schedule: $FULL_RATES")
    for period in eachindex(RUN_RATES)
        well = jutulVWell(RUN_RATES[period], [(inj_loc[1], inj_loc[2])];
                          startz=[inj_loc[3]], endz=[inj_loc[3] + 6 * D_CELL[3]])
        if period == 1
            state0 = jutulSimpleState(model)
            state0[1:N_GRID[1]*N_GRID[3]] = vec(S0)
            states = Sblk(logTrans, well; state0=state0)
        else
            states = Sblk(logTrans, well; state0=prev)
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
    out_path = plotsdir("paper_figures", "no_control_mid_fracture.jld2")
    JLD2.save(
        out_path,
        "full_rates", FULL_RATES,
        "run_rates", RUN_RATES,
        "ground_truth_idx", GT_IDX,
        "dt_days", DT,
        "p0", collect(p0),
        "p_max", collect(p_max),
        "sat_all", sat_all,
        "pres_all", pres_all,
        "min_margin_by_substep", min_margin,
        "fractured_cells_by_substep", fractured_cells,
    )
    println("Day 408: min(r)=$(min_margin[Int(408 / DT)]), fractured_cells=$(fractured_cells[Int(408 / DT)])")
    println("Day 480: min(r)=$(min_margin[end]), fractured_cells=$(fractured_cells[end])")
    println("Saved: $out_path")
end

main()
