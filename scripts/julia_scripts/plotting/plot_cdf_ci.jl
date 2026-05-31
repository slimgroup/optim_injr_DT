#!/usr/bin/env julia
# Plot CDF and 95% Confidence Interval for fracture probability vs injection rate

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
const KDE_BANDWIDTH = nothing  # KDE bandwidth (nothing = use default)
const NUM_GRID = 16000          # Number of grid points for KDE evaluation
const CONF_LEVEL = 0.95          # Confidence level (95%)
const FRACTURE_PROB_THRESHOLD = 0.01  # 1% fracture probability

# Font sizes
const FONT_SIZE_TITLE = 16
const FONT_SIZE_LABEL = 14
const FONT_SIZE_TICK = 12
const FONT_SIZE_ANNOTATION = 11
# ==================================================

# ========== Find latest CSV files ==========
function _aggregate_csv_dirs(root::AbstractString)
    [joinpath(root, "_aggregates", "csv"), root]
end

function latest_detail_csv(root::AbstractString)
    for dir in _aggregate_csv_dirs(root)
        isdir(dir) || continue
        files = filter(f -> occursin(r"^inj_rate_detail_.*\.csv$", f), readdir(dir))
        if !isempty(files)
            return joinpath(dir, sort(files)[end])
        end
    end
    error("Cannot find inj_rate_detail_*.csv")
end

function latest_pof_detail_csv(root::AbstractString)
    for dir in _aggregate_csv_dirs(root)
        isdir(dir) || continue
        files = filter(f -> occursin(r"^pof_inj_rate_detail_.*\.csv$", f), readdir(dir))
        if !isempty(files)
            return joinpath(dir, sort(files)[end])
        end
    end
    return nothing
end

# ========== Collect POF data from directories ==========
function collect_pof_from_dirs(root::AbstractString, target_eps::String)
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4)
        raw = get(data, "inj_rate_arr", nothing)
        raw === nothing && return init_rate
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        idx = findlast(!iszero, clean)
        return idx === nothing ? init_rate : clean[idx]
    end
    
    rows = NamedTuple[]
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
            end
        end
    end
    
    return DataFrame(rows)
end

# ========== Collect CVaR data from directories ==========
function collect_cvar_from_dirs(root::AbstractString, target_alpha::String, target_gamma::String)
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4)
        raw = get(data, "inj_rate_arr", nothing)
        raw === nothing && return init_rate
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        idx = findlast(!iszero, clean)
        return idx === nothing ? init_rate : clean[idx]
    end
    
    rows = NamedTuple[]
    risk_dirs = filter(d ->
        isdir(joinpath(root, d)) &&
        occursin("CVaR", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(root))
    
    for risk_name in risk_dirs
        alpha_match = occursin("alpha=$target_alpha", risk_name) || occursin("alpha=$(parse(Float64, target_alpha))", risk_name)
        gamma_match = occursin("gamma=$target_gamma", risk_name) || occursin("gamma=$(parse(Float64, target_gamma))", risk_name)
        
        if !alpha_match || !gamma_match
            continue
        end
        
        case_tag = "CVaR_g=$(target_gamma)_a=$(target_alpha)"
        
        risk_dir = joinpath(root, risk_name)
        for s in 1:128
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
                    case_tag = case_tag,
                    risk_dir = risk_name,
                    sample = s,
                    status = status,
                    last_inj_rate = last_inj,
                    file_used = final_path,
                    note = ""
                ))
            end
        end
    end
    
    return DataFrame(rows)
end

# ========== Format case title ==========
function format_case_title(case_tag::String)
    if startswith(case_tag, "POF")
        if (m = match(r"eps[_\s]*=\s*([0-9.]+)", case_tag)) !== nothing
            eps_val = m.captures[1]
            return "POF eps=$(eps_val)"
        else
            return replace(case_tag, "_" => " ")
        end
    elseif startswith(case_tag, "CVaR")
        title_text = replace(case_tag, "_" => " ")
        title_text = replace(title_text, r"\bg\s*=" => "γ=")
        title_text = replace(title_text, r"\ba\s*=" => "α=")
        return title_text
    else
        return replace(case_tag, "_" => " ")
    end
