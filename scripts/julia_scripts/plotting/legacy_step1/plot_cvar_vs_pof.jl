#!/usr/bin/env julia
# Panel histograms (frequency) for CVaR versus POF: Distribution of optimized injectivities
# First row: 5 POF cases (eps = 0.0, 0.001, 0.01, 0.02, 0.05)
# Remaining rows: CVaR cases (organized by gamma and alpha)

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames, Dates
using PyPlot
using KernelDensity
using JLD2

# ===================== Config =====================
const ROOT     = datadir("DT_control", "exp_name=step1")
const OUTDIR   = joinpath(projectdir(), "plots", "DT_control", "exp_name=step1", "statistical_analysis", "kde", "new_runs")
const USE_LOGX = false       # Set to true if injection rate spans large orders of magnitude (log x-axis)
const NBINS    = 30          # Number of histogram bins
const PAD      = 0.05        # Left/right padding ratio for x-axis (when using linear axis)
const KDE_BANDWIDTH = nothing  # KDE bandwidth (nothing = use default/Silverman's rule)
                                # Can specify a value like 0.01 for custom bandwidth

# Font sizes (larger for better readability)
const FONT_SIZE_TITLE = 14      # Subplot title (slightly increased)
const FONT_SIZE_SUPTITLE = 18   # Main title
const FONT_SIZE_LABEL = 16      # Axis labels (increased from 14)
const FONT_SIZE_TICK = 13       # Tick labels
# ==================================================

# ========== Find latest inj_rate_detail_*.csv ==========
function latest_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && error("Cannot find inj_rate_detail_*.csv, please run collection script first.")
    joinpath(root, sort(files)[end])
end

# ========== Find latest pof_inj_rate_detail_*.csv ==========
function latest_pof_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^pof_inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && return nothing
    joinpath(root, sort(files)[end])
end

# ========== Collect POF data directly from directories (1-128 samples) ==========
function collect_pof_from_dirs(root::AbstractString, target_eps::Vector{String})
    
    function normalize_case_tag(risk_dir_name::String)
        if occursin("POF", risk_dir_name)
            if (m = match(r"eps\s*=\s*([0-9.]+)", risk_dir_name)) !== nothing
                return "POF_eps=$(m.captures[1])"
            else
                return "POF"
            end
        end
        return risk_dir_name
    end
    
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
        case_tag = normalize_case_tag(risk_name)
        # Check if this case matches one of our target eps values
        eps_match = false
        for eps in target_eps
            if occursin("eps=$eps", risk_name) || occursin("eps=$(parse(Float64, eps))", risk_name)
                eps_match = true
                break
            end
        end
        if !eps_match
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
                    continue  # Skip load errors
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

# ========== Utility: get unique case list by prefix (sorted) ==========
function cases_with_prefix(df::DataFrame, prefix::AbstractString)
    unique(filter!(x -> startswith(x, prefix), unique(df.case_tag))) |> sort
end

# ========== Utility: collect all values for a group of cases, determine unified bins/xlim/ylim ==========
function collect_group_values(df::DataFrame, case_list::Vector{String}, xmin::Float64, xmax::Float64, nbins::Int; kde_bandwidth=nothing)
    # 返回：Dict(case_tag => Vector{Float64}), global_ymax
    vals_by_case = Dict{String, Vector{Float64}}()
    global_ymax = 0.0
    
    # Create unified bin edges
    edges = collect(range(xmin, xmax; length=nbins+1))
    bin_width = edges[2] - edges[1]
    
    for ct in case_list
        x = collect(skipmissing(df.last_inj_rate[df.case_tag .== ct]))
        vals_by_case[ct] = x
        if !isempty(x) && length(x) > 1
            # Calculate histogram counts using a temporary figure
            fig_temp = PyPlot.figure(figsize=(1,1))
            counts, _ = PyPlot.hist(x, bins=edges, density=false)
            PyPlot.close(fig_temp)
            if length(counts) > 0
                local_ymax_hist = maximum(counts)
                global_ymax = max(global_ymax, local_ymax_hist)
                
                # Also calculate KDE maximum to ensure KDE curve is not truncated
                try
                    kde_result = kde_bandwidth === nothing ? kde(x) : kde(x, bandwidth=kde_bandwidth)
                    # Scale KDE to match histogram frequency
                    kde_scaled = kde_result.density .* length(x) .* bin_width
                    local_ymax_kde = maximum(kde_scaled)
                    global_ymax = max(global_ymax, local_ymax_kde)
                catch e
                    # If KDE fails, just use histogram max
                    @warn "KDE calculation failed for case $ct when computing ymax: $e"
                end
            end
        elseif !isempty(x)
            # Single data point, just use histogram
            fig_temp = PyPlot.figure(figsize=(1,1))
            counts, _ = PyPlot.hist(x, bins=edges, density=false)
            PyPlot.close(fig_temp)
            if length(counts) > 0
                local_ymax = maximum(counts)
                global_ymax = max(global_ymax, local_ymax)
            end
        end
    end
    
    return vals_by_case, global_ymax, edges
