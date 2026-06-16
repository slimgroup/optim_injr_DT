#!/usr/bin/env julia
# Generate two-panel plots for bootstrap CDF analysis:
#   Panel (a): Injection rate distribution histogram with bootstrap inset
#   Panel (b): Empirical CDF with 95% Bootstrap CI and zoom-in inset
#
# Generates plots for:
#   - PoF eps=0.01
#   - CVaR g=0.05 a=0.05

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using Statistics
using Random
using StatsBase

# ===================== Config =====================
const ROOT = datadir("DT_control", "exp_name=step1")
const OUTDIR = joinpath(projectdir(), "plots", "DT_control", "exp_name=step1", "statistical_analysis", "ecdf")
const NUM_BOOTSTRAP = 10000
const CONF_LEVEL = 0.95
const FRACTURE_PROB_THRESHOLD = 0.01  # 1%
const NBINS = 30
const SEED = 42

# Font sizes
const FS_SUPTITLE = 16
const FS_TITLE = 14
const FS_LABEL = 12
const FS_TICK = 10
const FS_ANNOT = 10
const FS_LEGEND = 9
const FS_INSET_TITLE = 9
const FS_INSET_TICK = 7
const FS_STATS = 8
# ==================================================

# ========== Data loading ==========
function last_nonzero_inj_rate(data; init_rate::Float64=1e-4)
    raw = get(data, "inj_rate_arr", nothing)
    raw === nothing && return init_rate
    col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? init_rate : clean[idx]
end

function collect_data_from_dir(root::AbstractString, dir_pattern::String)
    risk_dirs = filter(d -> isdir(joinpath(root, d)) && occursin(dir_pattern, d), readdir(root))
    
    rates = Float64[]
    for risk_name in risk_dirs
        risk_dir = joinpath(root, risk_name)
        for s in 1:128
            final_path = joinpath(risk_dir, "sample=$(s)", "final.jld2")
            if isfile(final_path)
                try
                    data = load(final_path)
                    rate = last_nonzero_inj_rate(data; init_rate=1e-4)
                    push!(rates, rate)
                catch err
                    @warn "Failed to load sample $s from $risk_name: $err"
                end
            end
        end
    end
    return rates
end

# ========== Bootstrap functions ==========
function bootstrap_quantile(data::Vector{Float64}, q::Float64, B::Int; seed::Int=SEED)
    rng = MersenneTwister(seed)
    n = length(data)
    boot_quantiles = zeros(B)
    for b in 1:B
        boot_sample = data[rand(rng, 1:n, n)]
        boot_quantiles[b] = quantile(boot_sample, q)
    end
    return boot_quantiles
end

function bootstrap_ecdf_ci(data::Vector{Float64}, B::Int; conf_level::Float64=CONF_LEVEL, seed::Int=SEED)
    rng = MersenneTwister(seed)
    n = length(data)
    sorted_data = sort(data)
    
    # Evaluate ECDF on a fine grid
    x_min = minimum(data)
    x_max = maximum(data)
    margin = 0.05 * (x_max - x_min)
    x_grid = collect(range(x_min - margin, x_max + margin, length=2000))
    
    # Compute empirical CDF for original data
    ecdf_orig = zeros(length(x_grid))
    for (i, x) in enumerate(x_grid)
        ecdf_orig[i] = count(d -> d <= x, data) / n
    end
    
    # Bootstrap: compute ECDF for each bootstrap sample
    boot_ecdfs = zeros(B, length(x_grid))
    for b in 1:B
        boot_sample = data[rand(rng, 1:n, n)]
        for (i, x) in enumerate(x_grid)
            boot_ecdfs[b, i] = count(d -> d <= x, boot_sample) / n
        end
    end
    
    # Compute pointwise CI
    alpha = 1 - conf_level
    ci_lower = zeros(length(x_grid))
    ci_upper = zeros(length(x_grid))
    for i in eachindex(x_grid)
        ci_lower[i] = quantile(view(boot_ecdfs, :, i), alpha / 2)
        ci_upper[i] = quantile(view(boot_ecdfs, :, i), 1 - alpha / 2)
    end
    
    return x_grid, ecdf_orig, ci_lower, ci_upper
end

# ========== Find threshold crossings ==========
function find_threshold_crossing(x_grid, cdf_vals, threshold)
    idx = findfirst(v -> v >= threshold, cdf_vals)
    return idx !== nothing ? x_grid[idx] : nothing
end

