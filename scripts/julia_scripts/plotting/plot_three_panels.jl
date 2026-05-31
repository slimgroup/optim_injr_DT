#!/usr/bin/env julia
# Plot three panels:
# 1. Histogram + KDE curve (4x3 layout)
# 2. CDF + Confidence Interval (4x3 layout)
# 3. CDF + Confidence Interval Zoom-in (4x3 layout)

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

# Font sizes
const FONT_SIZE_TITLE = 14
const FONT_SIZE_SUPTITLE = 18
const FONT_SIZE_LABEL = 16
const FONT_SIZE_TICK = 13
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
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4, inj_start::Float64=0.0001, forward_step::Int=FORWARD_STEP)
        raw = get(data, "inj_rate_arr", nothing)
        raw === nothing && return (init_rate + inj_start) / 2.0
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        
        # Find the last nonzero element from inj_rate_arr
        idx = findlast(!iszero, clean)
        if idx === nothing
            return (init_rate + inj_start) / 2.0
        end
        
        last_nonzero = clean[idx]  # This is the last nonzero element
        # Reconstruct the full injection rate array: range(inj_start, last_nonzero, forward_step * 6)
        # This matches the logic in optim_inject.jl line 430: inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
        inj_rate_full = collect(range(inj_start, last_nonzero, forward_step * 6))
        # Select the 6th element (1-based indexing, i.e., index 6)
        # range produces (forward_step * 6) = 12 elements, so we have indices 1 through 12
        if length(inj_rate_full) >= 6
            inj_rate_at_index6 = inj_rate_full[6]
            return (inj_rate_at_index6 + inj_start) / 2.0
        else
            # Fallback: if array is too short, use last_nonzero
            return (last_nonzero + inj_start) / 2.0
        end
    end
    
    rows = NamedTuple[]
    seen_samples = Set{Int}()  # Track which samples we've already processed
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
            # Skip if we've already processed this sample
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
                push!(seen_samples, s)  # Mark this sample as processed
            end
        end
    end
    
    return DataFrame(rows)
end