end

# ========== Utility: format case title ==========
function format_case_title(case_tag::String)
    # For POF cases: "POF_eps=0.0" -> "POF eps=0.0"
    if startswith(case_tag, "POF")
        # Extract eps value if present (handle both "POF_eps=0.0" and "POF eps=0.0")
        if (m = match(r"eps[_\s]*=\s*([0-9.]+)", case_tag)) !== nothing
            eps_val = m.captures[1]
            return "PoF eps=$(eps_val)"
        else
            return replace(case_tag, "_" => " ")
        end
    # For CVaR cases: replace "g=" with "γ=" and "a=" with "α="
    elseif startswith(case_tag, "CVaR")
        title_text = replace(case_tag, "_" => " ")
        # Replace g= with γ= and a= with α= (handle both "g=" and "gamma=")
        title_text = replace(title_text, r"\bg\s*=" => "γ=")
        title_text = replace(title_text, r"\ba\s*=" => "α=")
        title_text = replace(title_text, r"gamma\s*=" => "γ=")
        title_text = replace(title_text, r"alpha\s*=" => "α=")
        return title_text
    else
        return replace(case_tag, "_" => " ")
    end
end

# ========== Utility: sort POF cases by eps value ==========
function sort_pof_cases_by_eps(cases::Vector{String})
    function extract_eps(case_tag::String)
        # Handle both "POF_eps=0.0" and "POF eps=0.0"
        if (m = match(r"eps[_\s]*=\s*([0-9.]+)", case_tag)) !== nothing
            return parse(Float64, m.captures[1])
        else
            return Inf  # Put cases without eps at the end
        end
    end
    return sort(cases, by=extract_eps)
end

# ========== Utility: sort CVaR cases by gamma then alpha ==========
# Sort by gamma value in ascending order (0.0, 0.01, 0.02, 0.05, ...)
function sort_cvar_cases(cases::Vector{String})
    function extract_params(case_tag::String)
        # Handle both "g=" and "gamma=", "a=" and "alpha="
        g_match = match(r"[g_]gamma[_\s]*=\s*([0-9.]+)", case_tag)
        if g_match === nothing
            g_match = match(r"g\s*=\s*([0-9.]+)", case_tag)  # Removed \b to match g=0.0 correctly
        end
        a_match = match(r"[a_]alpha[_\s]*=\s*([0-9.]+)", case_tag)
        if a_match === nothing
            a_match = match(r"a\s*=\s*([0-9.]+)", case_tag)  # Removed \b to match a=0.0 correctly
        end
        g_val = g_match !== nothing ? parse(Float64, g_match.captures[1]) : Inf
        a_val = a_match !== nothing ? parse(Float64, a_match.captures[1]) : Inf
        
        # Sort by gamma value (ascending), then by alpha value (ascending)
        return (g_val, a_val)
    end
    return sort(cases, by=extract_params)
end

