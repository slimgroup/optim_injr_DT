#!/usr/bin/env julia
# Full 1920-day ground-truth forwards for the three-case comparison video.

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
const N_SUBSTEPS = 240
const GT_IDX = 2000
const CVAR_SENSITIVITY = 1.22

const POF_EPS001_RATES = [
    0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530,
    0.04530, 0.05087, 0.05645, 0.06203, 0.06760, 0.07317,
    0.07317, 0.07458, 0.07599, 0.07741, 0.07882, 0.08023,
    0.08023, 0.08041, 0.08059, 0.08078, 0.08096, 0.08114,
]
const CVAR_BASE_RATES = [
    0.00010, 0.01502, 0.02994, 0.04486, 0.05978, 0.07470,
    0.07470, 0.08282, 0.09094, 0.09906, 0.10717, 0.11529,
    0.11529, 0.11596, 0.11664, 0.11731, 0.11798, 0.11866,
    0.11866, 0.11897, 0.11928, 0.11960, 0.11991, 0.12022,
]

function substep_rates(case_key)
    if case_key == "POF_eps001"
        return repeat(POF_EPS001_RATES; inner=DS)
    elseif case_key == "CVaR_g01_a001_sensitivity"
        return repeat(CVAR_BASE_RATES .* CVAR_SENSITIVITY; inner=DS)
    elseif case_key == "No_Control"
        ramp = collect(range(0.0, 0.2, length=10))
        # Severe fracture occurs at day 728; injection is shut down afterward.
        return vcat(repeat(ramp[1:9]; inner=DS), [ramp[10]], zeros(N_SUBSTEPS - 91))
    end
    error("Unknown case: $case_key")
end

function contiguous_segments(rates)
    segments = Tuple{Int,Int,Float64}[]
    start_idx = 1
    for idx in 2:length(rates)
        if rates[idx] != rates[start_idx]
            push!(segments, (start_idx, idx - 1, rates[start_idx]))
            start_idx = idx
        end
    end
    push!(segments, (start_idx, length(rates), rates[start_idx]))
    return segments
end

function main()
    cases = ["POF_eps001", "CVaR_g01_a001_sensitivity", "No_Control"]
    task_id = parse(Int, get(ENV, "SLURM_ARRAY_TASK_ID", "0"))
    0 <= task_id < length(cases) || error("SLURM_ARRAY_TASK_ID must be 0:$(length(cases)-1)")
    case_key = cases[task_id + 1]
    rates = substep_rates(case_key)

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

    sat_all = zeros(Float32, N_GRID[1], N_GRID[end], N_SUBSTEPS)
    pres_all = zeros(Float32, N_GRID[1], N_GRID[end], N_SUBSTEPS)
    min_margin = zeros(Float64, N_SUBSTEPS)
    fractured_cells = zeros(Int, N_SUBSTEPS)
    prev = nothing

    println("Full-campaign video forward: case=$case_key")
    println("Segments: $(contiguous_segments(rates))")
    for (start_idx, end_idx, rate) in contiguous_segments(rates)
        nsteps = end_idx - start_idx + 1
        Sblk = jutulModeling(model, DT * ones(nsteps))
        well = jutulVWell(rate, [(inj_loc[1], inj_loc[2])];
                          startz=[inj_loc[3]], endz=[inj_loc[3] + 6 * D_CELL[3]])
        if start_idx == 1
            state0 = jutulSimpleState(model)
            state0[1:N_GRID[1]*N_GRID[3]] = vec(S0)
            states = Sblk(logTrans, well; state0=state0)
        else
            states = Sblk(logTrans, well; state0=prev)
        end
        prev = states.states[end]
        for local_idx in 1:nsteps
            idx = start_idx + local_idx - 1
            ncells = N_GRID[1] * N_GRID[3]
            sat = reshape(states.states[local_idx][1:ncells], N_GRID[1], N_GRID[end])
            pres = reshape(states.states[local_idx][ncells+1:end], N_GRID[1], N_GRID[end])
            margin = (p_max .- pres) ./ p_max
            sat_all[:, :, idx] = sat
            pres_all[:, :, idx] = pres
            min_margin[idx] = minimum(margin)
            fractured_cells[idx] = count(margin .< 0)
        end
        println("Completed substeps $start_idx:$end_idx at rate=$rate")
    end

    out_path = plotsdir("paper_figures", "full_campaign_video_$(case_key).jld2")
    JLD2.save(
        out_path,
        "case_key", case_key,
        "ground_truth_idx", GT_IDX,
        "dt_days", DT,
        "rate_by_substep", rates,
        "cvar_sensitivity_multiplier", case_key == "CVaR_g01_a001_sensitivity" ? CVAR_SENSITIVITY : 1.0,
        "p0", collect(p0),
        "p_max", collect(p_max),
        "sat_all", sat_all,
        "pres_all", pres_all,
        "min_margin_by_substep", min_margin,
        "fractured_cells_by_substep", fractured_cells,
    )
    println("Final min(r)=$(min_margin[end]); max fractured cells=$(maximum(fractured_cells))")
    println("Saved: $out_path")
end

main()
