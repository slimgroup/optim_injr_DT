#!/usr/bin/env julia
# Generate videos for 3 control cases using the older statistical-analysis schedules.
# Cases:
# 1. POF eps = 0.01
# 2. CVaR gamma = 0.1, alpha = 0.01
# 3. No Control (legacy unconstrained baseline schedule)
#
# Video layout:
#   Row 1: normalized safety margin
#   Row 2: differential pressure (MPa)
#   Row 3: CO2 saturation

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using LinearAlgebra
using PyPlot
using JLD2
using Random
using PyCall
using Printf
using Dates

const N = (512, 1, 256)
const D = (6.25, 100.0, 6.25)
const H = 0.0
const PHI = 0.25
const DS = 10
const DT_PER_STEP = 8.0
const TOTAL_DAYS = 480
const THRESHOLD = 4.0

# Old statistical-analysis arrays from docs/injection_rate_arrays.md.
# No-control is kept as the legacy unconstrained reference schedule.
const CASES = Dict(
    "POF_eps=0.01" => (
        name = "POF ε = 0.01",
        inj_rates = [0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530],
    ),
    "CVaR_gamma=0.1_alpha=0.01" => (
        name = "CVaR γ = 0.1, α = 0.01",
        inj_rates = [0.00010, 0.01502, 0.02994, 0.04486, 0.05978, 0.07470],
    ),
    "No_Control" => (
        name = "No Control",
        inj_rates = collect(range(0.0, 0.1, length=6)),
    ),
)

const CASE_ORDER = ["POF_eps=0.01", "CVaR_gamma=0.1_alpha=0.01", "No_Control"]

function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_per_step=8.0)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    sblk = jutulModeling(model, dt_per_step * ones(ds))
    trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(trans), Sblk=sblk)
end

function run_simulation(K, inj_rates; ds=DS, dt_per_step=DT_PER_STEP, n=N, d=D, h=H, ϕ=PHI)
    @assert length(inj_rates) == 6 "Expected 6 injection rate values"

    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_per_step=dt_per_step)

    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc = (250 * d[1], 1 * d[2], inj_y * d[3])

    s0 = zeros(Float64, n[1], n[end])
    Random.seed!(2025)
    value = 0.5
    s0[249:251, inj_y-4] .= value
    s0[248:252, inj_y-3] .= value
    s0[247:253, inj_y-2] .= value
    s0[246:254, inj_y-1] .= value
    s0[246:254, inj_y]   .= value
    s0[246:254, inj_y+1] .= value
    s0[247:253, inj_y+2] .= value
    s0[248:252, inj_y+3] .= value
    s0[249:251, inj_y+4] .= value

    n_total = 6 * ds
    sat_arr = [zeros(n[1], n[end]) for _ in 1:n_total]
    pres_arr = [zeros(n[1], n[end]) for _ in 1:n_total]

    previous_state = nothing
    for i in 1:6
        f = jutulVWell(inj_rates[i], [(inj_loc[1], inj_loc[2])];
                       startz=[inj_loc[3]], endz=[inj_loc[3] + 6 * d[3]])

        if i == 1
            state0 = jutulSimpleState(sim.model)
            state0[1:n[1]*n[3]] = vec(s0)
            states = sim.Sblk(sim.logTrans, f; state0=state0)
        else
            states = sim.Sblk(sim.logTrans, f; state0=previous_state)
        end

        previous_state = states.states[end]
        for j in 1:ds
            idx = (i - 1) * ds + j
            sat_arr[idx] = reshape(states.states[j][1:n[1]*n[3]], n[1], n[end])
            pres_arr[idx] = reshape(states.states[j][n[1]*n[3] + 1:end], n[1], n[end])
        end
    end

    return sat_arr, pres_arr
end

function make_custom_cmap(name, stops)
    mpl_colors = pyimport("matplotlib.colors")
    py_stops = PyObject[]
    for (pos, color) in stops
        push!(py_stops, PyObject((pos, color)))
    end
    return mpl_colors.LinearSegmentedColormap.from_list(name, py_stops)
end