# ========== Panel plotting function (frequency, aligned axes) ==========
function plot_cvar_vs_pof_panels(
        df::DataFrame,
        pof_cases::Vector{String},
        cvar_cases::Vector{String};
        filename::AbstractString,
        use_logx::Bool=false,
        nbins::Int=30)

    # Sort cases
    pof_cases_sorted = sort_pof_cases_by_eps(pof_cases)
    cvar_cases_sorted = sort_cvar_cases(cvar_cases)
    
    # Combine all cases: POF first row, then CVaR
    all_cases = vcat(pof_cases_sorted, cvar_cases_sorted)
    
    # First pass: find global xmin and xmax
    global_min = Inf
    global_max = -Inf
    for ct in all_cases
        x = collect(skipmissing(df.last_inj_rate[df.case_tag .== ct]))
        if !isempty(x)
            global_min = min(global_min, minimum(x))
            global_max = max(global_max, maximum(x))
        end
    end
    
    if global_min == Inf  # No data available
        global_min, global_max = 0.0, 1.0
    end
    
    # Add padding
    if !use_logx && isfinite(global_min) && isfinite(global_max) && global_min != global_max
        span = global_max - global_min
        xmin = global_min - PAD * span
        xmax = global_max + PAD * span
    else
        xmin = global_min
        xmax = global_max
    end

    # Second pass: collect values and calculate unified ymax (including KDE)
    vals_by_case, ymax, edges = collect_group_values(df, all_cases, xmin, xmax, nbins; kde_bandwidth=KDE_BANDWIDTH)
    
    # Add padding to ymax for better visualization
    ymax = ymax * 1.1

    # Calculate grid: first row is POF (5 cases), remaining rows are CVaR
    n_pof = length(pof_cases_sorted)
    n_cvar = length(cvar_cases_sorted)
    # Determine number of columns based on CVaR cases (typically 5 for a 5x5 grid)
    # But ensure at least 5 columns for the POF row (if POF cases exist)
    if n_pof > 0
        ncols = max(n_pof, 5)
    else
        ncols = 5  # Default to 5 columns even if no POF cases
    end
    # If CVaR cases suggest a different column count, use that
    if n_cvar > 0
        # Try to infer column count from CVaR cases (e.g., if 25 cases, likely 5x5)
        cvar_cols = ceil(Int, sqrt(n_cvar))
        ncols = max(ncols, cvar_cols)
    end
    # Calculate rows: if POF cases exist, first row is POF, then CVaR rows
    # If no POF cases, start with CVaR from row 1
    if n_pof > 0
        nrows = 1 + ceil(Int, n_cvar / ncols)  # First row for POF, then CVaR rows
    else
        nrows = ceil(Int, n_cvar / ncols)  # All rows are CVaR
    end
    
    # Increase figure size slightly and adjust subplot spacing
    fig = PyPlot.figure(figsize=(4.0*ncols, 3.0*nrows))
    PyPlot.suptitle("CVaR versus PoF: Distribution of Optimized Injectivities",
                    fontsize=FONT_SIZE_SUPTITLE, fontweight="bold", y=0.98)
    
    # Adjust subplot spacing - reduce top margin to bring title closer to plots
    # Increased hspace to add more spacing between rows (especially between gamma=0.0 row and others)
    PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.94, bottom=0.06, 
                           wspace=0.15, hspace=0.23)

    # Plot POF cases in first row (if any)
    if n_pof > 0
        for (i, ct) in enumerate(pof_cases_sorted)
            row = 1
            col = i
            idx = (row - 1) * ncols + col
        
        ax = PyPlot.subplot(nrows, ncols, idx)
        x = vals_by_case[ct]
        if use_logx
            x = filter(>(0.0), x)  # log axis requires positive numbers
        end

        if isempty(x)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", 
                       transform=ax.transAxes, fontsize=FONT_SIZE_LABEL)
        else
            if use_logx
                PyPlot.hist(x, bins=nbins, density=false, alpha=0.85, edgecolor="none")
                PyPlot.xscale("log")
            else
                # Plot histogram (steelblue - distribution)
                counts, bin_edges_actual, patches = PyPlot.hist(x, bins=edges, density=false, alpha=0.75, edgecolor="none", color="#4682B4", label=(i==1 ? "Distribution" : ""))
                # Calculate bin width for KDE scaling
                bin_width = bin_edges_actual[2] - bin_edges_actual[1]
                
                # Add KDE curve (red)
                if length(x) > 1
                    try
                        kde_result = KDE_BANDWIDTH === nothing ? kde(x) : kde(x, bandwidth=KDE_BANDWIDTH)
                        # Scale KDE to match histogram frequency
                        kde_scaled = kde_result.density .* length(x) .* bin_width
                        # Plot KDE curve
                        PyPlot.plot(kde_result.x, kde_scaled, color="red", linewidth=2.0, alpha=0.8, label=(i==1 ? "KDE curve" : ""))
                    catch e
                        # If KDE fails, just skip it
                        @warn "KDE calculation failed for case $ct: $e"
                    end
                end
                
                # Add legend only for first POF subplot (top-left)
                if i == 1
                    PyPlot.legend(loc="upper right", fontsize=9, framealpha=0.9)
                end
                
                # Set unified x and y limits for alignment
                PyPlot.xlim(xmin, xmax)
                PyPlot.ylim(0, ymax)
            end
        end

        # Format title with Greek letters
        title_text = format_case_title(ct)
        PyPlot.title(title_text, fontsize=FONT_SIZE_TITLE)
        
        # X-axis labels on bottom row
        if row == nrows
            PyPlot.xlabel(use_logx ? "Injectivity (log scale)" : "Injectivity (m³/s)", 
                         fontsize=FONT_SIZE_LABEL)
        end
        # Y-axis labels on leftmost column
        if col == 1
            PyPlot.ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
        end
        
        # Set tick label sizes
        ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.4, alpha=0.5)
        end
    end
    
    # Plot CVaR cases in subsequent rows (or starting from row 1 if no POF cases)
    for (i, ct) in enumerate(cvar_cases_sorted)
        # Calculate which row and column
        # If POF cases exist, start from row 2; otherwise start from row 1
        start_row = n_pof > 0 ? 2 : 1
        row = start_row + div(i - 1, ncols)
        col = mod(i - 1, ncols) + 1
        idx = (row - 1) * ncols + col
        
        ax = PyPlot.subplot(nrows, ncols, idx)
        x = vals_by_case[ct]
        if use_logx
            x = filter(>(0.0), x)  # log axis requires positive numbers
        end

        if isempty(x)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", 
                       transform=ax.transAxes, fontsize=FONT_SIZE_LABEL)
        else
            if use_logx
                PyPlot.hist(x, bins=nbins, density=false, alpha=0.85, edgecolor="none")
                PyPlot.xscale("log")
            else
                # Plot histogram (steelblue - distribution)
                is_first_cvar = (i == 1 && row == (n_pof > 0 ? 2 : 1))
                counts, bin_edges_actual, patches = PyPlot.hist(x, bins=edges, density=false, alpha=0.75, edgecolor="none", color="#4682B4", label=(is_first_cvar ? "Distribution" : ""))
                # Calculate bin width for KDE scaling
                bin_width = bin_edges_actual[2] - bin_edges_actual[1]
                
                # Add KDE curve (red)
                if length(x) > 1
                    try
                        kde_result = KDE_BANDWIDTH === nothing ? kde(x) : kde(x, bandwidth=KDE_BANDWIDTH)
                        # Scale KDE to match histogram frequency
                        kde_scaled = kde_result.density .* length(x) .* bin_width
                        # Plot KDE curve
                        PyPlot.plot(kde_result.x, kde_scaled, color="red", linewidth=2.0, alpha=0.8, label=(is_first_cvar ? "KDE curve" : ""))
                    catch e
                        # If KDE fails, just skip it
                        @warn "KDE calculation failed for case $ct: $e"
                    end
                end
                
                # Add legend only for first CVaR subplot
                if is_first_cvar
                    PyPlot.legend(loc="upper right", fontsize=9, framealpha=0.9)
                end
                
                # Set unified x and y limits for alignment
                PyPlot.xlim(xmin, xmax)
                PyPlot.ylim(0, ymax)
            end
        end

        # Format title with Greek letters
        title_text = format_case_title(ct)
        PyPlot.title(title_text, fontsize=FONT_SIZE_TITLE)
        
        # X-axis labels on bottom row
        if row == nrows
            PyPlot.xlabel(use_logx ? "Injectivity (log scale)" : "Injectivity (m³/s)", 
                         fontsize=FONT_SIZE_LABEL)
        end
        # Y-axis labels on leftmost column
        if col == 1
            PyPlot.ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
        end
        
        # Set tick label sizes
        ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.4, alpha=0.5)
    end

    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Statistics on missing samples ==========
