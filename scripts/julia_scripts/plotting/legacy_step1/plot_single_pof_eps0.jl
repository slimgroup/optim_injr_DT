#!/usr/bin/env julia
# Plot single POF eps = 0.0 case for paper:
# 1. Histogram + KDE
# 2. CDF + Confidence Interval
# 3. CDF + Confidence Interval Zoom-in

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames, Dates
using PyPlot
using KernelDensity
using Distributions
using JLD2

# ===================== Config =====================
const ROOT     = datadir("DT_control", "exp_name=step1")
const OUTDIR   = joinpath(projectdir(), "plots", "DT_control", "exp_name=step1", "statistical_analysis", "kde", "new_runs")
const USE_LOGX = false
const NBINS    = 30
const PAD      = 0.05
const KDE_BANDWIDTH = nothing
const NUM_GRID = 16000
const CONF_LEVEL = 0.95
const FRACTURE_PROB_THRESHOLD = 0.01
const FORWARD_STEP = 2  # MPC forward steps (must match optim_inject.jl)

# Font sizes for single plot (larger for better readability)
const FONT_SIZE_TITLE = 18
const FONT_SIZE_LABEL = 16
const FONT_SIZE_TICK = 14
const FONT_SIZE_ANNOTATION = 12
const FONT_SIZE_LEGEND = 12
# ==================================================

