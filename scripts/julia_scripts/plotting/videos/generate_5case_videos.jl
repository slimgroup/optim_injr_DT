#!/usr/bin/env julia
# Generate videos for 5 injection control cases on ground truth permeability
# Cases:
# 1. PoF eps = 0.0
# 2. CVaR gamma = 0.0, alpha = 0.0
# 3. PoF eps = 0.01
# 4. CVaR gamma = 0.1, alpha = 0.01
# 5. No control (constant 0.05 m³/s)
#
# Ground truth permeability: sample 2000 from wise_perm_models_2000_new.jld2
# Simulation: 8 days per time step, 480 days total = 60 time steps
# Video layout: normalized safety margin (top), saturation (bottom)
#
# NOTE: All injection rates are multiplied by 3 for better visualization effect

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

# ─────────────────────────────────────────────────────────────────────────────
# PyCall setup (using shared utility)
include(srcdir("utils.jl"))
setup_pycall()

# ─────────────────────────────────────────────────────────────────────────────
# Constants
const N = (512, 1, 256)  # Grid dimensions
const D = (6.25, 100.0, 6.25)  # Cell size (m)
const H = 0.0  # Top depth
const PHI = 0.25  # Porosity
const DS = 10  # Sub-timesteps per injection period
const DT_PER_STEP = 8.0  # days per sub-timestep
const TOTAL_DAYS = 480  # Total simulation time
const N_TIMESTEPS = Int(TOTAL_DAYS / DT_PER_STEP)  # = 60 time steps
const THRESHOLD = 4.0  # MPa pressure threshold

# Injection rate multiplier for better visualization
const INJ_RATE_MULTIPLIER = 3.0

# ─────────────────────────────────────────────────────────────────────────────
# Injection rate arrays for 5 cases (from markdown file) - MULTIPLIED BY 3
const CASES = Dict(
    "POF_eps=0.0" => (
        name = "PoF ε = 0.0",
        inj_rates = [0.000100, 0.003468, 0.006836, 0.010204, 0.013572, 0.016940] .* INJ_RATE_MULTIPLIER
    ),
    "CVaR_gamma=0.0_alpha=0.0" => (
        name = "CVaR γ = 0.0, α = 0.0",
        inj_rates = [0.000100, 0.002738, 0.005376, 0.008014, 0.010652, 0.013290] .* INJ_RATE_MULTIPLIER
    ),
    "POF_eps=0.01" => (
        name = "PoF ε = 0.01",
        inj_rates = [0.000100, 0.004662, 0.009224, 0.013786, 0.018348, 0.022910] .* INJ_RATE_MULTIPLIER
    ),
    "CVaR_gamma=0.1_alpha=0.01" => (
        name = "CVaR γ = 0.1, α = 0.01",
        inj_rates = [0.000100, 0.007584, 0.015068, 0.022552, 0.030036, 0.037520] .* INJ_RATE_MULTIPLIER
    ),
    "No_Control" => (
        name = "No Control",
        inj_rates = collect(range(0.0, 0.1, length=6)) .* INJ_RATE_MULTIPLIER  # [0, 0.02, 0.04, 0.06, 0.08, 0.1] × 3
    )
)

const CASE_ORDER = ["POF_eps=0.0", "CVaR_gamma=0.0_alpha=0.0", "POF_eps=0.01", "CVaR_gamma=0.1_alpha=0.01", "No_Control"]

# ─────────────────────────────────────────────────────────────────────────────
# Simulation builder
function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_per_step=8.0)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    Sblk = jutulModeling(model, dt_per_step * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

# ─────────────────────────────────────────────────────────────────────────────
# Run simulation for a given injection rate schedule
function run_simulation(K, inj_rates; ds=DS, dt_per_step=DT_PER_STEP, n=N, d=D, h=H, ϕ=PHI)
    @assert length(inj_rates) == 6 "Expected 6 injection rate values"
    
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_per_step=dt_per_step)
    
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * d[1], 1 * d[2], inj_y * d[3])
    
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
    
    n_total = 6 * ds
    sat_arr = [zeros(n[1], n[end]) for _ in 1:n_total]
    pres_arr = [zeros(n[1], n[end]) for _ in 1:n_total]
    
    previous_state = nothing
    for i in 1:6
        f = jutulVWell(inj_rates[i], [(inj_loc[1], inj_loc[2])];
                       startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])
        
        try
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
                sat_arr[idx] = reshape(states.states[j][1:n[1]*n[3]], n[1], n[end])
                pres_arr[idx] = reshape(states.states[j][n[1]*n[3]+1:end], n[1], n[end])
            end
        catch e
            @error "Simulation failed at injection period $i" exception=(e, catch_backtrace())
            rethrow(e)
        end
    end
    
    return sat_arr, pres_arr, inj_y
end