function report_missing_samples(df_pof::DataFrame, df_cvar::DataFrame, pof_cases::Vector{String}, cvar_cases::Vector{String})
    println("\n" * "="^80)
    println("MISSING SAMPLES STATISTICS")
    println("="^80)
    
    # POF cases: expected range is 1-128 (now collecting full range)
    pof_total = 128
    println("POF cases (expected sample range: 1-128):")
    println()
    
    for ct in pof_cases
        case_data = df_pof[df_pof.case_tag .== ct, :]
        n_samples = length(unique(case_data.sample))
        n_missing = pof_total - n_samples
        missing_pct = 100.0 * n_missing / pof_total
        
        println("Case: $ct")
        println("  Samples present: $n_samples / $pof_total")
        if n_missing > 0
            println("  Missing: $n_missing ($(round(missing_pct, digits=2))%)")
            all_pof_samples = Set(1:pof_total)
            case_samples = Set(unique(case_data.sample))
            missing_samples = sort(collect(setdiff(all_pof_samples, case_samples)))
            println("  Missing sample IDs: $(missing_samples[1:min(10, length(missing_samples))])" * 
                   (length(missing_samples) > 10 ? " ... (showing first 10)" : ""))
        else
            println("  Missing: 0 (0.0%) - Complete!")
        end
        println()
    end
    
    # CVaR cases: expected range is 1-128
    cvar_total = 128
    println("CVaR cases (expected sample range: 1-128):")
    println()
    
    for ct in cvar_cases
        case_data = df_cvar[df_cvar.case_tag .== ct, :]
        n_samples = length(unique(case_data.sample))
        n_missing = cvar_total - n_samples
        missing_pct = 100.0 * n_missing / cvar_total
        
        println("Case: $ct")
        println("  Samples present: $n_samples / $cvar_total")
        if n_missing > 0
            println("  Missing: $n_missing ($(round(missing_pct, digits=2))%)")
            all_cvar_samples = Set(1:cvar_total)
            case_samples = Set(unique(case_data.sample))
            missing_samples = sort(collect(setdiff(all_cvar_samples, case_samples)))
            println("  Missing sample IDs: $(missing_samples[1:min(10, length(missing_samples))])" * 
                   (length(missing_samples) > 10 ? " ... (showing first 10)" : ""))
        else
            println("  Missing: 0 (0.0%) - Complete!")
        end
        println()
    end
    
    println("="^80)