function create_frame(sat, pres, p_max, p0, frame_idx, case_name, output_path;
                      n=N, d=D, h=H, threshold=THRESHOLD, dt_per_step=DT_PER_STEP)
    safety_margin = (p_max .- pres) ./ p_max
    dp = (pres .- p0) ./ 1e6

    rc("font", family="serif", size=13)
    rc("xtick", labelsize=12)
    rc("ytick", labelsize=12)
    rc("axes", labelsize=14, titlesize=15)

    fig, axes = subplots(3, 1, figsize=(10.5, 11.5))
    im_ratio = n[3] * d[3] / (n[1] * d[1])
    extent = (0, (n[1] - 1) * d[1], h + (n[3] - 1) * d[3], h)
    time_days = frame_idx * dt_per_step

    np = pyimport("numpy")

    red_colors = PyPlot.cm.Reds_r(np.linspace(0.0, 0.85, 23))
    blue_colors = PyPlot.cm.Blues(np.linspace(0.0, 1.0, 233))
    cmap_margin = PyPlot.cm.colors.ListedColormap(vcat(red_colors, blue_colors))

    cmap_pressure = make_custom_cmap("pressure_video", [
        (0.00, "#ffffff"),
        (0.12, "#f9f9f3"),
        (0.22, "#ecec98"),
        (0.40, "#ffd42a"),
        (0.62, "#f28e74"),
        (0.82, "#b22222"),
        (1.00, "#050505"),
    ])

    cmap_sat = make_custom_cmap("saturation_video", [
        (0.00, "#ffffff"),
        (0.10, "#f4f4f4"),
        (0.22, "#d8cf92"),
        (0.34, "#9fbe4a"),
        (0.50, "#49a65f"),
        (0.66, "#2b8cbe"),
        (0.82, "#5e3c99"),
        (1.00, "#050505"),
    ])

    vmax_dp = min(maximum(dp) * 1.05, threshold * 1.6)

    ax1 = axes[1]
    im1 = ax1.imshow(transpose(safety_margin), extent=extent, cmap=cmap_margin,
                     vmin=-0.1, vmax=1.0, aspect="auto")
    clb1 = fig.colorbar(im1, ax=ax1, fraction=0.046 * im_ratio, pad=0.04, extend="min")
    clb1.ax.set_title("r", fontsize=13)
    clb1.set_ticks([0.0, 0.5, 1.0])
    clb1.set_ticklabels(["0", "0.5", "1.0"])
    clb1.ax.text(0.5, -0.06, "<0 (frac)", transform=clb1.ax.transAxes,
                 fontsize=10, ha="center", va="top")
    ax1.set_ylabel("Depth [m]", fontsize=14)
    ax1.set_title("Normalized Safety Margin  r = (p_frac - p) / p_frac", fontsize=14)
    ax1.set_xticklabels([])

    ax2 = axes[2]
    im2 = ax2.imshow(transpose(dp), extent=extent, cmap=cmap_pressure,
                     vmin=0, vmax=vmax_dp, aspect="auto")
    clb2 = fig.colorbar(im2, ax=ax2, fraction=0.046 * im_ratio, pad=0.04)
    clb2.set_label("MPa", fontsize=13)
    ax2.set_ylabel("Depth [m]", fontsize=14)
    ax2.set_title("Differential Pressure  (p - p₀)", fontsize=14)
    ax2.set_xticklabels([])

    ax3 = axes[3]
    im3 = ax3.imshow(transpose(sat), extent=extent, cmap=cmap_sat,
                     vmin=0, vmax=1, aspect="auto")
    clb3 = fig.colorbar(im3, ax=ax3, fraction=0.046 * im_ratio, pad=0.04)
    clb3.set_ticks([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax3.set_xlabel("X [m]", fontsize=14)
    ax3.set_ylabel("Depth [m]", fontsize=14)
    ax3.set_title("Saturation", fontsize=14)

    fig.suptitle("$case_name    t = $(Int(time_days)) days",
                 fontsize=18, fontweight="bold", x=0.58, y=0.995, ha="center")
    plt.tight_layout(rect=[0, 0, 1, 0.98], h_pad=1.2)

    frame_file = joinpath(output_path, @sprintf("frame_%04d.png", frame_idx))
    savefig(frame_file, dpi=150, bbox_inches="tight", pad_inches=0.08)
    close(fig)

    return frame_file
end

function create_video(frames_dir, output_video)
    println("Frames saved in: $frames_dir")
    println("Create video separately for: $output_video")
end

function main()
    println("="^64)
    println("Generating 3-case videos from old statistical-analysis schedules")
    println("="^64)

    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    perm_data = JLD2.load(perm_path)
    broadk = perm_data["BroadK"]

    ground_truth_idx = 2000
    k = broadk[ground_truth_idx, :, :] * JutulDarcyRules.md
    p0 = (repeat(collect(1:N[3]), 1, N[1]) * D[3] .+ H) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ THRESHOLD * 10^6

    ts = Dates.format(now(), "yyyymmdd_HHMMSS")
    output_root = plotsdir("DT_control", "videos_stat3cases_oldstats_$(ts)")
    mkpath(output_root)
    println("Output directory: $output_root")

    for case_key in CASE_ORDER
        case_info = CASES[case_key]
        println("\n" * "="^64)
        println("Processing: $(case_info.name)")
        println("Injection rates: $(round.(case_info.inj_rates; digits=5))")
        println("="^64)

        sat_arr, pres_arr = run_simulation(k, case_info.inj_rates)
        case_slug = replace(case_key, "=" => "", "." => "")
        frames_dir = joinpath(output_root, "frames_$(case_slug)")
        mkpath(frames_dir)

        for t in 1:length(sat_arr)
            create_frame(sat_arr[t], pres_arr[t], p_max, p0, t, case_info.name, frames_dir)
            if t % 10 == 0
                println("  Frame $t / $(length(sat_arr))")
            end
        end

        create_video(frames_dir, joinpath(output_root, "$(case_slug).mp4"))
    end

    println("\n" * "="^64)
    println("All 3-case frames generated successfully")
    println("Output directory: $output_root")
    println("="^64)
end

main()
