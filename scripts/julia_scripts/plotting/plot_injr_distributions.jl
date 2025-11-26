#!/usr/bin/env julia
# Panel histograms (frequency) for last_inj_rate by case:
# - One figure for POF (5 cases, split by case)
# - One figure for CVaR (9 cases, split by case)

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames, Dates
using PyPlot

# ===================== Config =====================
const ROOT     = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const USE_LOGX = false       # Set to true if injection rate spans large orders of magnitude (log x-axis)
const NBINS    = 30          # Number of histogram bins
const PAD      = 0.05        # Left/right padding ratio for x-axis (when using linear axis)

# ========== Find latest inj_rate_detail_*.csv ==========
function latest_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && error("Cannot find inj_rate_detail_*.csv, please run collection script first.")
    joinpath(root, sort(files)[end])
end

detail_csv = latest_detail_csv(ROOT)
println("Using detail CSV: ", detail_csv)

# ========== Read data, only use ok_final ==========
df = CSV.read(detail_csv, DataFrame)
df_ok = df[df.status .== "ok_final", :]

# Convert case_tag to String, otherwise startswith broadcasting will error
df_ok.case_tag = String.(df_ok.case_tag)

# ========== Utility: get unique case list by prefix (sorted) ==========
function cases_with_prefix(df::DataFrame, prefix::AbstractString)
    unique(filter!(x -> startswith(x, prefix), unique(df.case_tag))) |> sort
end

cases_pof  = cases_with_prefix(df_ok, "POF")
cases_cvar = cases_with_prefix(df_ok, "CVaR")
println("Found POF cases:  ", cases_pof)
println("Found CVaR cases: ", cases_cvar)

# ========== Utility: collect all values for a group of cases, determine unified bins/xlim ==========
function collect_group_values(df::DataFrame, case_list::Vector{String})
    # 返回：Dict(case_tag => Vector{Float64}), global_xmin, global_xmax
    vals_by_case = Dict{String, Vector{Float64}}()
    global_min = Inf
    global_max = -Inf
    for ct in case_list
        x = collect(skipmissing(df.last_inj_rate[df.case_tag .== ct]))
        vals_by_case[ct] = x
        if !isempty(x)
            local_min = minimum(x)
            local_max = maximum(x)
            global_min = min(global_min, local_min)
            global_max = max(global_max, local_max)
        end
    end
    if global_min == Inf  # No data available
        global_min, global_max = 0.0, 1.0
    end
    return vals_by_case, global_min, global_max
end

# ========== Utility: calculate grid rows/columns (prefer square) ==========
function grid_rc(n::Int)
    r = floor(Int, sqrt(n))
    c = ceil(Int, n / r)
    return r, c
end

# ========== Panel plotting function (frequency) ==========
function plot_case_panels(
        df::DataFrame,
        case_list::Vector{String};
        fig_title::AbstractString,
        filename::AbstractString,
        use_logx::Bool=false,
        nbins::Int=30)

    vals_by_case, xmin, xmax = collect_group_values(df, case_list)

    # Log axis requires positive numbers; linear axis adds slight padding
    if use_logx
        nothing
    else
        if isfinite(xmin) && isfinite(xmax) && xmin != xmax
            span = xmax - xmin
            xmin -= PAD * span
            xmax += PAD * span
        end
    end

    n = length(case_list)
    nrows, ncols = grid_rc(n)
    fig = PyPlot.figure(figsize=(3.8*ncols, 2.8*nrows))
    PyPlot.suptitle(fig_title, fontsize=12)

    # Unified bin edges (linear); log axis left to matplotlib auto-adaptation
    edges = nothing
    if !use_logx && isfinite(xmin) && isfinite(xmax) && xmin != xmax
        edges = collect(range(xmin, xmax; length=nbins+1))
    end

    for (i, ct) in enumerate(case_list)
        ax = PyPlot.subplot(nrows, ncols, i)
        x = vals_by_case[ct]
        if use_logx
            x = filter(>(0.0), x)  # log axis requires positive numbers
        end

        if isempty(x)
            PyPlot.text(0.5, 0.5, "No data", ha="center", va="center", transform=ax.transAxes)
        else
            if use_logx
                PyPlot.hist(x, bins=nbins, density=false, alpha=0.85)  # ⇐ frequency
                PyPlot.xscale("log")
            else
                if edges === nothing
                    PyPlot.hist(x, bins=nbins, density=false, alpha=0.85)  # ⇐ frequency
                else
                    PyPlot.hist(x, bins=edges, density=false, alpha=0.85)  # ⇐ frequency
                end
                if isfinite(xmin) && isfinite(xmax) && xmin != xmax
                    PyPlot.xlim(xmin, xmax)
                end
            end
        end

        PyPlot.title(ct, fontsize=10)
        if i > (nrows-1)*ncols
            PyPlot.xlabel(use_logx ? "last_inj_rate (log)" : "last_inj_rate", fontsize=9)
        end
        if (i-1) % ncols == 0
            PyPlot.ylabel("frequency", fontsize=9)  # frequency
        end
        PyPlot.grid(true, linestyle="--", linewidth=0.4, alpha=0.5)
    end

    PyPlot.tight_layout(rect=[0, 0.0, 1, 0.96])  # Leave space for suptitle
    PyPlot.savefig(filename, dpi=200)
    PyPlot.close(fig)
    println("Saved: ", filename)
end

# ===================== Generate plots =====================
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
out_pof  = joinpath(ROOT, "panel_POF_last_inj_rate_freq_$ts.png")
out_cvar = joinpath(ROOT, "panel_CVaR_last_inj_rate_freq_$ts.png")

plot_case_panels(df_ok, cases_pof;
    fig_title="POF: Histogram of last_inj_rate by case (frequency, ok_final)",
    filename=out_pof,
    use_logx=USE_LOGX,
    nbins=NBINS)

plot_case_panels(df_ok, cases_cvar;
    fig_title="CVaR: Histogram of last_inj_rate by case (frequency, ok_final)",
    filename=out_cvar,
    use_logx=USE_LOGX,
    nbins=NBINS)

println("Done.")