end

# ===================== Main =====================
detail_csv = latest_detail_csv(ROOT)
println("Using CVaR detail CSV: ", detail_csv)

# Read CVaR data
df_cvar = CSV.read(detail_csv, DataFrame)
df_cvar_ok = df_cvar[df_cvar.status .== "ok_final", :]
df_cvar_ok.case_tag = String.(df_cvar_ok.case_tag)

# Try to read POF data from separate CSV file, or collect from directories
pof_csv = latest_pof_detail_csv(ROOT)
df_pof_ok = DataFrame()
target_eps = ["0.0", "0.001", "0.01", "0.02", "0.05"]

if pof_csv !== nothing
    println("Using POF detail CSV: ", pof_csv)
    df_pof = CSV.read(pof_csv, DataFrame)
    df_pof_ok = df_pof[df_pof.status .== "ok_final", :]
    df_pof_ok.case_tag = String.(df_pof_ok.case_tag)
    
    # Check if we have samples 1-128, if not, collect from directories
    max_sample = maximum(df_pof_ok.sample)
    if max_sample < 128
        println("POF CSV only has samples up to $max_sample, collecting from directories for samples 1-128...")
        df_pof_dirs = collect_pof_from_dirs(ROOT, target_eps)
        if nrow(df_pof_dirs) > 0
            df_pof_dirs.case_tag = String.(df_pof_dirs.case_tag)
            df_pof_ok = df_pof_dirs[df_pof_dirs.status .== "ok_final", :]
            println("Collected $(nrow(df_pof_ok)) POF samples from directories")
        end
    end
