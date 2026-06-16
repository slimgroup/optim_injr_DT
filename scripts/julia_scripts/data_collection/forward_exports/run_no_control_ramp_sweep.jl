#!/usr/bin/env julia
# Ground-truth no-control ramp sweep. Each Slurm array task runs one terminal rate.

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using JLD2
using Printf
using Random

const N_GRID = (512, 1, 256)
const D_CELL = (6.25, 100.0, 6.25)
const H_TOP = 0.0
const PHI = 0.25
const DS = 10
const DT = 8.0
const N_PERIODS_RUN = 6
const N_PERIODS_CAMPAIGN = 24
const THRESHOLD = 4.0
const GT_IDX = 2000
const TERMINAL_RATES = [0.40, 0.60, 0.80]

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
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", "0"))
    0 <= task_id < length(TERMINAL_RATES) || error("SLURM_ARRAY_TASK_ID must be 0:$(length(TERMINAL_RATES)-1)")
    terminal_rate = TERMINAL_RATES[task_id + 1]
    full_rates = collect(range(0.0, terminal_rate, length=N_PERIODS_CAMPAIGN))
    run_rates = full_rates[1:N_PERIODS_RUN]

    BroadK = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"), "BroadK")
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    sim = build_sim(K)
    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 1e6
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * D_CELL[1], D_CELL[2], inj_y * D_CELL[3])
    S0 = initial_saturation(inj_y)

    nt = N_PERIODS_RUN * DS
    sat_all = zeros(N_GRID[1], N_GRID[end], nt)
    pres_all = zeros(N_GRID[1], N_GRID[end], nt)
    prev = nothing

    println("No-control ramp sweep: terminal=$terminal_rate m3/s, first rates=$run_rates")
    for period in eachindex(run_rates)
        well = jutulVWell(run_rates[period], [(inj_loc[1], inj_loc[2])];
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
    tag = replace(@sprintf("%.2f", terminal_rate), "." => "p")
    out_path = plotsdir("paper_figures", "no_control_ramp_terminal_$(tag).jld2")
    JLD2.save(
        out_path,
        "terminal_rate", terminal_rate,
        "full_rates", full_rates,
        "run_rates", run_rates,
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
    println("Day 408: min(r)=$(min_margin[Int(408 / DT)]), fractured_cells=$(fractured_cells[Int(408 / DT)])")
    println("Day 480: min(r)=$(min_margin[end]), fractured_cells=$(fractured_cells[end])")
    println("Saved: $out_path")
end

main()
