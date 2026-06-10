#!/usr/bin/env julia
# Test slower no-control ramps and stop each real forward run at severe fracture.

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
const N_PERIODS = 24
const GT_IDX = 2000
const TERMINAL_RATE = 0.2
const RAMP_PERIODS = [8, 10, 12]
const SEVERE_MARGIN = -0.1

function main()
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", "0"))
    0 <= task_id < length(RAMP_PERIODS) || error("SLURM_ARRAY_TASK_ID must be 0:$(length(RAMP_PERIODS)-1)")
    ramp_periods = RAMP_PERIODS[task_id + 1]
    full_rates = vcat(collect(range(0.0, TERMINAL_RATE, length=ramp_periods)), fill(TERMINAL_RATE, N_PERIODS - ramp_periods))

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

    sat_all = Array{Float64, 3}(undef, N_GRID[1], N_GRID[end], 0)
    pres_all = Array{Float64, 3}(undef, N_GRID[1], N_GRID[end], 0)
    min_margin = Float64[]
    fractured_cells = Int[]
    prev = nothing
    severe_substep = 0

    println("Delayed no-control ramp: ramp_periods=$ramp_periods, full_rates=$full_rates")
    for period in eachindex(full_rates)
        rate = full_rates[period]
        well = jutulVWell(rate, [(inj_loc[1], inj_loc[2])];
                          startz=[inj_loc[3]], endz=[inj_loc[3] + 6 * D_CELL[3]])
        if period == 1
            state0 = jutulSimpleState(model)
            state0[1:N_GRID[1]*N_GRID[3]] = vec(S0)
            states = Sblk(logTrans, well; state0=state0)
        else
            states = Sblk(logTrans, well; state0=prev)
        end
        prev = states.states[end]

        period_sat = zeros(N_GRID[1], N_GRID[end], DS)
        period_pres = zeros(N_GRID[1], N_GRID[end], DS)
        for substep in 1:DS
            sat = reshape(states.states[substep][1:N_GRID[1]*N_GRID[3]], N_GRID[1], N_GRID[end])
            pres = reshape(states.states[substep][N_GRID[1]*N_GRID[3]+1:end], N_GRID[1], N_GRID[end])
            margin = (p_max .- pres) ./ p_max
            period_sat[:, :, substep] = sat
            period_pres[:, :, substep] = pres
            push!(min_margin, minimum(margin))
            push!(fractured_cells, count(margin .< 0))
            if severe_substep == 0 && min_margin[end] <= SEVERE_MARGIN
                severe_substep = length(min_margin)
            end
        end
        sat_all = cat(sat_all, period_sat; dims=3)
        pres_all = cat(pres_all, period_pres; dims=3)
        severe_substep > 0 && break
    end

    severe_day = severe_substep > 0 ? severe_substep * DT : NaN
    out_path = plotsdir("paper_figures", "no_control_delayed_ramp_$(ramp_periods)_periods.jld2")
    JLD2.save(
        out_path,
        "full_rates", full_rates,
        "simulated_rates", full_rates[1:(size(sat_all, 3) ÷ DS)],
        "ramp_periods", ramp_periods,
        "ground_truth_idx", GT_IDX,
        "dt_days", DT,
        "severe_margin_threshold", SEVERE_MARGIN,
        "severe_substep", severe_substep,
        "severe_day", severe_day,
        "p0", collect(p0),
        "p_max", collect(p_max),
        "sat_all", sat_all,
        "pres_all", pres_all,
        "min_margin_by_substep", min_margin,
        "fractured_cells_by_substep", fractured_cells,
    )
    println("Severe day=$severe_day; min(r)=$(minimum(min_margin)); simulated periods=$(size(sat_all, 3) ÷ DS)")
    println("Saved: $out_path")
end

main()