else
    println("No pof_inj_rate_detail_*.csv found, collecting POF data from directories (samples 1-128)...")
    df_pof_dirs = collect_pof_from_dirs(ROOT, target_eps)
    if nrow(df_pof_dirs) > 0
        df_pof_dirs.case_tag = String.(df_pof_dirs.case_tag)
        df_pof_ok = df_pof_dirs[df_pof_dirs.status .== "ok_final", :]
        println("Collected $(nrow(df_pof_ok)) POF samples from directories")
    end
end

# Combine dataframes (if POF data exists, merge it; otherwise use only CVaR)
if nrow(df_pof_ok) > 0
    # Rename last_inj_rate column if needed (POF CSV might use different name)
    if hasproperty(df_pof_ok, :last_inj_rate)
        # Already has the right column name
    elseif hasproperty(df_pof_ok, :last_inj)
        rename!(df_pof_ok, :last_inj => :last_inj_rate)
    end
    # Combine dataframes
    df_ok = vcat(df_pof_ok, df_cvar_ok, cols=:union)
else
    # Only CVaR data available
    df_ok = df_cvar_ok
end

# Get POF cases (filter for specific eps values: 0.0, 0.001, 0.01, 0.02, 0.05)
# Use df_pof_ok if available, otherwise fall back to df_ok
pof_all = nrow(df_pof_ok) > 0 ? unique(df_pof_ok.case_tag) : cases_with_prefix(df_ok, "POF")
target_eps = ["0.0", "0.001", "0.01", "0.02", "0.05"]
pof_cases = String[]
for eps in target_eps
    # Try to find cases matching this eps value (handle both "POF_eps=0.0" and "POF eps=0.0")
    eps_val = parse(Float64, eps)
    best_match = nothing
    best_diff = Inf
    for case in pof_all
        if (m = match(r"eps[_\s]*=\s*([0-9.]+)", case)) !== nothing
            case_eps = parse(Float64, m.captures[1])
            diff = abs(case_eps - eps_val)
            # Prefer exact match, but accept close match
            if diff < 1e-6  # Exact match
                push!(pof_cases, case)
                best_match = nothing  # Found exact, don't need best match
                break
            elseif diff < best_diff
                best_diff = diff
                best_match = case
            end
        end
    end
    # If no exact match found, use best match if it's close enough
    if best_match !== nothing && !(best_match in pof_cases) && best_diff < 0.001
        push!(pof_cases, best_match)
        if best_diff > 1e-6
            println("  Using $best_match for eps=$eps (diff=$(best_diff))")
        end
    end
end

if length(pof_cases) < length(target_eps)
    println("Warning: Only found $(length(pof_cases)) out of $(length(target_eps)) target POF cases")
    println("  Found: $pof_cases")
end

println("Found POF cases: ", pof_cases)

# Get CVaR cases
cvar_cases = cases_with_prefix(df_ok, "CVaR")
println("Found CVaR cases: ", cvar_cases)

if isempty(pof_cases)
    println("Warning: No POF cases found in the data!")
    println("  This might be expected if POF data is in a separate CSV file.")
    println("  Attempting to continue with CVaR cases only...")
    # If no POF cases, we'll just plot CVaR cases
    pof_cases = String[]
end
if isempty(cvar_cases)
    error("No CVaR cases found in the data!")
end

# If no POF cases found, adjust the plot to start with CVaR
if isempty(pof_cases)
    println("Note: Plotting CVaR cases only (no POF cases available)")
end

# Generate plot
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
mkpath(OUTDIR)
out_file = joinpath(OUTDIR, "panel_CVaR_vs_POF_distribution_optimized_injectivities_$ts.png")

all_cases_combined = vcat(sort_pof_cases_by_eps(pof_cases), sort_cvar_cases(cvar_cases))
plot_cvar_vs_pof_panels(df_ok, pof_cases, cvar_cases;
    filename=out_file,
    use_logx=USE_LOGX,
    nbins=NBINS)

# Report missing samples (separate POF and CVaR dataframes)
df_pof_ok_final = nrow(df_pof_ok) > 0 ? df_pof_ok : DataFrame()
df_cvar_ok_final = df_cvar_ok
report_missing_samples(df_pof_ok_final, df_cvar_ok_final, pof_cases, cvar_cases)

println("Done.")
