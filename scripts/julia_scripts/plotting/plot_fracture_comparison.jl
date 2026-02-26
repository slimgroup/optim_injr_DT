#!/usr/bin/env julia
# ─────────────────────────────────────────────────────────────────────────────
# Paper figure: Fracture vs Non-Fracture Forward Simulation Comparison
#
# Runs forward simulation on ground truth permeability (sample 2000) for:
#   - POF-controlled case (non-fracture): conservative injection → r > 0 everywhere
#   - CVaR-controlled case (fracture): higher injection → r < 0 in some regions
#
# Y-axis shows relative pressure margin: r = (p_frac − p) / p_frac
#   r > 0  ⟹  safe (below fracture pressure)
#   r < 0  ⟹  fractured (exceeded fracture pressure)
#
# Injection rates loaded from optimization results (final.jld2).
# Rates are optionally scaled by INJ_RATE_MULTIPLIER for clear visualization.
# ─────────────────────────────────────────────────────────────────────────────

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using LinearAlgebra
using PyPlot
using JLD2
using Random
using PyCall
@pyimport cmasher
using Printf
using Dates

include(srcdir("utils.jl"))
setup_pycall()

# ═════════════════════════════════════════════════════════════════════════════
# CONFIGURATION — adjust these to select the cases you want
# ═════════════════════════════════════════════════════════════════════════════

# Sample index (1-128) in the optimization runs
const SAMPLE_IDX = 1

# Rate multiplier (set to 1.0 for actual optimized rates;
# set to 3.0 to match the 5-case video visualization)
const INJ_RATE_MULTIPLIER = 3.0

# Forward simulation parameters
const FORWARD_STEP = 2     # MPC forward horizon
const DS           = 10    # sub-steps per injection period
const DT_PER_STEP  = 8.0   # days per sub-step  (= 80/DS)

# Domain
const N_GRID  = (512, 1, 256)
const D_CELL  = (6.25, 100.0, 6.25)
const H_TOP   = 0.0
const PHI     = 0.25
const THRESHOLD = 4.0       # fracture pressure above hydrostatic [MPa]
const INJ_START = 0.0001    # ramp starting rate

# Ground truth permeability
const GROUND_TRUTH_IDX = 2000

# Case directories under data/DT_control/exp_name=step1/
const POF_CASE_DIR  = "POF__HARD__eps=0.0__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
const CVAR_CASE_DIR = "CVaR__HARD__alpha=0.01__gamma=0.1__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0"

# Labels for the figure
const POF_LABEL  = "POF  (ε = 0)"
const CVAR_LABEL = "CVaR (γ = 0.1, α = 0.01)"

# ═════════════════════════════════════════════════════════════════════════════
# Helper: build simulation block
# ═════════════════════════════════════════════════════════════════════════════
function build_sim(n, d, ϕ, K; h=0.0, ds=DS, dt_per_step=DT_PER_STEP)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    Sblk  = jutulModeling(model, dt_per_step * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

# ═════════════════════════════════════════════════════════════════════════════
# Helper: run forward simulation for a given injection rate schedule
# ═════════════════════════════════════════════════════════════════════════════
function run_forward(K, inj_rates;
                     n=N_GRID, d=D_CELL, h=H_TOP, ϕ=PHI,
                     ds=DS, dt_per_step=DT_PER_STEP)
    n_periods = length(inj_rates)
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_per_step=dt_per_step)

    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250*d[1], 1*d[2], inj_y*d[3])

    # Initial CO2 saturation (small plume around injection well)
    S0 = zeros(Float64, n[1], n[end])
    Random.seed!(2025)
    value = 0.5
    S0[249:251, inj_y-4] .= value
    S0[248:252, inj_y-3] .= value
    S0[247:253, inj_y-2] .= value
    S0[246:254, inj_y-1] .= value
    S0[246:254, inj_y]   .= value
    S0[246:254, inj_y+1] .= value
    S0[247:253, inj_y+2] .= value
    S0[248:252, inj_y+3] .= value
    S0[249:251, inj_y+4] .= value

    n_total = n_periods * ds
    sat_arr  = [zeros(n[1], n[end]) for _ in 1:n_total]
    pres_arr = [zeros(n[1], n[end]) for _ in 1:n_total]

    previous_state = nothing
    for i in 1:n_periods
        f = jutulVWell(inj_rates[i], [(inj_loc[1], inj_loc[2])];
                       startz=[inj_loc[3]], endz=[inj_loc[3] + 6*d[3]])
        if i == 1
            state0 = jutulSimpleState(sim.model)
            state0[1:n[1]*n[3]] = vec(S0)
            states = sim.Sblk(sim.logTrans, f; state0=state0)
        else
            states = sim.Sblk(sim.logTrans, f; state0=previous_state)
        end
        previous_state = states.states[end]

        for j in 1:ds
            idx = (i-1)*ds + j
            sat_arr[idx]  = reshape(states.states[j][1:n[1]*n[3]],       n[1], n[end])
            pres_arr[idx] = reshape(states.states[j][n[1]*n[3]+1:end],   n[1], n[end])
        end
    end
    return sat_arr, pres_arr