# ========== Two-panel plot ==========
function plot_two_panel(data::Vector{Float64}, case_tag::String, case_title::String, filename::String;
                        B::Int=NUM_BOOTSTRAP, conf_level::Float64=CONF_LEVEL,
                        threshold::Float64=FRACTURE_PROB_THRESHOLD, nbins::Int=NBINS)
    
    n = length(data)
    q_level = threshold  # 1% quantile
    
    println("Computing bootstrap for $case_tag (n=$n, B=$B)...")
    
    # Bootstrap the 1% quantile
    boot_quantiles = bootstrap_quantile(data, q_level, B)
    q_val = quantile(data, q_level)
    ci_lo_q = quantile(boot_quantiles, (1 - conf_level) / 2)
    ci_hi_q = quantile(boot_quantiles, 1 - (1 - conf_level) / 2)
    
    println("  1% quantile: $(round(q_val, digits=5))")
    println("  95% CI: [$(round(ci_lo_q, digits=5)), $(round(ci_hi_q, digits=5))]")
    
    # Bootstrap the empirical CDF
    x_grid, ecdf_vals, ci_lower, ci_upper = bootstrap_ecdf_ci(data, B; conf_level=conf_level)
    
    # Find threshold crossings (in probability space: where CDF crosses threshold)
    x_ecdf = find_threshold_crossing(x_grid, ecdf_vals, threshold)
    x_conservative = find_threshold_crossing(x_grid, ci_upper, threshold)  # upper CI crosses first = conservative
    x_optimistic = find_threshold_crossing(x_grid, ci_lower, threshold)    # lower CI crosses last = optimistic
    
    println("  ECDF crossing at 1%: $(x_ecdf !== nothing ? round(x_ecdf, digits=5) : "N/A")")
    println("  Conservative: $(x_conservative !== nothing ? round(x_conservative, digits=5) : "N/A")")
    println("  Optimistic: $(x_optimistic !== nothing ? round(x_optimistic, digits=5) : "N/A")")
    
    # ========== Create figure ==========
    fig = PyPlot.figure(figsize=(16, 6))
    PyPlot.suptitle("$case_title    (n=$n, B=$B, $(Int(conf_level*100))% CI)", 
                    fontsize=FS_SUPTITLE, fontweight="bold", y=1.02)
    
    # ==================== Panel (a): Histogram ====================
    ax_a = fig.add_subplot(1, 2, 1)
    
    # Histogram
    data_min, data_max = minimum(data), maximum(data)
    edges = collect(range(data_min, data_max, length=nbins+1))
    
    ax_a.hist(data, bins=edges, density=false, alpha=0.7, color="#6BAED6", edgecolor="#2171B5",
              linewidth=0.5, label="Histogram (n=$n)", zorder=2)
    
    # Vertical lines for quantile and CI
    ax_a.axvline(x=q_val, color="#2171B5", linewidth=2.0, linestyle="-", 
                label="1% quantile: $(round(q_val, digits=5))", zorder=3)
    ax_a.axvline(x=ci_lo_q, color="#D62728", linewidth=1.5, linestyle="--",
                label="95% CI lower (1% quantile): $(round(ci_lo_q, digits=5))", zorder=3)
    ax_a.axvline(x=ci_hi_q, color="#2CA02C", linewidth=1.5, linestyle="--",
                label="95% CI upper (1% quantile): $(round(ci_hi_q, digits=5))", zorder=3)
    
    # Shade bootstrap CI region on the histogram x-axis
    ylims = ax_a.get_ylim()
    ax_a.axvspan(ci_lo_q, ci_hi_q, alpha=0.15, color="#CE93D8", 
                label="Bootstrap 95% CI for 1% quantile", zorder=1)
    
    ax_a.legend(loc="upper right", fontsize=FS_LEGEND, framealpha=0.9, edgecolor="gray")
    ax_a.set_xlabel("Injection Rate (m³/s)", fontsize=FS_LABEL)
    ax_a.set_ylabel("Count", fontsize=FS_LABEL)
    ax_a.set_title("(a) Injection Rate Distribution", fontsize=FS_TITLE, fontweight="bold")
    ax_a.tick_params(axis="both", labelsize=FS_TICK)
    ax_a.grid(true, linestyle="--", linewidth=0.3, alpha=0.5)
    
    # ---------- Statistics text box ----------
    # Place in the empty upper-left area of panel (a), formatted as 3 lines
    stats_text = string(
        "n=", n, "  mean=", round(mean(data), digits=5),
        "\nstd=", round(std(data), digits=5),
        "\nmin=", round(minimum(data), digits=5),
        "  max=", round(maximum(data), digits=5)
    )
    ax_a.text(0.35, 0.95, stats_text, transform=ax_a.transAxes,
             fontsize=FS_STATS, verticalalignment="top", horizontalalignment="center",
             bbox=Dict("boxstyle" => "round,pad=0.4", "facecolor" => "lightyellow", 
                       "edgecolor" => "gray", "alpha" => 0.95),
             zorder=10)
    
    # ---------- Bootstrap inset (further RIGHT to avoid histogram) ----------
    # Position: [left, bottom, width, height] in axes fraction
    inset_a = ax_a.inset_axes([0.55, 0.22, 0.40, 0.38])  # shifted more right
    
    inset_a.hist(boot_quantiles, bins=50, density=false, alpha=0.6, 
                color="#CE93D8", edgecolor="#8E24AA", linewidth=0.3)
    inset_a.axvline(x=q_val, color="#2171B5", linewidth=1.5, linestyle="-")
    inset_a.axvline(x=ci_lo_q, color="#D62728", linewidth=1.0, linestyle="--")
    inset_a.axvline(x=ci_hi_q, color="#2CA02C", linewidth=1.0, linestyle="--")
    inset_a.set_title("Bootstrap dist. of 1% quantile\n(B=$B)", fontsize=FS_INSET_TITLE)
    inset_a.tick_params(axis="both", labelsize=FS_INSET_TICK)
    inset_a.set_ylabel("Count", fontsize=FS_INSET_TICK)
    
    # ==================== Panel (b): Empirical CDF ====================
    ax_b = fig.add_subplot(1, 2, 2)
    
    # Plot bootstrap CI band
    ax_b.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100,
                     color="#BBDEFB", alpha=0.5,
                     label="95% Bootstrap CI (B=$B)", zorder=1)
    
    # Plot empirical CDF
    ax_b.plot(x_grid, ecdf_vals .* 100, color="#1565C0", linewidth=2.0,
             label="Empirical CDF", zorder=2)
    
    # Plot threshold line
    ax_b.axhline(y=threshold * 100, color="#D62728", linewidth=1.5, linestyle="--",
                label="$(Int(threshold * 100))% Fracture Probability", zorder=3)
    
    # Mark crossing points on main plot (markers only, no text annotations)
    marker_size = 10
    if x_conservative !== nothing
        ax_b.plot(x_conservative, threshold * 100, "*", color="#FF6F00", 
                 markersize=marker_size, zorder=5)
    end
    if x_ecdf !== nothing
        ax_b.plot(x_ecdf, threshold * 100, "*", color="#2E7D32",
                 markersize=marker_size, zorder=5)
    end
    if x_optimistic !== nothing
        ax_b.plot(x_optimistic, threshold * 100, "*", color="#1565C0",
                 markersize=marker_size, zorder=5)
    end
    
    ax_b.set_xlabel("Injection Rate (m³/s)", fontsize=FS_LABEL)
    ax_b.set_ylabel("Fracture Probability (%)", fontsize=FS_LABEL)
    ax_b.set_title("(b) Empirical CDF with 95% Bootstrap CI", fontsize=FS_TITLE, fontweight="bold")
    ax_b.set_ylim(0, 100)
    ax_b.legend(loc="upper left", fontsize=FS_LEGEND, framealpha=0.9, edgecolor="gray")
    ax_b.tick_params(axis="both", labelsize=FS_TICK)
    ax_b.grid(true, linestyle="--", linewidth=0.3, alpha=0.5)
    
    # ---------- Zoom-in inset: BOTTOM-RIGHT corner, shifted LEFT ----------
    # Position: [left, bottom, width, height] in axes fraction
    inset_b = ax_b.inset_axes([0.38, 0.08, 0.60, 0.48])  # slight right nudge to avoid CDF overlap in PoF
    
    # Determine zoom range around the threshold crossing
    zoom_points = filter(!isnothing, [x_conservative, x_ecdf, x_optimistic])
    if !isempty(zoom_points)
        zx_min = minimum(zoom_points) * 0.85
        zx_max = maximum(zoom_points) * 1.15
    else
        zx_min = data_min
        zx_max = data_min + (data_max - data_min) * 0.3
    end
    zoom_y_max = threshold * 100 * 8  # 0-8%
    
    # Plot in inset
    inset_b.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100,
                        color="#BBDEFB", alpha=0.5)
    inset_b.plot(x_grid, ecdf_vals .* 100, color="#1565C0", linewidth=1.5)
    inset_b.axhline(y=threshold * 100, color="#D62728", linewidth=1.0, linestyle="--")
    
    # Mark crossing points AND annotate INSIDE the zoom inset
    inset_annot_fs = 8
    if x_conservative !== nothing
        inset_b.plot(x_conservative, threshold * 100, "*", color="#FF6F00", markersize=10, zorder=5)
        inset_b.annotate("Conservative\n$(round(x_conservative, digits=5)) m³/s",
                        xy=(x_conservative, threshold * 100),
                        xytext=(-35, 30), textcoords="offset points",
                        fontsize=inset_annot_fs, color="#E65100", fontweight="bold",
                        ha="center",
                        bbox=Dict("boxstyle" => "round,pad=0.2", "facecolor" => "#FFF3E0", "alpha" => 0.9, "edgecolor" => "#FF6F00"),
                        arrowprops=Dict("arrowstyle" => "->", "color" => "#FF6F00", "connectionstyle" => "arc3,rad=-0.2"))
    end
    if x_ecdf !== nothing
        inset_b.plot(x_ecdf, threshold * 100, "*", color="#2E7D32", markersize=10, zorder=5)
        inset_b.annotate("ECDF\n$(round(x_ecdf, digits=5)) m³/s",
                        xy=(x_ecdf, threshold * 100),
                        xytext=(5, 45), textcoords="offset points",
                        fontsize=inset_annot_fs, color="#1B5E20", fontweight="bold",
                        ha="center",
                        bbox=Dict("boxstyle" => "round,pad=0.2", "facecolor" => "#E8F5E9", "alpha" => 0.9, "edgecolor" => "#2E7D32"),
                        arrowprops=Dict("arrowstyle" => "->", "color" => "#2E7D32", "connectionstyle" => "arc3,rad=0.2"))
    end
    if x_optimistic !== nothing
        inset_b.plot(x_optimistic, threshold * 100, "*", color="#1565C0", markersize=10, zorder=5)
        inset_b.annotate("Optimistic\n$(round(x_optimistic, digits=5)) m³/s",
                        xy=(x_optimistic, threshold * 100),
                        xytext=(35, 30), textcoords="offset points",
                        fontsize=inset_annot_fs, color="#0D47A1", fontweight="bold",
                        ha="center",
                        bbox=Dict("boxstyle" => "round,pad=0.2", "facecolor" => "#E3F2FD", "alpha" => 0.9, "edgecolor" => "#1565C0"),
                        arrowprops=Dict("arrowstyle" => "->", "color" => "#1565C0", "connectionstyle" => "arc3,rad=0.2"))
    end
    
    inset_b.set_xlim(zx_min, zx_max)
    inset_b.set_ylim(0, zoom_y_max)
    inset_b.set_title("Left tail zoom (0-$(Int(zoom_y_max))%)", fontsize=FS_INSET_TITLE)
    inset_b.set_xlabel("Injection Rate (m³/s)", fontsize=FS_INSET_TICK)
    inset_b.set_ylabel("Frac. Prob. (%)", fontsize=FS_INSET_TICK)
    inset_b.tick_params(axis="both", labelsize=FS_INSET_TICK)
    inset_b.grid(true, linestyle="--", linewidth=0.3, alpha=0.4)
    
    # Draw rectangle on main plot showing zoom area
    ax_b.indicate_inset_zoom(inset_b, edgecolor="gray", alpha=0.5)
    
    # Save
    PyPlot.tight_layout()
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: $filename")
end