end

# ========== Compute CDF and Confidence Interval ==========
function compute_cdf_ci(data::Vector{Float64}; kde_bandwidth=nothing, num_grid::Int=NUM_GRID, conf_level::Float64=CONF_LEVEL)
    if isempty(data) || length(data) < 2
        error("Need at least 2 data points")
    end
    
    # Compute KDE
    kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
    
    # Create grid for evaluation
    x_min = minimum(data)
    x_max = maximum(data)
    x_grid = collect(range(x_min, stop=x_max, length=num_grid))
    dx = x_grid[2] - x_grid[1]
    
    # Compute PDF values at grid points
    pdf_vals = pdf(kde_result, x_grid)
    
    # Compute CDF by cumulative sum
    cdf_vals = cumsum(pdf_vals) .* dx
    
    # Normalize CDF to ensure it ends at 1.0
    cdf_vals = cdf_vals ./ cdf_vals[end]
    
    # Compute confidence interval using Bernoulli assumption
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
    
    # Alternative: use Wilson score interval for better coverage
    # for i in eachindex(cdf_vals)
    #     p_hat = cdf_vals[i]
    #     z2 = z^2
    #     denom = 1 + z2 / n
    #     center = p_hat + z2 / (2n)
    #     radicand = p_hat * (1 - p_hat) / n + z2 / (4n^2)
    #     delta = z * sqrt(radicand)
    #     ci_lower[i] = max(0.0, (center - delta) / denom)
    #     ci_upper[i] = min(1.0, (center + delta) / denom)
    # end
    
    return x_grid, cdf_vals, ci_lower, ci_upper
end

# ========== Find threshold crossing points ==========
function find_threshold_crossings(x_grid::Vector{Float64}, cdf::Vector{Float64}, 
                                  ci_lower::Vector{Float64}, ci_upper::Vector{Float64},
                                  threshold::Float64)
    # Find CDF crossing
    idx_cdf = findfirst(x -> x >= threshold, cdf)
    x_cdf = idx_cdf !== nothing ? x_grid[idx_cdf] : nothing
    
    # ci_upper is the upper bound (higher probability), so it reaches threshold earlier (smaller x) = Left CI
    idx_upper = findfirst(x -> x >= threshold, ci_upper)
    x_left_ci = idx_upper !== nothing ? x_grid[idx_upper] : nothing
    
    # ci_lower is the lower bound (lower probability), so it reaches threshold later (larger x) = Right CI
    idx_lower = findfirst(x -> x >= threshold, ci_lower)
    x_right_ci = idx_lower !== nothing ? x_grid[idx_lower] : nothing
    
    return x_left_ci, x_cdf, x_right_ci
end

