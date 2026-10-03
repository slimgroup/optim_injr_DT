#!/usr/bin/env julia
# Panel histograms (frequency) for POF: Distribution of optimized injectivities by case

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames, Dates, Printf
using PyPlot
using Statistics

# ==================== CONFIG ====================
const ROOT    = datadir("DT_control", "exp_name=step1")
const OUTDIR  = joinpath(projectdir(), "plots", "DT_control", "exp_name=step1", "statistical_analysis", "kde", "new_runs")
const USE_LOGX = false
const NBINS   = 30
const PAD     = 0.05

# Font sizes (larger for better readability)
const FONT_SIZE_TITLE = 16      # Subplot title
const FONT_SIZE_SUPTITLE = 18   # Main title
const FONT_SIZE_LABEL = 12      # Axis labels
const FONT_SIZE_TICK = 11       # Tick labels
# ================================================

# ========== Find latest detail CSV ==========
function latest_detail_csv(root::String)
    pofs = filter(f -> occursin(r"^pof_inj_rate_detail_\d{8}_\d{6}\.csv$", f), readdir(root))
    if !isempty(pofs)
        by_ts_pofs = s -> DateTime(match(r"(\d{8}_\d{6})", s).captures[1], dateformat"yyyymmdd_HHMMSS")
        return joinpath(root, last(sort(pofs, by=by_ts_pofs)))
    end
    files = filter(f -> occursin(r"^inj_rate_detail_\d{8}_\d{6}\.csv$", f), readdir(root))
    if !isempty(files)
        by_ts_files = s -> DateTime(match(r"(\d{8}_\d{6})", s).captures[1], dateformat"yyyymmdd_HHMMSS")
        return joinpath(root, last(sort(files, by=by_ts_files)))
    end
    allcsv = filter(f -> endswith(f, ".csv") && (occursin("pof_inj_rate_detail_", f) || occursin("inj_rate_detail_", f)), readdir(root))
    @assert !isempty(allcsv) "No detail CSV found under $root"
    return joinpath(root, last(sort(allcsv, by=f -> stat(joinpath(root, f)).mtime)))
end

# ========== Utility: get unique case list by prefix (sorted) ==========
function cases_with_prefix(df::DataFrame, prefix::AbstractString)
    unique(filter!(x -> startswith(x, prefix), unique(df.case_tag))) |> sort
end

# ========== Utility: collect all values for a group of cases, determine unified bins/xlim/ylim ==========
function collect_group_values(df::DataFrame, case_list::Vector{String}, xmin::Float64, xmax::Float64, nbins::Int)
    # Returns: Dict(case_tag => Vector{Float64}), global_ymax
    vals_by_case = Dict{String, Vector{Float64}}()
    global_ymax = 0.0
    
    # Create unified bin edges
    edges = collect(range(xmin, xmax; length=nbins+1))
    
    for ct in case_list
        x = collect(skipmissing(df.last_inj_rate[df.case_tag .== ct]))
        vals_by_case[ct] = x
        if !isempty(x)
            # Calculate histogram counts using a temporary figure
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

# ========== Utility: calculate grid rows/columns (prefer square) ==========
function grid_rc(n::Int)
    r = floor(Int, sqrt(n))
    c = ceil(Int, n / r)
    return r, c
end

# ========== Panel plotting function (frequency, aligned axes) ==========
function plot_pof_panels(
        df::DataFrame,
        case_list::Vector{String};
        filename::AbstractString,
        use_logx::Bool=false,
        nbins::Int=30)

    # First pass: find global xmin and xmax
    global_min = Inf
    global_max = -Inf
    for ct in case_list
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

    # Second pass: collect values and calculate unified ymax
    vals_by_case, ymax, edges = collect_group_values(df, case_list, xmin, xmax, nbins)
    
    # Add padding to ymax for better visualization
    ymax = ymax * 1.1

    n = length(case_list)
    nrows, ncols = grid_rc(n)
    fig = PyPlot.figure(figsize=(3.8*ncols, 2.8*nrows))
    PyPlot.suptitle("PoF: Distribution of Optimized Injectivities",
                    fontsize=FONT_SIZE_SUPTITLE, fontweight="bold", y=0.98)

    for (i, ct) in enumerate(case_list)
        ax = PyPlot.subplot(nrows, ncols, i)
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
                PyPlot.hist(x, bins=edges, density=false, alpha=0.85, edgecolor="none")
                # Set unified x and y limits for alignment
                PyPlot.xlim(xmin, xmax)
                PyPlot.ylim(0, ymax)
            end
        end

        PyPlot.title(ct, fontsize=FONT_SIZE_TITLE, fontweight="bold")
        
        if i > (nrows-1)*ncols
            PyPlot.xlabel(use_logx ? "Injectivity (log scale)" : "Injectivity (m³/s)", 
                         fontsize=FONT_SIZE_LABEL)
        end
        if (i-1) % ncols == 0
            PyPlot.ylabel("Frequency", fontsize=FONT_SIZE_LABEL)
        end
        
        # Set tick label sizes
        ax.tick_params(axis="both", labelsize=FONT_SIZE_TICK)
        PyPlot.grid(true, linestyle="--", linewidth=0.4, alpha=0.5)
    end

    PyPlot.tight_layout(rect=[0, 0.0, 1, 0.96])  # Leave space for suptitle
    PyPlot.savefig(filename, dpi=200, bbox_inches="tight")
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ===================== Main =====================
detail_csv = latest_detail_csv(ROOT)
println("Using detail CSV: ", detail_csv)

# Read data, only use ok_final
df = CSV.read(detail_csv, DataFrame)
df_ok = df[df.status .== "ok_final", :]

# Convert case_tag to String
df_ok.case_tag = String.(df_ok.case_tag)

# Get POF cases
cases_pof = cases_with_prefix(df_ok, "POF")
println("Found POF cases: ", cases_pof)

if isempty(cases_pof)
    error("No POF cases found in the data!")
end

# Generate plot
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
mkpath(OUTDIR)
out_pof = joinpath(OUTDIR, "panel_POF_distribution_optimized_injectivities_$ts.png")

plot_pof_panels(df_ok, cases_pof;
    filename=out_pof,
    use_logx=USE_LOGX,
    nbins=NBINS)

println("Done.")
