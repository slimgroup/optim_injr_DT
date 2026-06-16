#!/usr/bin/env julia
# Plot individual cases with histogram and KDE curve

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames, Dates
using PyPlot
using KernelDensity

# ===================== Config =====================
const ROOT     = datadir("DT_control", "exp_name=step1")
const OUTDIR   = joinpath(projectdir(), "plots", "DT_control", "exp_name=step1", "statistical_analysis", "kde", "new_runs")
const NBINS    = 30          # Number of histogram bins
const PAD      = 0.05        # Left/right padding ratio for x-axis
const KDE_BANDWIDTH = nothing  # KDE bandwidth (nothing = use default/Silverman's rule)

# Font sizes
const FONT_SIZE_TITLE = 16
const FONT_SIZE_LABEL = 14
const FONT_SIZE_TICK = 12
# ==================================================

# ========== Find latest CSV files ==========
function latest_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && error("Cannot find inj_rate_detail_*.csv")
    joinpath(root, sort(files)[end])
end

function latest_pof_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^pof_inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && return nothing
    joinpath(root, sort(files)[end])
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
        # Check if this case matches target alpha and gamma
        alpha_match = occursin("alpha=$target_alpha", risk_name) || occursin("alpha=$(parse(Float64, target_alpha))", risk_name)
        gamma_match = occursin("gamma=$target_gamma", risk_name) || occursin("gamma=$(parse(Float64, target_gamma))", risk_name)
        
        if !alpha_match || !gamma_match
            continue
        end
        
        # Create case_tag in normalized format
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

# ========== Collect POF data from directories ==========
function collect_pof_from_dirs(root::AbstractString, target_eps::String)
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
        # Check if this case matches target eps
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
            return "PoF eps=$(eps_val)"
        else
            return replace(case_tag, "_" => " ")
        end
    elseif startswith(case_tag, "CVaR")
        title_text = replace(case_tag, "_" => " ")
        title_text = replace(title_text, r"\bg\s*=" => "γ=")
        title_text = replace(title_text, r"\ba\s*=" => "α=")
        title_text = replace(title_text, r"gamma\s*=" => "γ=")
        title_text = replace(title_text, r"alpha\s*=" => "α=")
        return title_text
    else
        return replace(case_tag, "_" => " ")
    end
end