# ========== Plot multiple CDFs with zoom-in ==========
function plot_multiple_cdf_ci(cases_data::Vector{Tuple{String, Vector{Float64}}}, filename::AbstractString;
                              kde_bandwidth=nothing, num_grid::Int=NUM_GRID, 
                              conf_level::Float64=CONF_LEVEL, threshold::Float64=FRACTURE_PROB_THRESHOLD)
    ncases = length(cases_data)
    if ncases == 0
        @warn "No cases to plot"
        return
    end
    
    # Compute CDF and CI for all cases
    all_results = []
    for (case_tag, data) in cases_data
        if isempty(data) || length(data) < 2
            continue
        end
        x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data; kde_bandwidth=kde_bandwidth, 
                                                          num_grid=num_grid, conf_level=conf_level)
        x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, threshold)
        push!(all_results, (case_tag, x_grid, cdf, ci_lower, ci_upper, x_left_ci, x_cdf, x_right_ci))
    end
    
    if isempty(all_results)
        @warn "No valid data to plot"
        return
    end
    
    # Determine global x range
    all_x_min = minimum([minimum(r[2]) for r in all_results])
    all_x_max = maximum([maximum(r[2]) for r in all_results])
    
    # Determine zoom-in range (around 1% threshold area)
    all_x_cdf = [r[7] for r in all_results if r[7] !== nothing]
    if !isempty(all_x_cdf)
        zoom_x_min = minimum(all_x_cdf) * 0.7
        zoom_x_max = maximum(all_x_cdf) * 1.3
        zoom_y_max = threshold * 100 * 4  # Show up to 4% for zoom
    else
        zoom_x_min = all_x_min
        zoom_x_max = all_x_max
        zoom_y_max = threshold * 100 * 4
    end
    
    # Create figure with subplots: 2x2 main plots + 2x2 zoom plots
    fig = PyPlot.figure(figsize=(16, 12))
    PyPlot.suptitle("Fracture Probability vs Injectivity: CDF with 95% Confidence Intervals", 
                    fontsize=18, fontweight="bold", y=0.98)
    
    # Adjust subplot spacing
    PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.93, bottom=0.07, 
                           wspace=0.25, hspace=0.35)
    
    # Color palette (nicer colors)
    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728"]  # Blue, Orange, Green, Red
    
    # Plot main figures (2x2)
    for (idx, result) in enumerate(all_results)
        case_tag, x_grid, cdf, ci_lower, ci_upper, x_left_ci, x_cdf, x_right_ci = result
        
        # Main plot
        ax_main = PyPlot.subplot(4, 2, 2*idx - 1)
        
        # Plot CDF
        PyPlot.plot(x_grid, cdf .* 100, color=colors[idx], linewidth=2.5, label="CDF")
        
        # Plot CI
        PyPlot.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                           color="lightgray", alpha=0.3, 
                           label="$(Int(conf_level * 100))% CI")
        
        # Plot threshold line
        PyPlot.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
                      label="$(Int(threshold * 100))% Fracture Probability")
        
        # Add annotations (only Left CI and CDF)
        if x_left_ci !== nothing
            y_left = threshold * 100
            PyPlot.plot(x_left_ci, y_left, "o", color=colors[idx], markersize=6)
            # Adjust annotation position to avoid going outside plot
            x_offset = x_left_ci < (all_x_min + (all_x_max - all_x_min) * 0.25) ? 40 : -60
            PyPlot.annotate("Left CI: $(round(x_left_ci, digits=5))", 
                           xy=(x_left_ci, y_left), 
                           xytext=(x_offset, 25), textcoords="offset points",
                           fontsize=9, color="black", ha=x_offset > 0 ? "left" : "right",
                           bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                           arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
        end
        
        if x_cdf !== nothing
            y_cdf = threshold * 100
            PyPlot.plot(x_cdf, y_cdf, "o", color=colors[idx], markersize=6)
            PyPlot.annotate("CDF: $(round(x_cdf, digits=5))", 
                           xy=(x_cdf, y_cdf), 
                           xytext=(0, 40), textcoords="offset points",
                           fontsize=9, color="black", ha="center",
                           bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                           arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
        end
        
        # Format
        title_text = format_case_title(case_tag)
        PyPlot.title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
        PyPlot.xlim(all_x_min, all_x_max)
        PyPlot.ylim(0, 100)
        
        if idx == 1
            PyPlot.legend(loc="lower right", fontsize=9, framealpha=0.9)
        end
        
        # Labels only on outer edges
        # Injectivity label only on last row (idx == 4), not second-to-last
        if idx == 4
            PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
        end
        # Fracture Probability label only on first column (all rows in first column)
        PyPlot.ylabel("Fracture Probability (%)", fontsize=FONT_SIZE_LABEL)
        
        ax_main.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
        
        # Zoom-in plot
        ax_zoom = PyPlot.subplot(4, 2, 2*idx)
        
        # Plot CDF
        PyPlot.plot(x_grid, cdf .* 100, color=colors[idx], linewidth=2.5, label="CDF")
        
        # Plot CI
        PyPlot.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                           color="lightgray", alpha=0.3, 
                           label="$(Int(conf_level * 100))% CI")
        
        # Plot threshold line
        PyPlot.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
                      label="$(Int(threshold * 100))% Fracture Probability")
        
        # Add annotations (only Left CI and CDF)
        if x_left_ci !== nothing
            y_left = threshold * 100
            PyPlot.plot(x_left_ci, y_left, "o", color=colors[idx], markersize=8)
            # Adjust annotation position to avoid going outside plot
            x_offset = x_left_ci < (zoom_x_min + (zoom_x_max - zoom_x_min) * 0.25) ? 40 : -60
            PyPlot.annotate("Left CI: $(round(x_left_ci, digits=5))", 
                           xy=(x_left_ci, y_left), 
                           xytext=(x_offset, 25), textcoords="offset points",
                           fontsize=9, color="black", ha=x_offset > 0 ? "left" : "right",
                           bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                           arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
        end
        
        if x_cdf !== nothing
            y_cdf = threshold * 100
            PyPlot.plot(x_cdf, y_cdf, "o", color=colors[idx], markersize=8)
            PyPlot.annotate("CDF: $(round(x_cdf, digits=5))", 
                           xy=(x_cdf, y_cdf), 
                           xytext=(0, 40), textcoords="offset points",
                           fontsize=9, color="black", ha="center",
                           bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                           arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
        end
        
        # Format zoom plot
        PyPlot.title("$title_text (Zoomed In)", fontsize=FONT_SIZE_TITLE - 2, fontweight="bold")
        PyPlot.xlim(zoom_x_min, zoom_x_max)
        PyPlot.ylim(0, zoom_y_max)
        
        # Labels only on outer edges
        # Injectivity label only on last row (idx == 4), not second-to-last
        if idx == 4
            PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
        end
        # No y-label for zoom plots (they're in the second column)
        
        ax_zoom.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    end
    
    # Save
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Plot CDF with CI ==========
function plot_cdf_ci(data::Vector{Float64}, case_tag::String, filename::AbstractString;
                     kde_bandwidth=nothing, num_grid::Int=NUM_GRID, 
                     conf_level::Float64=CONF_LEVEL, threshold::Float64=FRACTURE_PROB_THRESHOLD)
    if isempty(data) || length(data) < 2
        @warn "No data for case $case_tag, skipping plot"
        return
    end
    
    # Compute CDF and CI
    x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data; kde_bandwidth=kde_bandwidth, 
                                                      num_grid=num_grid, conf_level=conf_level)
    
    # Find threshold crossings
    x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, threshold)
    
    # Create figure
    fig = PyPlot.figure(figsize=(10, 7))
    ax = PyPlot.gca()
    
    # Plot CDF (convert to percentage) - using a nicer blue
    PyPlot.plot(x_grid, cdf .* 100, color="#2E86AB", linewidth=2.5, label="CDF")
    
    # Plot confidence interval (convert to percentage)
    PyPlot.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                       color="lightgray", alpha=0.3, 
                       label="$(Int(conf_level * 100))% Confidence Interval")
    
    # Plot 1% fracture probability line
    PyPlot.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
                  label="$(Int(threshold * 100))% Fracture Probability")
    
    # Add annotations (adjust positions to avoid overlap)
    if x_left_ci !== nothing
        y_left = threshold * 100
        PyPlot.plot(x_left_ci, y_left, "o", color="#2E86AB", markersize=8)
        PyPlot.annotate("Left CI: $(round(x_left_ci, digits=5))", 
                       xy=(x_left_ci, y_left), 
                       xytext=(-50, 20), textcoords="offset points",
                       fontsize=FONT_SIZE_ANNOTATION, color="black", ha="right",
                       bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                       arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    if x_cdf !== nothing
        y_cdf = threshold * 100
        PyPlot.plot(x_cdf, y_cdf, "o", color="#2E86AB", markersize=8)
        PyPlot.annotate("CDF: $(round(x_cdf, digits=5))", 
                       xy=(x_cdf, y_cdf), 
                       xytext=(0, -35), textcoords="offset points",
                       fontsize=FONT_SIZE_ANNOTATION, color="black", ha="center",
                       bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                       arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    if x_right_ci !== nothing
        y_right = threshold * 100
        PyPlot.plot(x_right_ci, y_right, "o", color="#2E86AB", markersize=8)
        PyPlot.annotate("Right CI: $(round(x_right_ci, digits=5))", 
                       xy=(x_right_ci, y_right), 
                       xytext=(50, 20), textcoords="offset points",
                       fontsize=FONT_SIZE_ANNOTATION, color="black", ha="left",
                       bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                       arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
    end
    
    # Format title
    title_text = format_case_title(case_tag)
    PyPlot.title("Fracture Probability vs Injectivity — $title_text", fontsize=FONT_SIZE_TITLE, fontweight="bold")
    PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
    PyPlot.ylabel("Fracture Probability (%)", fontsize=FONT_SIZE_LABEL)
    
    # Set limits
    PyPlot.xlim(minimum(x_grid), maximum(x_grid))
    PyPlot.ylim(0, 100)
    
    # Add legend
    PyPlot.legend(loc="lower right", fontsize=11, framealpha=0.9)
    
    # Set tick label sizes
    ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
    PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    
    # Save
    PyPlot.tight_layout()
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
    
    # Print summary
    println("  Threshold crossings at $(Int(threshold * 100))%:")
    if x_left_ci !== nothing
        println("    Left CI:  $(round(x_left_ci, digits=5)) m³/s")
    end
    if x_cdf !== nothing
        println("    CDF:      $(round(x_cdf, digits=5)) m³/s")
    end
    if x_right_ci !== nothing
        println("    Right CI: $(round(x_right_ci, digits=5)) m³/s")
    end
end

# ===================== Main =====================
# Read CVaR data
detail_csv = latest_detail_csv(ROOT)
println("Using CVaR detail CSV: ", detail_csv)
df_cvar = CSV.read(detail_csv, DataFrame)
df_cvar_ok = df_cvar[df_cvar.status .== "ok_final", :]
df_cvar_ok.case_tag = String.(df_cvar_ok.case_tag)

# Read POF data
pof_csv = latest_pof_detail_csv(ROOT)
df_pof_ok = DataFrame()

if pof_csv !== nothing
    println("Using POF detail CSV: ", pof_csv)
    df_pof = CSV.read(pof_csv, DataFrame)
    df_pof_ok = df_pof[df_pof.status .== "ok_final", :]
    df_pof_ok.case_tag = String.(df_pof_ok.case_tag)
    
    max_sample = maximum(df_pof_ok.sample)
    if max_sample < 128
        println("POF CSV only has samples up to $max_sample, collecting from directories...")
        df_pof_dirs = collect_pof_from_dirs(ROOT, "0.05")
        if nrow(df_pof_dirs) > 0
            df_pof_dirs.case_tag = String.(df_pof_dirs.case_tag)
            df_pof_ok = df_pof_dirs[df_pof_dirs.status .== "ok_final", :]
            println("Collected $(nrow(df_pof_ok)) POF samples from directories")
        end
    end
else
    println("No pof_inj_rate_detail_*.csv found, collecting POF data from directories...")
    df_pof_dirs = collect_pof_from_dirs(ROOT, "0.05")
    if nrow(df_pof_dirs) > 0
        df_pof_dirs.case_tag = String.(df_pof_dirs.case_tag)
        df_pof_ok = df_pof_dirs[df_pof_dirs.status .== "ok_final", :]
        println("Collected $(nrow(df_pof_ok)) POF samples from directories")
    end
end

# Combine dataframes
if nrow(df_pof_ok) > 0
    if hasproperty(df_pof_ok, :last_inj)
        rename!(df_pof_ok, :last_inj => :last_inj_rate)
    end
    df_ok = vcat(df_pof_ok, df_cvar_ok, cols=:union)
else
    df_ok = df_cvar_ok
end

# Define cases to plot
cases_to_plot = [
    "POF_eps=0.05",
    "CVaR_g=0.05_a=0.05",
    "CVaR_g=0.1_a=0.05",
    "CVaR_g=0.2_a=0.05"
]

# Generate timestamp
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

# Collect data for all cases
cases_data = Tuple{String, Vector{Float64}}[]

# Collect data for each case
for case_tag in cases_to_plot
    case_data = DataFrame()
    
    if case_tag == "POF_eps=0.05"
        case_data = filter(row -> begin
            ct = row.case_tag
            occursin("POF", ct) && (occursin("eps=0.05", ct) || occursin("eps=0.050", ct))
        end, df_ok)
        
        if nrow(case_data) == 0
            println("POF case not found in CSV, collecting from directories...")
            local df_pof_dirs_local = collect_pof_from_dirs(ROOT, "0.05")
            if nrow(df_pof_dirs_local) > 0
                df_pof_dirs_local.case_tag = String.(df_pof_dirs_local.case_tag)
                case_data = df_pof_dirs_local[df_pof_dirs_local.status .== "ok_final", :]
            end
        end
    elseif case_tag == "CVaR_g=0.05_a=0.05"
        case_data = filter(row -> begin
            ct = row.case_tag
            occursin("CVaR", ct) && occursin("g=0.05", ct) && occursin("a=0.05", ct)
        end, df_ok)
    elseif case_tag == "CVaR_g=0.1_a=0.05"
        case_data = filter(row -> begin
            ct = row.case_tag
            occursin("CVaR", ct) && occursin("g=0.1", ct) && occursin("a=0.05", ct)
        end, df_ok)
        
        if nrow(case_data) == 0
            println("CVaR g=0.1 a=0.05 not found in CSV, collecting from directories...")
            local df_cvar_dirs_local = collect_cvar_from_dirs(ROOT, "0.05", "0.1")
            if nrow(df_cvar_dirs_local) > 0
                df_cvar_dirs_local.case_tag = String.(df_cvar_dirs_local.case_tag)
                case_data = df_cvar_dirs_local[df_cvar_dirs_local.status .== "ok_final", :]
            end
        end
    elseif case_tag == "CVaR_g=0.2_a=0.05"
        case_data = filter(row -> begin
            ct = row.case_tag
            occursin("CVaR", ct) && occursin("g=0.2", ct) && occursin("a=0.05", ct)
        end, df_ok)
        
        if nrow(case_data) == 0
            println("CVaR g=0.2 a=0.05 not found in CSV, collecting from directories...")
            local df_cvar_dirs_local = collect_cvar_from_dirs(ROOT, "0.05", "0.2")
            if nrow(df_cvar_dirs_local) > 0
                df_cvar_dirs_local.case_tag = String.(df_cvar_dirs_local.case_tag)
                case_data = df_cvar_dirs_local[df_cvar_dirs_local.status .== "ok_final", :]
            end
        end
    else
        case_data = filter(row -> row.case_tag == case_tag, df_ok)
    end
    
    if nrow(case_data) == 0
        @warn "No data found for case: $case_tag"
        continue
    end
    
    # Extract data
    data = collect(skipmissing(case_data.last_inj_rate))
    println("\nCase $case_tag: $(length(data)) samples")
    
    # Store data for combined plot
    push!(cases_data, (case_tag, data))
    
    # Optional: also plot individual cases (comment out if not needed)
    # safe_case = replace(case_tag, "=" => "_", " " => "_")
    # filename = joinpath(ROOT, "cdf_ci_$(safe_case)_$(ts).png")
    # plot_cdf_ci(data, case_tag, filename; kde_bandwidth=KDE_BANDWIDTH, 
    #             num_grid=NUM_GRID, conf_level=CONF_LEVEL, threshold=FRACTURE_PROB_THRESHOLD)
end

# Plot all cases together with zoom-in
if length(cases_data) > 0
    combined_filename = joinpath(OUTDIR, "combined_cdf_ci_4cases_$(ts).png")
    mkpath(OUTDIR)
    plot_multiple_cdf_ci(cases_data, combined_filename; kde_bandwidth=KDE_BANDWIDTH, 
                       num_grid=NUM_GRID, conf_level=CONF_LEVEL, threshold=FRACTURE_PROB_THRESHOLD)
end

println("\nDone.")