# ========== Collect CVaR data from directories ==========
function collect_cvar_from_dirs(root::AbstractString, target_alpha::String, target_gamma::String)
    function last_nonzero_inj_rate(data; init_rate::Float64=1e-4, inj_start::Float64=0.0001, forward_step::Int=FORWARD_STEP)
        raw = get(data, "inj_rate_arr", nothing)
        raw === nothing && return (init_rate + inj_start) / 2.0
        col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
        clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
        
        # Find the last nonzero element from inj_rate_arr
        idx = findlast(!iszero, clean)
        if idx === nothing
            return (init_rate + inj_start) / 2.0
        end
        
        last_nonzero = clean[idx]  # This is the last nonzero element
        # Reconstruct the full injection rate array: range(inj_start, last_nonzero, forward_step * 6)
        # This matches the logic in optim_inject.jl line 430: inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
        inj_rate_full = collect(range(inj_start, last_nonzero, forward_step * 6))
        # Select the 6th element (1-based indexing, i.e., index 6)
        # range produces (forward_step * 6) = 12 elements, so we have indices 1 through 12
        if length(inj_rate_full) >= 6
            inj_rate_at_index6 = inj_rate_full[6]
            return (inj_rate_at_index6 + inj_start) / 2.0
        else
            # Fallback: if array is too short, use last_nonzero
            return (last_nonzero + inj_start) / 2.0
        end
    end
    
    rows = NamedTuple[]
    seen_samples = Set{Int}()  # Track which samples we've already processed
    risk_dirs = filter(d ->
        isdir(joinpath(root, d)) &&
        occursin("CVaR", d) &&
        d != "geo" &&
        !startswith(d, ".")
    , readdir(root))
    
    # For gamma=0.0, alpha=0.0: prefer alpha=0.0 directory over alpha=0.001
    # First, check if alpha=0.0 directory exists; if yes, only use that
    # If no, then fall back to alpha=0.001
    alpha_0_dir_exists = false
    if target_gamma == "0.0" && target_alpha == "0.0"
        gamma_pattern = r"gamma=([0-9.]+)"
        alpha_pattern = r"alpha=([0-9.]+)"
        for d in risk_dirs
            if (gm = match(gamma_pattern, d)) !== nothing && 
               (am = match(alpha_pattern, d)) !== nothing &&
               abs(parse(Float64, gm.captures[1]) - 0.0) < 1e-6 &&
               abs(parse(Float64, am.captures[1]) - 0.0) < 1e-6
                alpha_0_dir_exists = true
                break
            end
        end
    end
    
    for risk_name in risk_dirs
        # More precise matching: use regex to match exact values
        # For alpha: match "alpha=0.0" to "alpha=0.001", and exact match for others
        # But if alpha=0.0 directory exists, only use that (don't use alpha=0.001)
        alpha_pattern = r"alpha=([0-9.]+)"
        alpha_match = false
        alpha_val_matched = nothing
        if (m = match(alpha_pattern, risk_name)) !== nothing
            alpha_val = parse(Float64, m.captures[1])
            target_alpha_val = parse(Float64, target_alpha)
            # alpha=0.0 in case_tag maps to alpha=0.001 in directory name, but prefer alpha=0.0 if exists
            if target_alpha_val == 0.0
                if alpha_0_dir_exists
                    # If alpha=0.0 directory exists, only match alpha=0.0, not alpha=0.001
                    alpha_match = abs(alpha_val - 0.0) < 1e-6
                else
                    # If alpha=0.0 directory doesn't exist, fall back to alpha=0.001
                    alpha_match = (alpha_val == 0.001 || abs(alpha_val - 0.0) < 1e-6)
                end
            else
                alpha_match = abs(alpha_val - target_alpha_val) < 1e-6
            end
            if alpha_match
                alpha_val_matched = alpha_val
            end
        end
        
        # For gamma: match "gamma=0.0" but not "gamma=0.01"
        gamma_pattern = r"gamma=([0-9.]+)"
        gamma_match = false
        if (m = match(gamma_pattern, risk_name)) !== nothing
            gamma_val = parse(Float64, m.captures[1])
            target_gamma_val = parse(Float64, target_gamma)
            gamma_match = abs(gamma_val - target_gamma_val) < 1e-6
        end
        
        if !alpha_match || !gamma_match
            continue
        end
        
        # Debug: print which directory is being used
        if target_gamma == "0.0"
            println("  Matching directory: $risk_name (alpha=$alpha_val_matched, gamma=$gamma_val)")
        end
        
        case_tag = "CVaR_g=$(target_gamma)_a=$(target_alpha)"
        
        risk_dir = joinpath(root, risk_name)
        for s in 1:128
            # Skip if we've already processed this sample
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
                    case_tag = case_tag,
                    risk_dir = risk_name,
                    sample = s,
                    status = status,
                    last_inj_rate = last_inj,
                    file_used = final_path,
                    note = ""
                ))
                push!(seen_samples, s)  # Mark this sample as processed
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