# ─────────────────────────────────────────────────────────────────────────────
# Create frame for video (2-row layout)
function create_frame(sat, pres, p_max, p0, frame_idx, case_name, output_path;
                      n=N, d=D, h=H, threshold=THRESHOLD, dt_per_step=DT_PER_STEP)
    
    # Normalized safety margin: r = (p_fracture - p_reservoir) / p_fracture = (p_max - p) / p_max
    # r > 0 means safe, r < 0 means fractured
    safety_margin = (p_max .- pres) ./ p_max
    
    rc("font", family="serif")
    rc("xtick", labelsize=15)
    rc("ytick", labelsize=15)
    
    fig, axes = subplots(2, 1, figsize=(10, 8))
    im_ratio = n[3] * d[3] / (n[1] * d[1])
    extent = (0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h)
    
    time_days = frame_idx * dt_per_step
    
    # ─── Top plot: Normalized Safety Margin ───
    ax1 = axes[1]
    np = pyimport("numpy")
    
    # Create custom colormap: red gradient (negative/fractured) -> white (0) -> blue gradient (positive/safe)
    # Use linear scale so colorbar proportions match data range
    # Range: -0.1 to 1.0, with red taking only ~9% of colorbar (proportional to range)
    vmin_margin = -0.1
    vmax_margin = 1.0
    total_range = vmax_margin - vmin_margin  # 1.1
    
    # Proportional colors: negative part is 0.1/1.1 ≈ 9%, positive is 1.0/1.1 ≈ 91%
    n_negative = 23   # ~9% of 256 colors for r < 0
    n_positive = 233  # ~91% of 256 colors for r >= 0
    
    # Red gradient: dark red (most negative) -> light red/white at 0
    red_colors = PyPlot.cm.Reds_r(np.linspace(0.0, 0.85, n_negative))
    # Blue gradient: white at 0 -> light blue -> dark blue
    blue_colors = PyPlot.cm.Blues(np.linspace(0.0, 1.0, n_positive))
    
    colors = vcat(red_colors, blue_colors)
    cmap_margin = PyPlot.cm.colors.ListedColormap(colors)
    
    # Simple linear normalization (colorbar proportions match data range)
    im1 = ax1.imshow(transpose(safety_margin), extent=extent, cmap=cmap_margin, 
                     vmin=vmin_margin, vmax=vmax_margin)
    
    # Colorbar - extend="min" for values below -0.1
    clb1 = fig.colorbar(im1, ax=ax1, fraction=0.046*im_ratio, pad=0.04, extend="min")
    clb1.ax.set_title("r", fontsize=14)
    clb1.set_ticks([vmin_margin, 0.0, 0.5, 1.0])
    clb1.set_ticklabels(["<0 (frac)", "0", "0.5", "1.0"])
    
    ax1.set_ylabel("Depth[m]", fontsize=15)
    ax1.set_title("Normalized Safety Margin  r = (p_frac - p) / p_frac", fontsize=14)
    ax1.set_xticklabels([])
    
    # ─── Bottom plot: CO2 Saturation (0 = white) ───
    ax2 = axes[2]
    im2 = ax2.imshow(transpose(sat), vmin=0, vmax=1, extent=extent, cmap=cmasher.rainforest_r)
    clb2 = fig.colorbar(im2, ax=ax2, fraction=0.046*im_ratio, pad=0.04)
    clb2.set_ticks([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax2.set_xlabel("X[m]", fontsize=15)
    ax2.set_ylabel("Depth[m]", fontsize=15)
    ax2.set_title("Saturation", fontsize=14)
    
    # Super title (centered over entire figure, shifted right to account for colorbar)
    fig.suptitle("$case_name    t = $(Int(time_days)) days", fontsize=18, fontweight="bold", 
                 x=0.58, y=0.995, ha="center")
    
    plt.tight_layout(rect=[0, 0, 1, 0.98], h_pad=1.5)
    
    frame_file = joinpath(output_path, @sprintf("frame_%04d.png", frame_idx))
    savefig(frame_file, dpi=150, bbox_inches="tight", pad_inches=0.1)
    close(fig)
    
    return frame_file
end

# ─────────────────────────────────────────────────────────────────────────────
# Skip video creation in Julia - use Python script
function create_video(frames_dir, output_video, fps=10)
    println("Frames saved in: $frames_dir")
    println("Run 'python scripts/python_plots/create_videos_from_frames.py' to create videos")
end

# ─────────────────────────────────────────────────────────────────────────────
# Main function
function main()
    println("="^60)
    println("Generating 5-case simulation videos")
    println("Injection rates multiplied by $(INJ_RATE_MULTIPLIER)x for visualization")
    println("="^60)
    
    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    println("Loading permeability from: $perm_path")
    perm_data = JLD2.load(perm_path)
    BroadK = perm_data["BroadK"]
    
    ground_truth_idx = 2000
    K = BroadK[ground_truth_idx, :, :] * JutulDarcyRules.md
    println("Using ground truth permeability: sample $ground_truth_idx")
    println("K shape: $(size(K))")
    
    p0 = (repeat(collect(1:N[3]), 1, N[1]) * D[3] .+ H) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 10^6
    
    ts = Dates.format(now(), "yyyymmdd_HHMMSS")
    output_root = plotsdir("DT_control", "videos", "5cases", "videos_5cases_$(ts)")
    mkpath(output_root)
    println("Output directory: $output_root")
    
    for case_key in CASE_ORDER
        case_info = CASES[case_key]
        case_name = case_info.name
        inj_rates = case_info.inj_rates
        
        println("\n" * "="^60)
        println("Processing: $case_name")
        println("Injection rates (×$(INJ_RATE_MULTIPLIER)): $inj_rates")
        println("="^60)
        
        println("Running simulation...")
        sat_arr, pres_arr, inj_y = run_simulation(K, inj_rates)
        println("Simulation complete. Generated $(length(sat_arr)) time steps")
        
        case_slug = replace(case_key, "=" => "", "." => "")
        frames_dir = joinpath(output_root, "frames_$(case_slug)")
        mkpath(frames_dir)
        
        println("Generating frames...")
        for t in 1:length(sat_arr)
            create_frame(sat_arr[t], pres_arr[t], p_max, p0, t, case_name, frames_dir)
            if t % 10 == 0
                println("  Frame $t / $(length(sat_arr))")
            end
        end
        
        video_file = joinpath(output_root, "$(case_slug).mp4")
        create_video(frames_dir, video_file)
    end
    
    println("\n" * "="^60)
    println("All frames generated successfully!")
    println("Output directory: $output_root")
    println("="^60)
end

main()