# ========== Collect POF data from directories ==========
function collect_pof_from_dirs(root::AbstractString, target_eps::String)
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4, inj_start::Float64=0.0001, forward_step::Int=FORWARD_STEP)
        raw = get(data, "inj_rate_arr", nothing)
        raw === nothing && return (init_rate + inj_start) / 2.0
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        
        idx = findlast(!iszero, clean)
        if idx === nothing
            return (init_rate + inj_start) / 2.0
        end
        
        last_nonzero = clean[idx]
        inj_rate_full = collect(range(inj_start, last_nonzero, forward_step * 6))
        if length(inj_rate_full) >= 6
            inj_rate_at_index6 = inj_rate_full[6]
            return (inj_rate_at_index6 + inj_start) / 2.0
        else
            return (last_nonzero + inj_start) / 2.0
        end
    end
    
    rows = NamedTuple[]
    seen_samples = Set{Int}()
    risk_dirs = filter(d ->
        isdir(joinpath(root, d)) &&
        occursin("POF", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(root))
    
    for risk_name in risk_dirs
        if !occursin("eps=$target_eps", risk_name) && !occursin("eps=$(parse(Float64, target_eps))", risk_name)
            continue
        end
        
        risk_dir = joinpath(root, risk_name)
        for s in 1:128
            if s in seen_samples
                continue
            end
            
            sdir = joinpath(risk_dir, "sample=$(s)")
            final_path = joinpath(sdir, "final.jld2")
            
            if isfile(final_path)
                status = "ok_final"
                last_inj = NaN
                try
                    data = load(final_path)
                    last_inj = last_nonzero_inj_rate(data; init_rate=1e-4)
                catch err
                    status = "load_error"
                    continue
                end
                push!(rows, (
                    case_tag = "POF_eps=$target_eps",
                    risk_dir = risk_name,
                    sample = s,
                    status = status,
                    last_inj_rate = last_inj,
                    file_used = final_path,
                    note = ""
                ))
                push!(seen_samples, s)
            end
        end
    end
    
    return DataFrame(rows)
end

# ========== Compute CDF and Confidence Interval ==========
function compute_cdf_ci(data::Vector{Float64}; kde_bandwidth=nothing, num_grid::Int=NUM_GRID, conf_level::Float64=CONF_LEVEL)
    if isempty(data) || length(data) < 2
        error("Need at least 2 data points")
    end
    
    kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
    
    x_min = minimum(data)
    x_max = maximum(data)
    x_grid = collect(range(x_min, stop=x_max, length=num_grid))
    dx = x_grid[2] - x_grid[1]
    
    pdf_vals = pdf(kde_result, x_grid)
    cdf_vals = cumsum(pdf_vals) .* dx
    cdf_vals = cdf_vals ./ cdf_vals[end]
    
    n = length(data)
    z = quantile(Normal(), 1 - (1 - conf_level) / 2)
    
    ci_lower = zeros(length(x_grid))
    ci_upper = zeros(length(x_grid))
    
    for i in eachindex(cdf_vals)
        p_hat = cdf_vals[i]
        se = sqrt(p_hat * (1 - p_hat) / n)
        ci_lower[i] = max(0.0, p_hat - z * se)
        ci_upper[i] = min(1.0, p_hat + z * se)
    end
    
    return x_grid, cdf_vals, ci_lower, ci_upper
end

# ========== Find threshold crossing points ==========
function find_threshold_crossings(x_grid::Vector{Float64}, cdf::Vector{Float64}, 
                                  ci_lower::Vector{Float64}, ci_upper::Vector{Float64},
                                  threshold::Float64)
    idx_cdf = findfirst(x -> x >= threshold, cdf)
    x_cdf = idx_cdf !== nothing ? x_grid[idx_cdf] : nothing
    
    idx_upper = findfirst(x -> x >= threshold, ci_upper)
    x_left_ci = idx_upper !== nothing ? x_grid[idx_upper] : nothing
    
    idx_lower = findfirst(x -> x >= threshold, ci_lower)
    x_right_ci = idx_lower !== nothing ? x_grid[idx_lower] : nothing
    
    return x_left_ci, x_cdf, x_right_ci
end

# ========== Plot Single Histogram + KDE ==========
function plot_single_histogram_kde(data::Vector{Float64}, case_tag::String, filename::AbstractString;
                                   kde_bandwidth=nothing, nbins::Int=NBINS)
    if isempty(data)
        @warn "No data to plot"
        return
    end
    
    global_min = minimum(data)
    global_max = maximum(data)
    
    if isfinite(global_min) && isfinite(global_max) && global_min != global_max
        span = global_max - global_min
        xmin = global_min - PAD * span
        xmax = global_max + PAD * span
    else
        xmin = global_min
        xmax = global_max
    end
    
    edges = collect(range(xmin, xmax; length=nbins+1))
    bin_width = edges[2] - edges[1]
    
    # Create figure
    fig = PyPlot.figure(figsize=(8, 6))
    ax = fig.add_subplot(111)
    
    # Plot histogram
    counts, bin_edges_actual, patches = ax.hist(data, bins=edges, density=false, 
                                                 alpha=0.75, edgecolor="none", 
                                                 color="#4682B4", 
                                                 label="Distribution")
    bin_width_actual = bin_edges_actual[2] - bin_edges_actual[1]
    
    # Add KDE curve
    if length(data) > 1
        try
            kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
            kde_scaled = kde_result.density .* length(data) .* bin_width_actual
            ax.plot(kde_result.x, kde_scaled, color="red", linewidth=2.5, 
                   alpha=0.8, label="KDE curve")
        catch e
            @warn "KDE calculation failed: $e"
        end
    end
    
    ax.legend(loc="upper right", fontsize=FONT_SIZE_LEGEND, framealpha=0.9)
    ax.set_xlim(xmin, xmax)
    
    # Title with sample count
    n_samples = length(data)
    title_text = "POF ε = 0.0 (n=$n_samples)"
    ax.set_title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
    ax.set_xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
    ax.set_ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
    
    ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
    ax.grid(true, linestyle="--", linewidth=0.4, alpha=0.5)
    
    PyPlot.tight_layout()
    PyPlot.savefig(filename, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Plot Single CDF + CI ==========
function plot_single_cdf_ci(data::Vector{Float64}, case_tag::String, filename::AbstractString;
                            kde_bandwidth=nothing, num_grid::Int=NUM_GRID, 
                            conf_level::Float64=CONF_LEVEL, threshold::Float64=FRACTURE_PROB_THRESHOLD)
    if isempty(data) || length(data) < 2
        @warn "Need at least 2 data points"
        return
    end
    
    x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data; kde_bandwidth=kde_bandwidth, 
                                                      num_grid=num_grid, conf_level=conf_level)
    x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, threshold)
    
    color = "#1f77b4"
    
    fig = PyPlot.figure(figsize=(8, 6))
    ax = fig.add_subplot(111)
    
    # Plot CDF
    ax.plot(x_grid, cdf .* 100, color=color, linewidth=2.5, label="CDF")
    
    # Plot CI
    ax.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                   color="lightgray", alpha=0.3, 
                   label="$(Int(conf_level * 100))% CI")
    
    # Plot threshold line
    ax.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
              label="$(Int(threshold * 100))% Fracture Probability")
    
    # Add annotations (Left CI: directly above, CDF: more right, Right CI: even more upper right)
    if x_left_ci !== nothing
        y_left = threshold * 100
        ax.plot(x_left_ci, y_left, "o", color=color, markersize=8)
        ax.annotate("Left CI: $(round(x_left_ci, digits=5))", 
                   xy=(x_left_ci, y_left), 
                   xytext=(0, 50), textcoords="offset points",
                   fontsize=FONT_SIZE_ANNOTATION, color="black", ha="center",
                   bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                   arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    if x_cdf !== nothing
        y_cdf = threshold * 100
        ax.plot(x_cdf, y_cdf, "o", color=color, markersize=8)
        ax.annotate("CDF: $(round(x_cdf, digits=5))", 
                   xy=(x_cdf, y_cdf), 
                   xytext=(90, 30), textcoords="offset points",
                   fontsize=FONT_SIZE_ANNOTATION, color="black", ha="left",
                   bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                   arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    # Add Right CI annotation (upper right)
    if x_right_ci !== nothing
        y_right = threshold * 100
        ax.plot(x_right_ci, y_right, "o", color=color, markersize=8)
        ax.annotate("Right CI: $(round(x_right_ci, digits=5))", 
                   xy=(x_right_ci, y_right), 
                   xytext=(60, 70), textcoords="offset points",
                   fontsize=FONT_SIZE_ANNOTATION, color="black", ha="left",
                   bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                   arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    title_text = "POF ε = 0.0"
    ax.set_title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
    ax.set_ylim(0, 100)
    ax.legend(loc="lower right", fontsize=FONT_SIZE_LEGEND, framealpha=0.9)
    ax.set_xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
    ax.set_ylabel("Fracture Probability (%)", fontsize=FONT_SIZE_LABEL)
    
    ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
    ax.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    
    PyPlot.tight_layout()
    PyPlot.savefig(filename, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Plot Single CDF + CI Zoom-in ==========
function plot_single_cdf_ci_zoom(data::Vector{Float64}, case_tag::String, filename::AbstractString;
                                 kde_bandwidth=nothing, num_grid::Int=NUM_GRID, 
                                 conf_level::Float64=CONF_LEVEL, threshold::Float64=FRACTURE_PROB_THRESHOLD)
    if isempty(data) || length(data) < 2
        @warn "Need at least 2 data points"
        return
    end
    
    x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data; kde_bandwidth=kde_bandwidth, 
                                                      num_grid=num_grid, conf_level=conf_level)
    x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, threshold)
    
    # Determine zoom range
    if x_cdf !== nothing
        zoom_x_min = x_cdf * 0.7
        zoom_x_max = x_cdf * 1.3
    else
        zoom_x_min = minimum(x_grid)
        zoom_x_max = maximum(x_grid)
    end
    zoom_y_max = threshold * 100 * 4  # Show up to 4%
    
    color = "#1f77b4"
    
    fig = PyPlot.figure(figsize=(8, 6))
    ax = fig.add_subplot(111)
    
    # Plot CDF
    ax.plot(x_grid, cdf .* 100, color=color, linewidth=2.5, label="CDF")
    
    # Plot CI
    ax.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                   color="lightgray", alpha=0.3, 
                   label="$(Int(conf_level * 100))% CI")
    
    # Plot threshold line
    ax.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
              label="$(Int(threshold * 100))% Fracture Probability")
    
    # Add annotations (all shifted more to the left and higher)
    if x_left_ci !== nothing
        y_left = threshold * 100
        ax.plot(x_left_ci, y_left, "o", color=color, markersize=10)
        ax.annotate("Left CI: $(round(x_left_ci, digits=5))", 
                   xy=(x_left_ci, y_left), 
                   xytext=(-50, 65), textcoords="offset points",
                   fontsize=FONT_SIZE_ANNOTATION, color="black", ha="center",
                   bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                   arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    if x_cdf !== nothing
        y_cdf = threshold * 100
        ax.plot(x_cdf, y_cdf, "o", color=color, markersize=10)
        ax.annotate("CDF: $(round(x_cdf, digits=5))", 
                   xy=(x_cdf, y_cdf), 
                   xytext=(5, 60), textcoords="offset points",
                   fontsize=FONT_SIZE_ANNOTATION, color="black", ha="left",
                   bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                   arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    # Add Right CI annotation (shifted more to the left and higher)
    if x_right_ci !== nothing
        y_right = threshold * 100
        ax.plot(x_right_ci, y_right, "o", color=color, markersize=10)
        ax.annotate("Right CI: $(round(x_right_ci, digits=5))", 
                   xy=(x_right_ci, y_right), 
                   xytext=(0, 70), textcoords="offset points",
                   fontsize=FONT_SIZE_ANNOTATION, color="black", ha="left",
                   bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                   arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    title_text = "POF ε = 0.0 (Zoomed In)"
    ax.set_title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
    ax.set_xlim(zoom_x_min, zoom_x_max)
    ax.set_ylim(0, zoom_y_max)
    ax.legend(loc="lower right", fontsize=FONT_SIZE_LEGEND, framealpha=0.9)
    ax.set_xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
    ax.set_ylabel("Fracture Probability (%)", fontsize=FONT_SIZE_LABEL)
    
    ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
    ax.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    
    PyPlot.tight_layout()
    PyPlot.savefig(filename, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ===================== Main =====================
println("Collecting POF eps=0.0 data from directories...")
df_pof = collect_pof_from_dirs(ROOT, "0.0")
df_pof_ok = df_pof[df_pof.status .== "ok_final", :]

if nrow(df_pof_ok) == 0
    error("No POF eps=0.0 data found!")
end

# Remove duplicates based on sample ID
if hasproperty(df_pof_ok, :sample)
    unique_df = df_pof_ok[.!nonunique(df_pof_ok, :sample), :]
    if nrow(unique_df) < nrow(df_pof_ok)
        println("Removed $(nrow(df_pof_ok) - nrow(unique_df)) duplicate samples")
    end
    df_pof_ok = unique_df
end

# Limit to 128 samples
if nrow(df_pof_ok) > 128
    println("Warning: $(nrow(df_pof_ok)) samples found, limiting to 128")
    df_pof_ok = df_pof_ok[1:128, :]
end

data = collect(skipmissing(df_pof_ok.last_inj_rate))
println("\nPOF eps=0.0: $(length(data)) samples")

# Generate timestamp
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

# Plot and save individual figures
mkpath(OUTDIR)
filename1 = joinpath(OUTDIR, "POF_eps0_histogram_kde_$(ts).png")
plot_single_histogram_kde(data, "POF_eps=0.0", filename1; kde_bandwidth=KDE_BANDWIDTH, nbins=NBINS)

filename2 = joinpath(OUTDIR, "POF_eps0_cdf_ci_$(ts).png")
plot_single_cdf_ci(data, "POF_eps=0.0", filename2; kde_bandwidth=KDE_BANDWIDTH, 
                     num_grid=NUM_GRID, conf_level=CONF_LEVEL, threshold=FRACTURE_PROB_THRESHOLD)

filename3 = joinpath(OUTDIR, "POF_eps0_cdf_ci_zoom_$(ts).png")
plot_single_cdf_ci_zoom(data, "POF_eps=0.0", filename3; kde_bandwidth=KDE_BANDWIDTH, 
                        num_grid=NUM_GRID, conf_level=CONF_LEVEL, threshold=FRACTURE_PROB_THRESHOLD)

println("\n=== Done! ===")
println("Saved files:")
println("  1. $filename1")
println("  2. $filename2")
println("  3. $filename3")