# ========== Plot single case ==========
function plot_single_case(data::Vector{Float64}, case_tag::String, filename::AbstractString; 
                          nbins::Int=30, kde_bandwidth=nothing)
    if isempty(data)
        @warn "No data for case $case_tag, skipping plot"
        return
    end
    
    # Calculate x range
    xmin_data = minimum(data)
    xmax_data = maximum(data)
    span = xmax_data - xmin_data
    xmin = xmin_data - PAD * span
    xmax = xmax_data + PAD * span
    
    # Create bin edges
    edges = collect(range(xmin, xmax; length=nbins+1))
    bin_width = edges[2] - edges[1]
    
    # Calculate histogram
    fig_temp = PyPlot.figure(figsize=(1,1))
    counts, bin_edges_actual = PyPlot.hist(data, bins=edges, density=false)
    PyPlot.close(fig_temp)
    
    # Calculate KDE
    kde_result = nothing
    kde_scaled = nothing
    if length(data) > 1
        try
            kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
            kde_scaled = kde_result.density .* length(data) .* bin_width
        catch e
            @warn "KDE calculation failed for case $case_tag: $e"
        end
    end
    
    # Calculate ymax (include both histogram and KDE)
    ymax = maximum(counts)
    if kde_scaled !== nothing
        ymax = max(ymax, maximum(kde_scaled))
    end
    ymax = ymax * 1.1  # Add 10% padding
    
    # Create figure
    fig = PyPlot.figure(figsize=(8, 6))
    ax = PyPlot.gca()
    
    # Plot histogram
    PyPlot.hist(data, bins=edges, density=false, alpha=0.75, edgecolor="none", 
                color="#4682B4", label="Histogram")
    
    # Plot KDE curve
    if kde_scaled !== nothing && kde_result !== nothing
        PyPlot.plot(kde_result.x, kde_scaled, color="red", linewidth=2.5, 
                   alpha=0.85, label="KDE curve")
    end
    
    # Format title
    title_text = format_case_title(case_tag)
    PyPlot.title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
    PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
    PyPlot.ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
    
    # Set limits
    PyPlot.xlim(xmin, xmax)
    PyPlot.ylim(0, ymax)
    
    # Add legend
    PyPlot.legend(loc="upper right", fontsize=12, framealpha=0.9)
    
    # Set tick label sizes
    ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
    PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
    
    # Save
    PyPlot.tight_layout()
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ========== Plot multiple cases in one figure ==========
function plot_multiple_cases(cases_data::Vector{Tuple{String, Vector{Float64}}}, filename::AbstractString;
                             nbins::Int=30, kde_bandwidth=nothing)
    ncases = length(cases_data)
    if ncases == 0
        @warn "No cases to plot"
        return
    end
    
    # Calculate global x range from all cases
    all_data = vcat([d[2] for d in cases_data]...)
    xmin_data = minimum(all_data)
    xmax_data = maximum(all_data)
    span = xmax_data - xmin_data
    xmin = xmin_data - PAD * span
    xmax = xmax_data + PAD * span
    
    # Create bin edges (same for all subplots)
    edges = collect(range(xmin, xmax; length=nbins+1))
    bin_width = edges[2] - edges[1]
    
    # Calculate global ymax from all cases
    global_ymax = 0.0
    for (case_tag, data) in cases_data
        if isempty(data)
            continue
        end
        # Histogram max
        fig_temp = PyPlot.figure(figsize=(1,1))
        counts, _ = PyPlot.hist(data, bins=edges, density=false)
        PyPlot.close(fig_temp)
        if length(counts) > 0
            local_ymax = maximum(counts)
            global_ymax = max(global_ymax, local_ymax)
        end
        
        # KDE max
        if length(data) > 1
            try
                kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
                kde_scaled = kde_result.density .* length(data) .* bin_width
                local_ymax_kde = maximum(kde_scaled)
                global_ymax = max(global_ymax, local_ymax_kde)
            catch e
                # Skip if KDE fails
            end
        end
    end
    ymax = global_ymax * 1.1  # Add 10% padding
    
    # Create figure with subplots (2x2 layout)
    fig = PyPlot.figure(figsize=(12, 10))
    PyPlot.suptitle("Distribution of Optimized Injectivities", 
                    fontsize=18, fontweight="bold", y=0.98)
    
    # Adjust subplot spacing
    PyPlot.subplots_adjust(left=0.08, right=0.95, top=0.92, bottom=0.08, 
                           wspace=0.2, hspace=0.3)
    
    for (idx, (case_tag, data)) in enumerate(cases_data)
        ax = PyPlot.subplot(2, 2, idx)
        
        if isempty(data)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", 
                       transform=ax.transAxes, fontsize=FONT_SIZE_LABEL)
        else
            # Plot histogram
            PyPlot.hist(data, bins=edges, density=false, alpha=0.75, edgecolor="none", 
                       color="#4682B4", label="Histogram")
            
            # Plot KDE curve
            if length(data) > 1
                try
                    kde_result = kde_bandwidth === nothing ? kde(data) : kde(data, bandwidth=kde_bandwidth)
                    kde_scaled = kde_result.density .* length(data) .* bin_width
                    PyPlot.plot(kde_result.x, kde_scaled, color="red", linewidth=2.5, 
                               alpha=0.85, label="KDE curve")
                catch e
                    @warn "KDE calculation failed for case $case_tag: $e"
                end
            end
            
            # Format title
            title_text = format_case_title(case_tag)
            PyPlot.title(title_text, fontsize=FONT_SIZE_TITLE, fontweight="bold")
            
            # Set limits (same for all subplots)
            PyPlot.xlim(xmin, xmax)
            PyPlot.ylim(0, ymax)
            
            # Add legend only for first subplot
            if idx == 1
                PyPlot.legend(loc="upper right", fontsize=11, framealpha=0.9)
            end
            
            # Labels only on outer edges
            if idx == 3 || idx == 4
                PyPlot.xlabel("Injectivity (m³/s)", fontsize=FONT_SIZE_LABEL)
            end
            if idx == 1 || idx == 3
                PyPlot.ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
            end
            
            # Set tick label sizes
            ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
            PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
        end
    end
    
    # Save
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ===================== Main =====================
using JLD2

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
    
    # Check if we need to collect from directories
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

# Generate timestamp for filenames
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

# Collect data for all cases
cases_data = Tuple{String, Vector{Float64}}[]

# Collect data for each case
for case_tag in cases_to_plot
    case_data = DataFrame()
    
    if case_tag == "POF_eps=0.05"
        # Find POF case
        case_data = filter(row -> begin
            ct = row.case_tag
            occursin("POF", ct) && (occursin("eps=0.05", ct) || occursin("eps=0.050", ct))
        end, df_ok)
        
        # If not found in CSV, try collecting from directories
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
        
        # If not found in CSV, try collecting from directories
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
        
        # If not found in CSV, try collecting from directories
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
    println("Case $case_tag: $(length(data)) samples")
    
    # Create filename
    safe_case = replace(case_tag, "=" => "_", " " => "_")
    filename = joinpath(OUTDIR, "individual_$(safe_case)_$(ts).png")
    
    # Store data for combined plot
    push!(cases_data, (case_tag, data))
    
    # Plot individual case (optional - uncomment if you want individual plots)
    # plot_single_case(data, case_tag, filename; nbins=NBINS, kde_bandwidth=KDE_BANDWIDTH)
end

# Plot all cases in one figure
if length(cases_data) > 0
    mkpath(OUTDIR)
    combined_filename = joinpath(OUTDIR, "combined_4cases_$(ts).png")
    plot_multiple_cases(cases_data, combined_filename; nbins=NBINS, kde_bandwidth=KDE_BANDWIDTH)
end

println("Done.")