# ========== Plot Panel 1: Histogram + KDE (4x3) ==========
function plot_histogram_kde_panel(cases_data::Vector{Tuple{String, Vector{Float64}}}, filename::AbstractString;
                                   kde_bandwidth=nothing, nbins::Int=NBINS)
    ncases = length(cases_data)
    if ncases != 12
        @warn "Expected 12 cases, got $ncases"
    end
    
    # Determine global x range
    all_data = vcat([d for (_, d) in cases_data]...)
    if isempty(all_data)
        @warn "No data to plot"
        return
    end
    
    global_min = minimum(all_data)
    global_max = maximum(all_data)
    
    # Add padding
    if !USE_LOGX && isfinite(global_min) && isfinite(global_max) && global_min != global_max
        span = global_max - global_min
        xmin = global_min - PAD * span
        xmax = global_max + PAD * span
    else
        xmin = global_min
        xmax = global_max
    end
    
    # Create unified bin edges
    edges = collect(range(xmin, xmax; length=nbins+1))
    bin_width = edges[2] - edges[1]
    
    # Calculate global ymax (including KDE)
    global_ymax = 0.0
    for (case_tag, data) in cases_data
        if !isempty(data) && length(data) > 1
            # Histogram
            fig_temp = PyPlot.figure(figsize=(1,1))
            counts, _ = PyPlot.hist(data, bins=edges, density=false)
            PyPlot.close(fig_temp)
            if length(counts) > 0
                local_ymax_hist = maximum(counts)
                global_ymax = max(global_ymax, local_ymax_hist)
                
                # KDE
                try
                    kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
                    kde_scaled = kde_result.density .* length(data) .* bin_width
                    local_ymax_kde = maximum(kde_scaled)
                    global_ymax = max(global_ymax, local_ymax_kde)
                catch e
                    @warn "KDE calculation failed for case $case_tag: $e"
                end
            end
        end
    end
    
    # Add padding to ymax
    ymax = global_ymax * 1.1
    
    # Create figure: 4 rows x 3 columns
    fig = PyPlot.figure(figsize=(15, 12))
    PyPlot.suptitle("Distribution of Optimized Injectivities: Histogram + KDE", 
                    fontsize=FONT_SIZE_SUPTITLE, fontweight="bold", y=0.98)
    PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.94, bottom=0.06, 
                           wspace=0.15, hspace=0.25)
    
    # Plot each case
    for (idx, (case_tag, data)) in enumerate(cases_data)
        row = div(idx - 1, 3) + 1
        col = mod(idx - 1, 3) + 1
        subplot_idx = (row - 1) * 3 + col
        
        ax = PyPlot.subplot(4, 3, subplot_idx)
        
        if isempty(data)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", 
                       transform=ax.transAxes, fontsize=FONT_SIZE_LABEL)
        else
            # Plot histogram
            counts, bin_edges_actual, patches = PyPlot.hist(data, bins=edges, density=false, 
                                                           alpha=0.75, edgecolor="none", 
                                                           color="#4682B4", 
                                                           label=(idx==1 ? "Distribution" : ""))
            bin_width_actual = bin_edges_actual[2] - bin_edges_actual[1]
            
            # Add KDE curve
            if length(data) > 1
                try
                    kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
                    kde_scaled = kde_result.density .* length(data) .* bin_width_actual
                    PyPlot.plot(kde_result.x, kde_scaled, color="red", linewidth=2.0, 
                              alpha=0.8, label=(idx==1 ? "KDE curve" : ""))
                catch e
                    @warn "KDE calculation failed for case $case_tag: $e"
                end
            end
            
            # Add legend only for first subplot
            if idx == 1
                PyPlot.legend(loc="upper right", fontsize=9, framealpha=0.9)
            end
            
            # Set unified limits
            PyPlot.xlim(xmin, xmax)
            PyPlot.ylim(0, ymax)
        end
        
        # Format title with sample count
        title_text = format_case_title(case_tag)
        n_samples = length(data)
        title_with_count = "$title_text (n=$n_samples)"
        PyPlot.title(title_with_count, fontsize=FONT_SIZE_TITLE, fontweight="bold")
        
        # Labels only on outer edges
        if row == 4  # Last row
            PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
        end
        if col == 1  # First column
            PyPlot.ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
        end
        
        ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.4, alpha=0.5)
    end
    
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Plot Panel 2: CDF + CI (4x3) ==========
function plot_cdf_ci_panel(cases_data::Vector{Tuple{String, Vector{Float64}}}, filename::AbstractString;
                            kde_bandwidth=nothing, num_grid::Int=NUM_GRID, 
                            conf_level::Float64=CONF_LEVEL, threshold::Float64=FRACTURE_PROB_THRESHOLD)
    ncases = length(cases_data)
    if ncases != 12
        @warn "Expected 12 cases, got $ncases"
    end
    
    # Compute CDF and CI for all cases - keep track of original index
    all_results = []
    for (orig_idx, (case_tag, data)) in enumerate(cases_data)
        if isempty(data) || length(data) < 2
            push!(all_results, (orig_idx, case_tag, nothing, nothing, nothing, nothing, nothing, nothing, nothing))
            continue
        end
        try
            x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data; kde_bandwidth=kde_bandwidth, 
                                                              num_grid=num_grid, conf_level=conf_level)
            x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, threshold)
            push!(all_results, (orig_idx, case_tag, x_grid, cdf, ci_lower, ci_upper, x_left_ci, x_cdf, x_right_ci))
        catch e
            @warn "Failed to compute CDF for case $case_tag: $e"
            push!(all_results, (orig_idx, case_tag, nothing, nothing, nothing, nothing, nothing, nothing, nothing))
        end
    end
    
    # Determine global x range (only from valid results)
    valid_results = [r for r in all_results if r[3] !== nothing]
    if isempty(valid_results)
        @warn "No valid data to plot"
        return
    end
    
    all_x_min = minimum([minimum(r[3]) for r in valid_results])
    all_x_max = maximum([maximum(r[3]) for r in valid_results])
    
    # Color palette
    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b",
              "#e377c2", "#7f7f7f", "#bcbd22", "#17becf", "#aec7e8", "#ffbb78"]
    
    # Create figure: 4 rows x 3 columns
    fig = PyPlot.figure(figsize=(15, 12))
    PyPlot.suptitle("Fracture Probability vs Injectivity: CDF with 95% Confidence Intervals", 
                    fontsize=FONT_SIZE_SUPTITLE, fontweight="bold", y=0.98)
    PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.94, bottom=0.06, 
                           wspace=0.15, hspace=0.25)
    
    # Plot each case using original index
    for result in all_results
        orig_idx, case_tag, x_grid, cdf, ci_lower, ci_upper, x_left_ci, x_cdf, x_right_ci = result
        
        # Skip if no valid data
        if x_grid === nothing
            row = div(orig_idx - 1, 3) + 1
            col = mod(orig_idx - 1, 3) + 1
            subplot_idx = (row - 1) * 3 + col
            ax = PyPlot.subplot(4, 3, subplot_idx)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", 
                       transform=ax.transAxes, fontsize=FONT_SIZE_LABEL)
            title_text = format_case_title(case_tag)
            PyPlot.title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
            continue
        end
        
        row = div(orig_idx - 1, 3) + 1
        col = mod(orig_idx - 1, 3) + 1
        subplot_idx = (row - 1) * 3 + col
        
        ax = PyPlot.subplot(4, 3, subplot_idx)
        
        # Plot CDF
        PyPlot.plot(x_grid, cdf .* 100, color=colors[orig_idx], linewidth=2.5, label="CDF")
        
        # Plot CI
        PyPlot.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                           color="lightgray", alpha=0.3, 
                           label=(orig_idx==1 ? "$(Int(conf_level * 100))% CI" : ""))
        
        # Plot threshold line
        PyPlot.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
                      label=(orig_idx==1 ? "$(Int(threshold * 100))% Fracture Probability" : ""))
        
        # Add annotations (Left CI and CDF)
        if x_left_ci !== nothing
            y_left = threshold * 100
            PyPlot.plot(x_left_ci, y_left, "o", color=colors[orig_idx], markersize=6)
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
            PyPlot.plot(x_cdf, y_cdf, "o", color=colors[orig_idx], markersize=6)
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
        
        if orig_idx == 1
            PyPlot.legend(loc="lower right", fontsize=9, framealpha=0.9)
        end
        
        # Labels only on outer edges
        if row == 4  # Last row
            PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
        end
        if col == 1  # First column
            PyPlot.ylabel("Fracture Probability (%)", fontsize=FONT_SIZE_LABEL)
        end
        
        ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    end
    
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Plot Panel 3: CDF + CI Zoom-in (4x3) ==========
function plot_cdf_ci_zoom_panel(cases_data::Vector{Tuple{String, Vector{Float64}}}, filename::AbstractString;
                                 kde_bandwidth=nothing, num_grid::Int=NUM_GRID, 
                                 conf_level::Float64=CONF_LEVEL, threshold::Float64=FRACTURE_PROB_THRESHOLD)
    ncases = length(cases_data)
    if ncases != 12
        @warn "Expected 12 cases, got $ncases"
    end
    
    # Compute CDF and CI for all cases - keep track of original index
    all_results = []
    for (orig_idx, (case_tag, data)) in enumerate(cases_data)
        if isempty(data) || length(data) < 2
            push!(all_results, (orig_idx, case_tag, nothing, nothing, nothing, nothing, nothing, nothing, nothing))
            continue
        end
        try
            x_grid, cdf, ci_lower, ci_upper = compute_cdf_ci(data; kde_bandwidth=kde_bandwidth, 
                                                              num_grid=num_grid, conf_level=conf_level)
            x_left_ci, x_cdf, x_right_ci = find_threshold_crossings(x_grid, cdf, ci_lower, ci_upper, threshold)
            push!(all_results, (orig_idx, case_tag, x_grid, cdf, ci_lower, ci_upper, x_left_ci, x_cdf, x_right_ci))
        catch e
            @warn "Failed to compute CDF for case $case_tag: $e"
            push!(all_results, (orig_idx, case_tag, nothing, nothing, nothing, nothing, nothing, nothing, nothing))
        end
    end
    
    # Determine zoom-in range (around 1% threshold area) - only from valid results
    valid_results = [r for r in all_results if r[3] !== nothing]
    if isempty(valid_results)
        @warn "No valid data to plot"
        return
    end
    
    all_x_cdf = []
    for result in valid_results
        _, _, _, _, _, _, x_cdf, _ = result
        if x_cdf !== nothing
            push!(all_x_cdf, x_cdf)
        end
    end
    
    if !isempty(all_x_cdf)
        zoom_x_min = minimum(all_x_cdf) * 0.7
        zoom_x_max = maximum(all_x_cdf) * 1.3
        zoom_y_max = threshold * 100 * 4  # Show up to 4% for zoom
    else
        # Fallback: use global range
        all_x_min = minimum([minimum(r[3]) for r in valid_results])
        all_x_max = maximum([maximum(r[3]) for r in valid_results])
        zoom_x_min = all_x_min
        zoom_x_max = all_x_max
        zoom_y_max = threshold * 100 * 4
    end
    
    # Color palette
    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b",
              "#e377c2", "#7f7f7f", "#bcbd22", "#17becf", "#aec7e8", "#ffbb78"]
    
    # Create figure: 4 rows x 3 columns
    fig = PyPlot.figure(figsize=(15, 12))
    PyPlot.suptitle("Fracture Probability vs Injectivity: CDF with 95% Confidence Intervals (Zoomed In)", 
                    fontsize=FONT_SIZE_SUPTITLE, fontweight="bold", y=0.98)
    PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.94, bottom=0.06, 
                           wspace=0.15, hspace=0.25)
    
    # Plot each case using original index
    for result in all_results
        orig_idx, case_tag, x_grid, cdf, ci_lower, ci_upper, x_left_ci, x_cdf, x_right_ci = result
        
        # Skip if no valid data
        if x_grid === nothing
            row = div(orig_idx - 1, 3) + 1
            col = mod(orig_idx - 1, 3) + 1
            subplot_idx = (row - 1) * 3 + col
            ax = PyPlot.subplot(4, 3, subplot_idx)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", 
                       transform=ax.transAxes, fontsize=FONT_SIZE_LABEL)
            title_text = format_case_title(case_tag)
            PyPlot.title("$title_text (Zoomed In)", fontsize=FONT_SIZE_TITLE, fontweight="bold")
            continue
        end
        
        row = div(orig_idx - 1, 3) + 1
        col = mod(orig_idx - 1, 3) + 1
        subplot_idx = (row - 1) * 3 + col
        
        ax = PyPlot.subplot(4, 3, subplot_idx)
        
        # Plot CDF
        PyPlot.plot(x_grid, cdf .* 100, color=colors[orig_idx], linewidth=2.5, label="CDF")
        
        # Plot CI
        PyPlot.fill_between(x_grid, ci_lower .* 100, ci_upper .* 100, 
                           color="lightgray", alpha=0.3, 
                           label=(orig_idx==1 ? "$(Int(conf_level * 100))% CI" : ""))
        
        # Plot threshold line
        PyPlot.axhline(y=threshold * 100, color="red", linestyle="--", linewidth=1.5,
                      label=(orig_idx==1 ? "$(Int(threshold * 100))% Fracture Probability" : ""))
        
        # Add annotations (Left CI and CDF)
        if x_left_ci !== nothing
            y_left = threshold * 100
            PyPlot.plot(x_left_ci, y_left, "o", color=colors[orig_idx], markersize=8)
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
            PyPlot.plot(x_cdf, y_cdf, "o", color=colors[orig_idx], markersize=8)
            PyPlot.annotate("CDF: $(round(x_cdf, digits=5))", 
                           xy=(x_cdf, y_cdf), 
                           xytext=(0, 40), textcoords="offset points",
                           fontsize=9, color="black", ha="center",
                           bbox=Dict("boxstyle" => "round,pad=0.3", "facecolor" => "white", "alpha" => 0.8),
                           arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"))
        end
        
        # Format
        title_text = format_case_title(case_tag)
        PyPlot.title("$title_text (Zoomed In)", fontsize=FONT_SIZE_TITLE, fontweight="bold")
        PyPlot.xlim(zoom_x_min, zoom_x_max)
        PyPlot.ylim(0, zoom_y_max)
        
        if orig_idx == 1
            PyPlot.legend(loc="lower right", fontsize=9, framealpha=0.9)
        end
        
        # Labels only on outer edges
        if row == 4  # Last row
            PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
        end
        if col == 1  # First column
            PyPlot.ylabel("Fracture Probability (%)", fontsize=FONT_SIZE_LABEL)
        end
        
        ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    end
    
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
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
        for eps in ["0.0", "0.01", "0.05"]
            df_pof_dirs = collect_pof_from_dirs(ROOT, eps)
            if nrow(df_pof_dirs) > 0
                df_pof_dirs.case_tag = String.(df_pof_dirs.case_tag)
                df_pof_dirs_ok = df_pof_dirs[df_pof_dirs.status .== "ok_final", :]
                global df_pof_ok = vcat(df_pof_ok, df_pof_dirs_ok, cols=:union)
            end
        end
        println("Collected POF samples from directories")
    end
else
    println("No pof_inj_rate_detail_*.csv found, collecting POF data from directories...")
    df_pof_ok = DataFrame()
    for eps in ["0.0", "0.01", "0.05"]
        df_pof_dirs = collect_pof_from_dirs(ROOT, eps)
        if nrow(df_pof_dirs) > 0
            df_pof_dirs.case_tag = String.(df_pof_dirs.case_tag)
            df_pof_dirs_ok = df_pof_dirs[df_pof_dirs.status .== "ok_final", :]
            global df_pof_ok = vcat(df_pof_ok, df_pof_dirs_ok, cols=:union)
        end
    end
    println("Collected POF samples from directories")
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

# Define cases to plot (4x3 layout)
# Set to true to use gamma=0 cases in row 2, false for gamma=0.05
const USE_GAMMA_ZERO_ROW2 = true

if USE_GAMMA_ZERO_ROW2
    cases_to_plot = [
        # Row 1: POF
        "POF_eps=0.0",
        "POF_eps=0.01",
        "POF_eps=0.05",
        # Row 2: CVaR gamma=0.0
        "CVaR_g=0.0_a=0.0",
        "CVaR_g=0.0_a=0.01",
        "CVaR_g=0.0_a=0.05",
        # Row 3: CVaR gamma=0.1
        "CVaR_g=0.1_a=0.0",
        "CVaR_g=0.1_a=0.01",
        "CVaR_g=0.1_a=0.05",
        # Row 4: CVaR gamma=0.2
        "CVaR_g=0.2_a=0.0",
        "CVaR_g=0.2_a=0.01",
        "CVaR_g=0.2_a=0.05"
    ]
else
    cases_to_plot = [
        # Row 1: POF
        "POF_eps=0.0",
        "POF_eps=0.01",
        "POF_eps=0.05",
        # Row 2: CVaR gamma=0.05
        "CVaR_g=0.05_a=0.0",
        "CVaR_g=0.05_a=0.01",
        "CVaR_g=0.05_a=0.05",
        # Row 3: CVaR gamma=0.1
        "CVaR_g=0.1_a=0.0",
        "CVaR_g=0.1_a=0.01",
        "CVaR_g=0.1_a=0.05",
        # Row 4: CVaR gamma=0.2
        "CVaR_g=0.2_a=0.0",
        "CVaR_g=0.2_a=0.01",
        "CVaR_g=0.2_a=0.05"
    ]
end

# Generate timestamp
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

# Collect data for all cases
cases_data = Tuple{String, Vector{Float64}}[]

for case_tag in cases_to_plot
    case_data = DataFrame()
    
    if startswith(case_tag, "POF")
        eps_match = match(r"eps[_\s]*=\s*([0-9.]+)", case_tag)
        if eps_match !== nothing
            eps_val = String(eps_match.captures[1])
            # Always collect from directories to ensure updated calculation logic is used
            println("POF case $case_tag: collecting from directories with updated calculation...")
            local df_pof_dirs_local = collect_pof_from_dirs(ROOT, eps_val)
            if nrow(df_pof_dirs_local) > 0
                df_pof_dirs_local.case_tag = String.(df_pof_dirs_local.case_tag)
                case_data = df_pof_dirs_local[df_pof_dirs_local.status .== "ok_final", :]
            end
        end
    elseif startswith(case_tag, "CVaR")
        # Extract gamma and alpha
        g_match = match(r"g\s*=\s*([0-9.]+)", case_tag)
        a_match = match(r"a\s*=\s*([0-9.]+)", case_tag)
        
        if g_match !== nothing && a_match !== nothing
            g_val = String(g_match.captures[1])
            a_val = String(a_match.captures[1])
            
            # Always collect from directories to ensure updated calculation logic is used
            println("CVaR g=$g_val a=$a_val: collecting from directories with updated calculation...")
            local df_cvar_dirs_local = collect_cvar_from_dirs(ROOT, a_val, g_val)
            if nrow(df_cvar_dirs_local) > 0
                df_cvar_dirs_local.case_tag = String.(df_cvar_dirs_local.case_tag)
                case_data = df_cvar_dirs_local[df_cvar_dirs_local.status .== "ok_final", :]
                # Debug: print which directories were used
                if g_val == "0.0"
                    used_dirs = unique(case_data.risk_dir)
                    println("  Used directories: $used_dirs")
                    println("  Number of samples: $(nrow(case_data))")
                    if length(used_dirs) > 1
                        @warn "  WARNING: Multiple directories matched for g=$g_val a=$a_val: $used_dirs"
                    end
                end
            end
        end
    end
    
    if nrow(case_data) == 0
        @warn "No data found for case: $case_tag"
        push!(cases_data, (case_tag, Float64[]))
        continue
    end
    
    # Extract data and ensure unique samples (by sample ID)
    # Remove duplicates based on sample ID, keeping the first occurrence
    if hasproperty(case_data, :sample)
        # Remove duplicate samples, keeping the first occurrence
        unique_case_data = case_data[.!nonunique(case_data, :sample), :]
        if nrow(unique_case_data) < nrow(case_data)
            println("  Removed $(nrow(case_data) - nrow(unique_case_data)) duplicate samples")
        end
        case_data = unique_case_data
    end
    
    # Limit to 128 samples if more than that
    if nrow(case_data) > 128
        println("  Warning: $(nrow(case_data)) samples found, limiting to 128")
        case_data = case_data[1:128, :]
    end
    
    # Extract data
    data = collect(skipmissing(case_data.last_inj_rate))
    println("\nCase $case_tag: $(length(data)) samples")
    
    # Store data
    push!(cases_data, (case_tag, data))
end

# Plot Panel 1: Histogram + KDE
if length(cases_data) > 0
    mkpath(OUTDIR)
    suffix = USE_GAMMA_ZERO_ROW2 ? "_gamma0_row2" : ""
    filename1 = joinpath(OUTDIR, "panel1_histogram_kde_4x3$(suffix)_$(ts).png")
    plot_histogram_kde_panel(cases_data, filename1; kde_bandwidth=KDE_BANDWIDTH, nbins=NBINS)
end

# Plot Panel 2: CDF + CI
if length(cases_data) > 0
    suffix = USE_GAMMA_ZERO_ROW2 ? "_gamma0_row2" : ""
    filename2 = joinpath(OUTDIR, "panel2_cdf_ci_4x3$(suffix)_$(ts).png")
    plot_cdf_ci_panel(cases_data, filename2; kde_bandwidth=KDE_BANDWIDTH, 
                     num_grid=NUM_GRID, conf_level=CONF_LEVEL, threshold=FRACTURE_PROB_THRESHOLD)
end

# Plot Panel 3: CDF + CI Zoom-in
if length(cases_data) > 0
    suffix = USE_GAMMA_ZERO_ROW2 ? "_gamma0_row2" : ""
    filename3 = joinpath(OUTDIR, "panel3_cdf_ci_zoom_4x3$(suffix)_$(ts).png")
    plot_cdf_ci_zoom_panel(cases_data, filename3; kde_bandwidth=KDE_BANDWIDTH, 
                           num_grid=NUM_GRID, conf_level=CONF_LEVEL, threshold=FRACTURE_PROB_THRESHOLD)
end

println("\nDone.")