# ===================== Main =====================
mkpath(OUTDIR)

# --- Case 1: PoF eps=0.01 ---
println("\n=== Collecting PoF eps=0.01 data ===")
pof_data = collect_data_from_dir(ROOT, "POF__HARD__eps=0.01__")
println("  Collected $(length(pof_data)) samples")

if length(pof_data) >= 2
    plot_two_panel(pof_data, "POF_eps0.01", "PoF (eps=0.01)",
                  joinpath(OUTDIR, "two_panel_POF_eps0.01.png"))
else
    @warn "Not enough PoF eps=0.01 data to plot ($(length(pof_data)) samples)"
end

# --- Case 2: CVaR g=0.05 a=0.05 ---
println("\n=== Collecting CVaR g=0.05 a=0.05 data ===")
cvar_data = collect_data_from_dir(ROOT, "CVaR__HARD__alpha=0.05__gamma=0.05__")
println("  Collected $(length(cvar_data)) samples")

if length(cvar_data) >= 2
    plot_two_panel(cvar_data, "CVaR_g0.05_a0.05", "CVaR (g=0.05 a=0.05)",
                  joinpath(OUTDIR, "two_panel_CVaR_g0.05_a0.05.png"))
else
    @warn "Not enough CVaR g=0.05 a=0.05 data to plot ($(length(cvar_data)) samples)"
end

println("\n=== Done! ===")
