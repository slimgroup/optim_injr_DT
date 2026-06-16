#!/usr/bin/env julia
# Ground-truth PoF eps=0.01 rate-sensitivity trajectories over the full campaign.

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
const MULTIPLIERS = [1.50, 1.55, 1.60, 1.65, 1.70, 1.75, 1.80]
const BASE_RATES = [
    0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530,
    0.04530, 0.05087, 0.05645, 0.06203, 0.06760, 0.07317,
    0.07317, 0.07458, 0.07599, 0.07741, 0.07882, 0.08023,
    0.08023, 0.08041, 0.08059, 0.08078, 0.08096, 0.08114,
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

    n_substeps = length(rates) * DS
    max_load = zeros(Float64, n_substeps)
    fractured_cells = zeros(Int, n_substeps)
    prev = nothing

    for (period, rate) in enumerate(rates)
        Sblk = jutulModeling(model, DT * ones(DS))
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
        for local_idx in 1:DS
            idx = (period - 1) * DS + local_idx
            ncells = N_GRID[1] * N_GRID[3]
            pres = reshape(states.states[local_idx][ncells+1:end], N_GRID[1], N_GRID[end])
            load = pres ./ p_max
            max_load[idx] = maximum(load)
            fractured_cells[idx] = count(load .> 1.0)
        end
    end

    first_fracture_idx = findfirst(>(0), fractured_cells)
    tag = replace(@sprintf("%.2f", multiplier), "." => "p")
    out_path = plotsdir("paper_figures", "pof_eps001_full_campaign_sensitivity_$(tag)x.jld2")
    JLD2.save(
        out_path,
        "case_key", "POF_eps0p01_sensitivity",
        "multiplier", multiplier,
        "base_rates", BASE_RATES,
        "rates", rates,
        "ground_truth_idx", GT_IDX,
        "dt_days", DT,
        "max_pressure_load_by_substep", max_load,
        "fractured_cells_by_substep", fractured_cells,
        "first_fracture_day", isnothing(first_fracture_idx) ? NaN : first_fracture_idx * DT,
    )
    println("multiplier=$multiplier, max load=$(maximum(max_load)), max fractured cells=$(maximum(fractured_cells))")
    println("Saved: $out_path")
end

main()
