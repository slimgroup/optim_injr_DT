#!/usr/bin/env julia
# Real ground-truth CVaR rate sensitivity through day 728.

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
const GT_IDX = 2000
const TARGET_DAY = 728.0
const MULTIPLIERS = [1.14, 1.16, 1.18, 1.20, 1.22, 1.24]
const BASE_RATES = [
    0.00010, 0.01502, 0.02994, 0.04486, 0.05978, 0.07470,
    0.07470, 0.08282, 0.09094, 0.09906,
]

function main()
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", "0"))
    0 <= task_id < length(MULTIPLIERS) || error("SLURM_ARRAY_TASK_ID must be 0:$(length(MULTIPLIERS)-1)")
    multiplier = MULTIPLIERS[task_id + 1]
    rates = BASE_RATES .* multiplier

    BroadK = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"), "BroadK")
    K = BroadK[GT_IDX, :, :] * JutulDarcyRules.md
    model = jutulModel(N_GRID, D_CELL, PHI, K1to3(K; kvoverkh=0.36); h=H_TOP)
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    logTrans = log.(Trans)
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * D_CELL[1], D_CELL[2], inj_y * D_CELL[3])
    p0 = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ 4.0e6

    S0 = zeros(Float64, N_GRID[1], N_GRID[end])
    Random.seed!(2025)
    for (rows, col_off) in [
        (249:251, -4), (248:252, -3), (247:253, -2), (246:254, -1),
        (246:254, 0), (246:254, 1), (247:253, 2), (248:252, 3), (249:251, 4)]
        S0[rows, inj_y + col_off] .= 0.5
    end

    prev = nothing
    final_sat = nothing
    final_pres = nothing
    remaining_days = TARGET_DAY
    for (period, rate) in enumerate(rates)
        period_days = min(DS * DT, remaining_days)
        period_days <= 0 && break
        nsteps = Int(round(period_days / DT))
        Sblk = jutulModeling(model, DT * ones(nsteps))
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
        ncells = N_GRID[1] * N_GRID[3]
        final_sat = reshape(prev[1:ncells], N_GRID[1], N_GRID[end])
        final_pres = reshape(prev[ncells+1:end], N_GRID[1], N_GRID[end])
        remaining_days -= period_days
    end

    margin = (p_max .- final_pres) ./ p_max
    tag = replace(@sprintf("%.2f", multiplier), "." => "p")
    out_path = plotsdir("paper_figures", "cvar_day728_sensitivity_$(tag)x.jld2")
    JLD2.save(
        out_path,
        "case_key", "CVaR_g01_a001_sensitivity",
        "multiplier", multiplier,
        "base_rates", BASE_RATES,
        "rates", rates,
        "active_rate_at_day728", rates[end],
        "ground_truth_idx", GT_IDX,
        "day", TARGET_DAY,
        "p0", collect(p0),
        "p_max", collect(p_max),
        "sat", final_sat,
        "pres", final_pres,
        "min_margin", minimum(margin),
        "fractured_cells", count(margin .< 0),
    )
    println("multiplier=$multiplier, active_rate=$(rates[end]), min(r)=$(minimum(margin)), fractured_cells=$(count(margin .< 0))")
    println("Saved: $out_path")
end

main()