end

# ═════════════════════════════════════════════════════════════════════════════
# Helper: load optimized injection rate from final.jld2
# ═════════════════════════════════════════════════════════════════════════════
function load_optimized_rate(case_dir::String, sample::Int)
    base = datadir("DT_control", "exp_name=step1", case_dir, "sample=$sample", "final.jld2")
    if !isfile(base)
        error("File not found: $base")
    end
    data = JLD2.load(base)
    inj_rate_arr = data["inj_rate_arr"]   # (niterations+1, 1)

    # Find last valid (non-zero) iteration
    last_iter = findlast(i -> any(inj_rate_arr[i, :] .!= 0), 1:size(inj_rate_arr, 1))
    final_rate = inj_rate_arr[last_iter, 1]
    println("  Loaded rate for sample $sample: $(final_rate) m³/s  (iteration $(last_iter-1))")
    return final_rate
end

# ═════════════════════════════════════════════════════════════════════════════
# Main
# ═════════════════════════════════════════════════════════════════════════════
function main()
    println("="^70)
    println("Fracture vs Non-Fracture Comparison on Ground Truth Permeability")
    println("  INJ_RATE_MULTIPLIER = $(INJ_RATE_MULTIPLIER)")
    println("="^70)

    # ── Load permeability ─────────────────────────────────────────────────
    perm_data = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"))
    BroadK = perm_data["BroadK"]
    K_gt = BroadK[GROUND_TRUTH_IDX, :, :] * JutulDarcyRules.md
    println("Ground truth permeability: sample $GROUND_TRUTH_IDX, shape $(size(K_gt))")

    # ── Reference pressures ───────────────────────────────────────────────
    p0    = (repeat(collect(1:N_GRID[3]), 1, N_GRID[1]) * D_CELL[3] .+ H_TOP) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 10^6   # fracture pressure [Pa]

    # ── Load optimized injection rates ────────────────────────────────────
    println("\nLoading POF case: $POF_CASE_DIR")
    rate_pof = load_optimized_rate(POF_CASE_DIR, SAMPLE_IDX)

    println("Loading CVaR case: $CVAR_CASE_DIR")
    rate_cvar = load_optimized_rate(CVAR_CASE_DIR, SAMPLE_IDX)

    # Build ramped injection schedules (same as optim_inject.jl)
    n_periods = FORWARD_STEP * 6   # 12
    inj_pof  = collect(range(INJ_START, rate_pof,  n_periods)) .* INJ_RATE_MULTIPLIER
    inj_cvar = collect(range(INJ_START, rate_cvar, n_periods)) .* INJ_RATE_MULTIPLIER

    println("\nPOF  injection rates (×$(INJ_RATE_MULTIPLIER)): ", round.(inj_pof;  digits=6))
    println("CVaR injection rates (×$(INJ_RATE_MULTIPLIER)): ", round.(inj_cvar; digits=6))

    # ── Run forward simulations ───────────────────────────────────────────
    println("\nRunning POF forward simulation...")
    sat_pof, pres_pof = run_forward(K_gt, inj_pof)
    println("  $(length(sat_pof)) time steps computed")

    println("Running CVaR forward simulation...")
    sat_cvar, pres_cvar = run_forward(K_gt, inj_cvar)
    println("  $(length(sat_cvar)) time steps computed")

    # ── Compute relative pressure margin at final time step ───────────────
    # r = (p_frac − p) / p_frac  ;  r>0 safe, r<0 fractured
    r_pof  = (p_max .- pres_pof[end])  ./ p_max
    r_cvar = (p_max .- pres_cvar[end]) ./ p_max

    min_r_pof  = minimum(r_pof)
    min_r_cvar = minimum(r_cvar)
    frac_pof   = count(r_pof  .< 0)
    frac_cvar  = count(r_cvar .< 0)

    total_cells = length(r_pof)
    println("\nPOF  case: min(r) = $(@sprintf("%.4f", min_r_pof)),  fractured cells = $frac_pof / $total_cells")
    println("CVaR case: min(r) = $(@sprintf("%.4f", min_r_cvar)),  fractured cells = $frac_cvar / $total_cells")

    # ── Create figure ─────────────────────────────────────────────────────
    out_dir = plotsdir("paper_figures")
    mkpath(out_dir)

    rc("font", family="serif", size=13)
    rc("xtick", labelsize=12)
    rc("ytick", labelsize=12)
    rc("axes", labelsize=14, titlesize=15)

    np = pyimport("numpy")
    extent = (0, (N_GRID[1]-1)*D_CELL[1], H_TOP+(N_GRID[3]-1)*D_CELL[3], H_TOP)

    # ──── Build custom red-blue diverging colormap ────────────────────────
    # Red (r<0, fractured) → white (r=0) → blue (r>0, safe)
    vmin_r, vmax_r = -0.1, 1.0
    n_neg = 26     # ~10% of colorbar for r ∈ [−0.1, 0)
    n_pos = 230    # ~90% of colorbar for r ∈ [0, 1.0]
    red_colors  = PyPlot.cm.Reds_r(np.linspace(0.0, 0.85, n_neg))
    blue_colors = PyPlot.cm.Blues(np.linspace(0.0, 1.0, n_pos))
    colors_arr  = vcat(red_colors, blue_colors)
    cmap_margin = PyPlot.cm.colors.ListedColormap(colors_arr)

    # ──── 2×2 figure: top=safety margin, bottom=saturation ────────────────
    fig, axes = subplots(2, 2, figsize=(14, 9), sharex=true, sharey=true)
    im_ratio = N_GRID[3]*D_CELL[3] / (N_GRID[1]*D_CELL[1])

    total_days = Int(n_periods * DS * DT_PER_STEP)

    # (a) POF: Relative Pressure Margin
    ax = axes[1, 1]
    im1 = ax.imshow(transpose(r_pof), extent=extent, cmap=cmap_margin,
                    vmin=vmin_r, vmax=vmax_r, aspect="auto")
    ax.set_title("(a) $(POF_LABEL)  —  Pressure Margin")
    ax.set_ylabel("Depth [m]")
    ax.text(0.02, 0.05, "min(r) = $(@sprintf("%.3f", min_r_pof))\nfrac cells = $frac_pof",
            transform=ax.transAxes, fontsize=10, va="bottom",
            bbox=Dict("boxstyle"=>"round", "facecolor"=>"white", "alpha"=>0.8))

    # (b) CVaR: Relative Pressure Margin
    ax = axes[1, 2]
    im2 = ax.imshow(transpose(r_cvar), extent=extent, cmap=cmap_margin,
                    vmin=vmin_r, vmax=vmax_r, aspect="auto")
    ax.set_title("(b) $(CVAR_LABEL)  —  Pressure Margin")
    ax.text(0.02, 0.05, "min(r) = $(@sprintf("%.3f", min_r_cvar))\nfrac cells = $frac_cvar",
            transform=ax.transAxes, fontsize=10, va="bottom",
            bbox=Dict("boxstyle"=>"round", "facecolor"=>"white", "alpha"=>0.8))

    # (c) POF: Saturation
    ax = axes[2, 1]
    im3 = ax.imshow(transpose(sat_pof[end]), vmin=0, vmax=1, extent=extent,
                    cmap=cmasher.rainforest_r, aspect="auto")
    ax.set_title("(c) $(POF_LABEL)  —  CO₂ Saturation")
    ax.set_xlabel("X [m]")
    ax.set_ylabel("Depth [m]")

    # (d) CVaR: Saturation
    ax = axes[2, 2]
    im4 = ax.imshow(transpose(sat_cvar[end]), vmin=0, vmax=1, extent=extent,
                    cmap=cmasher.rainforest_r, aspect="auto")
    ax.set_title("(d) $(CVAR_LABEL)  —  CO₂ Saturation")
    ax.set_xlabel("X [m]")

    # Colorbars
    fig.subplots_adjust(right=0.88, hspace=0.25, wspace=0.08)

    # Safety margin colorbar (spans top row)
    cax1 = fig.add_axes([0.90, 0.53, 0.015, 0.35])
    clb1 = fig.colorbar(im1, cax=cax1)
    clb1.set_label("r = (p_frac − p) / p_frac", fontsize=12)
    clb1.set_ticks([-0.1, 0.0, 0.25, 0.5, 0.75, 1.0])
    clb1.set_ticklabels(["≤−0.1\n(fracture)", "0", "0.25", "0.5", "0.75", "1.0\n(safe)"])

    # Saturation colorbar (spans bottom row)
    cax2 = fig.add_axes([0.90, 0.10, 0.015, 0.35])
    clb2 = fig.colorbar(im3, cax=cax2)
    clb2.set_label("CO₂ Saturation", fontsize=12)

    fig.suptitle("Forward Simulation on Ground Truth (t = $total_days days, rate ×$(INJ_RATE_MULTIPLIER))",
                 fontsize=16, y=0.98)

    # Save
    ts = Dates.format(now(), "yyyymmdd_HHMMSS")
    for ext in ["png", "pdf"]
        fname = joinpath(out_dir, "fracture_comparison_$(ts).$(ext)")
        savefig(fname, dpi=300, bbox_inches="tight")
        println("Saved: $fname")
    end
    close(fig)

    # ──── Supplementary: min(r) time series ───────────────────────────────
    println("\nGenerating min(r) time series...")
    n_total = length(pres_pof)
    times = collect(1:n_total) .* DT_PER_STEP

    minr_pof_ts  = [minimum((p_max .- pres_pof[t])  ./ p_max) for t in 1:n_total]
    minr_cvar_ts = [minimum((p_max .- pres_cvar[t]) ./ p_max) for t in 1:n_total]

    fig2, ax2 = subplots(figsize=(8, 4.5))
    ax2.plot(times, minr_pof_ts,  "b-o", markersize=3, linewidth=1.5, label=POF_LABEL)
    ax2.plot(times, minr_cvar_ts, "r-s", markersize=3, linewidth=1.5, label=CVAR_LABEL)
    ax2.axhline(0.0; color="k", linestyle="--", linewidth=1, alpha=0.7, label="Fracture threshold (r=0)")
    ax2.fill_between(times, minimum(vcat(minr_pof_ts, minr_cvar_ts)) - 0.02, 0.0;
                     color="red", alpha=0.1, label="Fracture zone (r < 0)")
    ax2.set_xlabel("Time [days]")
    ax2.set_ylabel("min(r)  — Relative Pressure Margin")
    ax2.set_title("Minimum Safety Margin Over Time  (rate ×$(INJ_RATE_MULTIPLIER))")
    ax2.legend(loc="best", fontsize=10)
    ax2.grid(true, alpha=0.3)
    plt.tight_layout()

    for ext in ["png", "pdf"]
        fname = joinpath(out_dir, "fracture_minr_timeseries_$(ts).$(ext)")
        savefig(fname, dpi=300, bbox_inches="tight")
        println("Saved: $fname")
    end
    close(fig2)

    println("\nDone!")
end

main()
