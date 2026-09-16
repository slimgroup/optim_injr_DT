#!/usr/bin/env julia
# Generate:
#   1. Split single-panel images (hist / CDF) for PoF eps=0.01 and CVaR g=0.05 a=0.05
#   2. 4×3 histogram grid (bootstrap style)
#   3. 4×3 CDF grid with zoom-in inset (bootstrap style)

using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"

using JLD2, PyPlot, Statistics, Random, StatsBase

# ===================== Config =====================
const ROOT   = datadir("DT_control", "exp_name=step1")
const OUTDIR = joinpath(projectdir(), "plots", "DT_control", "exp_name=step1", "statistical_analysis", "ecdf")
const B_SINGLE = 10000   # bootstrap resamples for single plots
const B_GRID   = 10000   # bootstrap resamples for grid plots
const CONF     = 0.95
const THRESH   = 0.01    # 1% fracture probability
const NBINS    = 30
const SEED     = 42
const ECDF_PTS = 1500    # grid points for ECDF evaluation
const FORWARD_STEP = 2
const INJ_START    = 0.0001

# 4×3 parameter grid: 4 rows × 3 columns
const GRID = [
    # Row 1: PoF
    ("POF__HARD__eps=0.0__",               "PoF ε=0.0"),
    ("POF__HARD__eps=0.01__",              "PoF ε=0.01"),
    ("POF__HARD__eps=0.05__",              "PoF ε=0.05"),
    # Row 2: CVaR γ=0.0
    ("CVaR__HARD__alpha=0.0__gamma=0.0__",   "CVaR γ=0.0 α=0.0"),
    ("CVaR__HARD__alpha=0.01__gamma=0.0__",  "CVaR γ=0.0 α=0.01"),
    ("CVaR__HARD__alpha=0.05__gamma=0.0__",  "CVaR γ=0.0 α=0.05"),
    # Row 3: CVaR γ=0.1
    ("CVaR__HARD__alpha=0.0__gamma=0.1__",   "CVaR γ=0.1 α=0.0"),
    ("CVaR__HARD__alpha=0.01__gamma=0.1__",  "CVaR γ=0.1 α=0.01"),
    ("CVaR__HARD__alpha=0.05__gamma=0.1__",  "CVaR γ=0.1 α=0.05"),
    # Row 4: CVaR γ=0.2
    ("CVaR__HARD__alpha=0.0__gamma=0.2__",   "CVaR γ=0.2 α=0.0"),
    ("CVaR__HARD__alpha=0.01__gamma=0.2__",  "CVaR γ=0.2 α=0.01"),
    ("CVaR__HARD__alpha=0.05__gamma=0.2__",  "CVaR γ=0.2 α=0.05"),
]

const SELECTED_GRID = [
    ("PoF ε=0.0", "PoF ε=0.0\n(identical to CVaR γ=0.0)"),
    ("PoF ε=0.01", "PoF ε=0.01"),
    ("CVaR γ=0.1 α=0.01", "CVaR γ=0.1 α=0.01"),
]

# ===================== Data loading =====================
function last_nonzero_inj_rate(data; init_rate::Float64=1e-4,
                               inj_start::Float64=INJ_START,
                               forward_step::Int=FORWARD_STEP)
    raw = get(data, "inj_rate_arr", nothing)
    raw === nothing && return init_rate
    col1 = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    idx === nothing && return init_rate
    endpoint = clean[idx]
    ramp = collect(range(inj_start, endpoint, forward_step * 6))
    return length(ramp) >= 6 ? ramp[6] : endpoint
end

"""
`inj_rate_arr[end, 6]` (last row, column 6). **Not** the same scalar as the bootstrap CDFs in this script.

The empirical CDF / histogram pipeline (`collect_data` default) uses `last_nonzero_inj_rate`, which takes
the last nonzero value along **column 1**, builds `range(inj_start, endpoint, forward_step*6)`, and returns
`ramp[6]`. That matches the ramp discretization used with `forward_step` in `optim_inject.jl`. For many runs,
column 6 of the final row stays near `inj_start`, so `raw[end,6]` is ~constant → degenerate empty-looking CDF.
"""
function inj_rate_arr_index6(data; init_rate::Float64=1e-4)
    raw = get(data, "inj_rate_arr", nothing)
    raw === nothing && return init_rate
    if ndims(raw) == 2
        _, nc = size(raw)
        nc < 6 && return init_rate
        v = raw[end, 6]
        (ismissing(v) || !isfinite(v)) && return init_rate
        return Float64(v)
    end
    col = ndims(raw) == 1 ? collect(raw) : vec(raw)
    length(col) < 6 && return init_rate
    v = col[6]
    (ismissing(v) || !isfinite(v)) && return init_rate
    return Float64(v)
end

function collect_data(root, pat; extractor=last_nonzero_inj_rate)
    dirs = filter(d -> isdir(joinpath(root, d)) && occursin(pat, d), readdir(root))
    rates = Float64[]
    for dn in dirs, s in 1:128
        fp = joinpath(root, dn, "sample=$(s)", "final.jld2")
        isfile(fp) || continue
        try push!(rates, extractor(load(fp))) catch; end
    end
    rates
end

# ===================== Bootstrap (optimised) =====================
function boot_quantile(data, q, B; seed=SEED)
    rng = MersenneTwister(seed); n = length(data)
    [quantile(data[rand(rng, 1:n, n)], q) for _ in 1:B]
end

function boot_ecdf_ci(data, B; conf=CONF, npts=ECDF_PTS, seed=SEED)
    rng = MersenneTwister(seed); n = length(data)
    xmin, xmax = extrema(data); margin = 0.05*(xmax-xmin)
    xg = collect(range(xmin-margin, xmax+margin, length=npts))
    ecdf_at(sorted, xg) = [searchsortedfirst(sorted, x)-1 for x in xg] ./ length(sorted)
    orig = ecdf_at(sort(data), xg)
    boot = zeros(B, npts)
    for b in 1:B
        boot[b,:] .= ecdf_at(sort(data[rand(rng,1:n,n)]), xg)
    end
    α = 1-conf
    lo = [quantile(view(boot,:,i), α/2) for i in 1:npts]
    hi = [quantile(view(boot,:,i), 1-α/2) for i in 1:npts]
    xg, orig, lo, hi
end

function threshold_crossing(xg, cdf, thr)
    idx = findfirst(v -> v >= thr, cdf)
    idx !== nothing ? xg[idx] : nothing
end

# Struct to hold all precomputed results for one case
struct CaseResult
    title::String
    data::Vector{Float64}
    n::Int
    q_val::Float64; ci_lo_q::Float64; ci_hi_q::Float64
    boot_q::Vector{Float64}
    xg::Vector{Float64}; ecdf_v::Vector{Float64}; ci_lo::Vector{Float64}; ci_hi::Vector{Float64}
    x_conservative::Union{Nothing,Float64}; x_ecdf::Union{Nothing,Float64}; x_optimistic::Union{Nothing,Float64}
end

retitle_case(cr::CaseResult, new_title::String) = CaseResult(
    new_title, cr.data, cr.n, cr.q_val, cr.ci_lo_q, cr.ci_hi_q, cr.boot_q,
    cr.xg, cr.ecdf_v, cr.ci_lo, cr.ci_hi, cr.x_conservative, cr.x_ecdf, cr.x_optimistic
)

function select_cases(results::Vector{CaseResult}, specs)
    selected = CaseResult[]
    for (src_title, display_title) in specs
        idx = findfirst(cr -> cr.title == src_title, results)
        idx === nothing && error("Selected case not found: $src_title")
        push!(selected, retitle_case(results[idx], display_title))
    end
    return selected
end

function compute_case(data, title; B=B_SINGLE)
    n = length(data); q = THRESH
    bq = boot_quantile(data, q, B)
    q_val = quantile(data, q)
    ci_lo_q = quantile(bq, (1-CONF)/2)
    ci_hi_q = quantile(bq, 1-(1-CONF)/2)
    xg, ev, clo, chi = boot_ecdf_ci(data, B)
    xcons = threshold_crossing(xg, chi, THRESH)
    xecdf = threshold_crossing(xg, ev, THRESH)
    xopt  = threshold_crossing(xg, clo, THRESH)
    CaseResult(title, data, n, q_val, ci_lo_q, ci_hi_q, bq,
               xg, ev, clo, chi, xcons, xecdf, xopt)
end

# ===================== Single-panel: Histogram =====================
function plot_single_hist(cr::CaseResult, fname; nbins=NBINS)
    fig = PyPlot.figure(figsize=(8, 6))
    ax = fig.add_subplot(111)
    edges = collect(range(minimum(cr.data), maximum(cr.data), length=nbins+1))
    ax.hist(cr.data, bins=edges, density=false, alpha=0.7, color="#6BAED6",
            edgecolor="#2171B5", linewidth=0.5, label="Histogram (M=$(cr.n))", zorder=2)
    ax.axvline(x=cr.q_val, color="#2CA02C", lw=2, ls="-",
              label="1% quantile: $(round(cr.q_val,digits=5))", zorder=3)
    if cr.x_conservative !== nothing
        ax.axvline(x=cr.x_conservative, color="#D62728", lw=2.5, ls="--",
                  label="\$q_k^{\\star}\$: $(round(cr.x_conservative,digits=5))", zorder=4)
    end
    ax.legend(loc="upper right", fontsize=13, framealpha=0.9)
    st = "M=$(cr.n)  mean=$(round(mean(cr.data),digits=4))  std=$(round(std(cr.data),digits=4))\nmin=$(round(minimum(cr.data),digits=4))  max=$(round(maximum(cr.data),digits=4))"
    ax.text(0.97, 0.62, st, transform=ax.transAxes, fontsize=12, va="top", ha="right",
            bbox=Dict("boxstyle"=>"round,pad=0.3","facecolor"=>"lightyellow","edgecolor"=>"gray","alpha"=>0.9))
    ax.set_xlabel("Injection Rate (m³/s)", fontsize=14)
    ax.set_ylabel("Count", fontsize=14)
    ax.set_title("$(cr.title) — Injection Rate Distribution", fontsize=16, fontweight="bold")
    ax.tick_params(labelsize=12)
    ax.grid(true, ls="--", lw=0.3, alpha=0.5)
    PyPlot.tight_layout()
    PyPlot.savefig(fname, dpi=200, bbox_inches="tight"); PyPlot.close(fig)
    println("  Saved: $fname")
end

# ===================== Single-panel: CDF with zoom inset =====================
function plot_single_cdf(cr::CaseResult, fname)
    fig = PyPlot.figure(figsize=(8, 6))
    ax = fig.add_subplot(111)
    ax.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5,
                   label="95% Bootstrap CI")
    ax.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=2, label="Empirical CDF")
    ax.axhline(y=THRESH*100, color="#D62728", lw=1.5, ls="--", label="Target p = 1%")
    for (xv, col, ms) in [(cr.x_conservative,"#FF6F00",10),(cr.x_ecdf,"#2E7D32",10),(cr.x_optimistic,"#1565C0",10)]
        xv !== nothing && ax.plot(xv, THRESH*100, "*", color=col, markersize=ms, zorder=5)
    end
    ax.set_xlabel("Injection Rate (m³/s)", fontsize=14); ax.set_ylabel("Violation probability (%)", fontsize=14)
    case_label = cr.title == "PoF (eps=0.01)" ? "PoF eps = 0.01" : cr.title
    ax.set_title("Optimized-endpoint ECDF — $(case_label)", fontsize=16, fontweight="bold")
    ax.set_ylim(0,100)
    ax.tick_params(labelsize=12); ax.grid(true, ls="--", lw=0.3, alpha=0.5)
    ins = ax.inset_axes([0.38, 0.12, 0.57, 0.50])
    ins.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5)
    ins.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=1.5)
    ins.axhline(y=THRESH*100, color="#D62728", lw=1, ls="--")
    zpts = filter(!isnothing, [cr.x_conservative, cr.x_ecdf, cr.x_optimistic])
    if !isempty(zpts); zxmin=minimum(zpts)*0.85; zxmax=maximum(zpts)*1.15; else; zxmin=minimum(cr.data); zxmax=zxmin+0.1; end
    zymax = THRESH*100*8
    afs = 10
    if cr.x_conservative !== nothing
        ins.plot(cr.x_conservative, THRESH*100, "*", color="#FF6F00", ms=12, zorder=5)
        ins.annotate("\$q_k^{\\star}\$\n$(round(cr.x_conservative,digits=4))", xy=(cr.x_conservative,THRESH*100),
                    xytext=(-35,18), textcoords="offset points", fontsize=afs, color="#E65100", fontweight="bold", ha="center",
                    bbox=Dict("boxstyle"=>"round,pad=0.2","facecolor"=>"#FFF3E0","alpha"=>0.9,"edgecolor"=>"#FF6F00"),
                    arrowprops=Dict("arrowstyle"=>"->","color"=>"#FF6F00",
                                     "linewidth"=>1.5,"mutation_scale"=>14,"shrinkB"=>7))
    end
    if cr.x_ecdf !== nothing
        ins.plot(cr.x_ecdf, THRESH*100, "*", color="#2E7D32", ms=12, zorder=5)
        ins.annotate("ECDF\n$(round(cr.x_ecdf,digits=4))", xy=(cr.x_ecdf,THRESH*100),
                    xytext=(0,45), textcoords="offset points", fontsize=afs, color="#1B5E20", fontweight="bold", ha="center",
                    bbox=Dict("boxstyle"=>"round,pad=0.2","facecolor"=>"#E8F5E9","alpha"=>0.9,"edgecolor"=>"#2E7D32"),
                    arrowprops=Dict("arrowstyle"=>"->","color"=>"#2E7D32",
                                     "linewidth"=>1.5,"mutation_scale"=>14,"shrinkB"=>7))
    end
    if cr.x_optimistic !== nothing
        ins.plot(cr.x_optimistic, THRESH*100, "*", color="#1565C0", ms=12, zorder=5)
        ins.annotate("Optimistic\n$(round(cr.x_optimistic,digits=4))", xy=(cr.x_optimistic,THRESH*100),
                    xytext=(35,18), textcoords="offset points", fontsize=afs, color="#0D47A1", fontweight="bold", ha="center",
                    bbox=Dict("boxstyle"=>"round,pad=0.2","facecolor"=>"#E3F2FD","alpha"=>0.9,"edgecolor"=>"#1565C0"),
                    arrowprops=Dict("arrowstyle"=>"->","color"=>"#1565C0",
                                     "linewidth"=>1.5,"mutation_scale"=>14,"shrinkB"=>7))
    end
    ins.set_xlim(zxmin, zxmax); ins.set_ylim(0, zymax)
    ins.set_title("Left tail zoom (0-$(Int(zymax))%)", fontsize=10)
    ins.set_xlabel("Injection Rate (m³/s)", fontsize=9); ins.set_ylabel("Violation probability (%)", fontsize=9)
    ins.tick_params(labelsize=9); ins.grid(true, ls="--", lw=0.3, alpha=0.4)
    # Main axis limits from data (avoids pathological bbox_inches with indicate_inset_zoom on some backends)
    xdmin, xdmax = extrema(cr.data)
    xspan = max(xdmax - xdmin, 1e-12)
    ax.set_xlim(xdmin - 0.05 * xspan, xdmax + 0.05 * xspan)
    # Show exactly which main-axis region is enlarged in the inset. Both ends
    # stay inside the fixed axes limits, avoiding unbounded tight-export bounds.
    zoom_box = matplotlib.patches.Rectangle((zxmin, 0), zxmax-zxmin, zymax,
                    fill=false, edgecolor="#555555", linewidth=1.3, zorder=4)
    ax.add_patch(zoom_box)
    zoom_arrow = matplotlib.patches.ConnectionPatch(
        xyA=(zxmax, 0), coordsA=ax.transData,
        xyB=(0.10, 0), coordsB=ins.transAxes,
        arrowstyle="-|>", mutation_scale=16, linewidth=1.5,
        color="#555555", shrinkA=2, shrinkB=5, zorder=6)
    fig.add_artist(zoom_arrow)
    PyPlot.tight_layout()
    # Keep the plotting area fixed; put the legend/title above it and B below it.
    ax.set_title("Optimized-endpoint ECDF — $(case_label)", fontsize=16,
                 fontweight="bold", y=1.085)
    ax.legend(loc="lower center", bbox_to_anchor=(0.5, 1.01), ncol=3,
              fontsize=12, frameon=false, borderaxespad=0,
              columnspacing=1.3, handletextpad=0.6)
    fig.text(0.02, -0.015, "Endpoint ECDF uses ≤; strict violation uses <.",
             ha="left", va="top", fontsize=8.5, color="#444444")
    fig.text(0.98, -0.015, "Bootstrap resamples: B = $(length(cr.boot_q))",
             ha="right", va="top", fontsize=10, color="#444444")
    PyPlot.savefig(fname, dpi=200, bbox_inches="tight", pad_inches=0.15); PyPlot.close(fig)
    println("  Saved: $fname")
end

# ===================== 4×3 Grid: Histogram =====================
function plot_grid_histogram(results::Vector{CaseResult}, fname; nbins=NBINS)
    nrows, ncols = 4, 3
    fig, axes = PyPlot.subplots(nrows, ncols, figsize=(15, 14))
    PyPlot.suptitle("Distribution of Optimized Injectivities: Histogram (M=128)",
                    fontsize=22, fontweight="bold", y=1.01)
    PyPlot.subplots_adjust(hspace=0.22, wspace=0.12, top=0.94, bottom=0.05, left=0.06, right=0.98)
    global_xmin = minimum(minimum(cr.data) for cr in results)
    global_xmax = maximum(maximum(cr.data) for cr in results)
    xpad = 0.03 * (global_xmax - global_xmin)
    global_edges = collect(range(global_xmin, global_xmax, length=nbins+1))
    for idx in 1:length(results)
        cr = results[idx]
        r = div(idx-1, ncols) + 1; c = mod(idx-1, ncols) + 1
        ax = axes[r, c]
        ax.hist(cr.data, bins=global_edges, density=false, alpha=0.7, color="#6BAED6",
                edgecolor="#2171B5", lw=0.5, label="Histogram (M=$(cr.n))", zorder=2)
        ax.axvline(x=cr.q_val, color="#2CA02C", lw=1.8, ls="-",
                  label="1% quantile: $(round(cr.q_val,digits=4))", zorder=3)
        if cr.x_conservative !== nothing
            ax.axvline(x=cr.x_conservative, color="#D62728", lw=2.5, ls="--",
                      label="\$q_k^{\\star}\$: $(round(cr.x_conservative,digits=4))", zorder=4)
        end
        ax.set_xlim(global_xmin - xpad, global_xmax + xpad)
        ax.set_title("$(cr.title)", fontsize=16, fontweight="bold")
        ax.tick_params(labelsize=13)
        ax.grid(true, ls="--", lw=0.3, alpha=0.4)
        ax.legend(loc="upper right", fontsize=12, framealpha=0.9)
        st = "mean=$(round(mean(cr.data),digits=4))  std=$(round(std(cr.data),digits=4))\nmin=$(round(minimum(cr.data),digits=4))  max=$(round(maximum(cr.data),digits=4))"
        ax.text(0.97, 0.48, st, transform=ax.transAxes, fontsize=11, va="top", ha="right",
                bbox=Dict("boxstyle"=>"round,pad=0.3","facecolor"=>"lightyellow","edgecolor"=>"gray","alpha"=>0.9))
        if r == nrows; ax.set_xlabel("Injection Rate (m³/s)", fontsize=15); end
        if c == 1; ax.set_ylabel("Count", fontsize=15); end
    end
    PyPlot.savefig(fname, dpi=200, bbox_inches="tight"); PyPlot.close(fig)
    println("Saved grid histogram: $fname")
end

# ===================== 4×3 Grid: CDF with zoom inset =====================
function plot_grid_cdf(results::Vector{CaseResult}, fname)
    nrows, ncols = 4, 3
    fig, axes = PyPlot.subplots(nrows, ncols, figsize=(15, 13))
    PyPlot.suptitle("Optimized-endpoint ECDFs\nB = $(B_GRID); Opt. = Optimistic",
                    fontsize=22, fontweight="bold", y=1.01)
    PyPlot.subplots_adjust(hspace=0.20, wspace=0.12, top=0.94, bottom=0.05, left=0.06, right=0.98)
    global_xmin = minimum(minimum(cr.data) for cr in results)
    global_xmax = maximum(maximum(cr.data) for cr in results)
    xpad = 0.03 * (global_xmax - global_xmin)
    all_zpts = Float64[]
    for cr in results
        for xv in [cr.x_conservative, cr.x_ecdf, cr.x_optimistic]
            xv !== nothing && push!(all_zpts, xv)
        end
    end
    global_zxmin = minimum(all_zpts) * 0.75
    global_zxmax = maximum(all_zpts) * 1.25
    zymax = THRESH * 100 * 8
    for idx in 1:length(results)
        cr = results[idx]
        r = div(idx-1, ncols) + 1; c = mod(idx-1, ncols) + 1
        ax = axes[r, c]
        ax.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5, zorder=1)
        ax.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=1.8, zorder=2)
        ax.axhline(y=THRESH*100, color="#D62728", lw=1.2, ls="--", zorder=3)
        for (xv, col) in [(cr.x_conservative,"#FF6F00"),(cr.x_ecdf,"#2E7D32"),(cr.x_optimistic,"#1565C0")]
            xv !== nothing && ax.plot(xv, THRESH*100, "*", color=col, ms=8, zorder=5)
        end
        ax.set_title("$(cr.title)", fontsize=15, fontweight="bold")
        ax.set_xlim(global_xmin - xpad, global_xmax + xpad)
        ax.set_ylim(0, 100); ax.tick_params(labelsize=13)
        ax.grid(true, ls="--", lw=0.3, alpha=0.4)
        if r == nrows; ax.set_xlabel("Injection Rate (m³/s)", fontsize=14); end
        if c == 1; ax.set_ylabel("Violation probability (%)", fontsize=12); end
        ins = ax.inset_axes([0.40, 0.10, 0.55, 0.45])
        ins.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5)
        ins.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=1.2)
        ins.axhline(y=THRESH*100, color="#D62728", lw=0.8, ls="--")
        afs = 9
        if cr.x_conservative !== nothing
            ins.plot(cr.x_conservative, THRESH*100, "*", color="#FF6F00", ms=10, zorder=5)
            ins.annotate("\$q_k^{\\star}\$\n$(round(cr.x_conservative,digits=4))", xy=(cr.x_conservative,THRESH*100),
                        xytext=(-28,18), textcoords="offset points", fontsize=afs, color="#E65100", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#FFF3E0","alpha"=>0.9,"edgecolor"=>"#FF6F00"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#FF6F00"))
        end
        if cr.x_ecdf !== nothing
            ins.plot(cr.x_ecdf, THRESH*100, "*", color="#2E7D32", ms=10, zorder=5)
            ins.annotate("ECDF\n$(round(cr.x_ecdf,digits=4))", xy=(cr.x_ecdf,THRESH*100),
                        xytext=(0,38), textcoords="offset points", fontsize=afs, color="#1B5E20", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#E8F5E9","alpha"=>0.9,"edgecolor"=>"#2E7D32"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#2E7D32"))
        end
        if cr.x_optimistic !== nothing
            ins.plot(cr.x_optimistic, THRESH*100, "*", color="#1565C0", ms=10, zorder=5)
            ins.annotate("Opt.\n$(round(cr.x_optimistic,digits=4))", xy=(cr.x_optimistic,THRESH*100),
                        xytext=(28,18), textcoords="offset points", fontsize=afs, color="#0D47A1", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#E3F2FD","alpha"=>0.9,"edgecolor"=>"#1565C0"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#1565C0"))
        end
        ins.set_xlim(global_zxmin, global_zxmax); ins.set_ylim(0, zymax)
        ins.set_title("Zoom (0-$(Int(zymax))%)", fontsize=10)
        ins.tick_params(labelsize=9)
        ins.grid(true, ls="--", lw=0.2, alpha=0.4)
        ax.indicate_inset_zoom(ins, edgecolor="gray", alpha=0.4)
    end
    ax1 = axes[1,1]
    ax1.fill_between([], [], [], color="#BBDEFB", alpha=0.5, label="95% Bootstrap CI")
    ax1.plot([], [], color="#1565C0", lw=1.8, label="Empirical CDF")
    ax1.plot([], [], color="#D62728", lw=1.2, ls="--", label="Target p = 1%")
    ax1.legend(loc="upper left", fontsize=12, framealpha=0.9)
    PyPlot.savefig(fname, dpi=200, bbox_inches="tight"); PyPlot.close(fig)
    println("Saved grid CDF: $fname")
end

# ===================== Selected 1×3 Histogram =====================
function plot_selected_histogram(results::Vector{CaseResult}, fname; nbins=NBINS)
    fig = PyPlot.figure(figsize=(16, 5.2))
    PyPlot.suptitle("Distribution of Optimized Injectivities: Histogram (M=128)",
                    fontsize=20, fontweight="bold", y=1.02)
    PyPlot.subplots_adjust(wspace=0.14, top=0.86, bottom=0.15, left=0.06, right=0.98)
    global_xmin = minimum(minimum(cr.data) for cr in results)
    global_xmax = maximum(maximum(cr.data) for cr in results)
    xpad = 0.03 * (global_xmax - global_xmin)
    global_edges = collect(range(global_xmin, global_xmax, length=nbins+1))
    for (idx, cr) in enumerate(results)
        ax = fig.add_subplot(1, 3, idx)
        ax.hist(cr.data, bins=global_edges, density=false, alpha=0.7, color="#6BAED6",
                edgecolor="#2171B5", lw=0.5, label="Histogram (M=$(cr.n))", zorder=2)
        ax.axvline(x=cr.q_val, color="#2CA02C", lw=1.8, ls="-",
                  label="1% quantile: $(round(cr.q_val,digits=4))", zorder=3)
        if cr.x_conservative !== nothing
            ax.axvline(x=cr.x_conservative, color="#D62728", lw=2.5, ls="--",
                      label="\$q_k^{\\star}\$: $(round(cr.x_conservative,digits=4))", zorder=4)
        end
        ax.set_xlim(global_xmin - xpad, global_xmax + xpad)
        ax.set_title("$(cr.title)", fontsize=15, fontweight="bold")
        ax.tick_params(labelsize=12)
        ax.grid(true, ls="--", lw=0.3, alpha=0.4)
        ax.legend(loc="upper right", fontsize=11, framealpha=0.9)
        st = "mean=$(round(mean(cr.data),digits=4))  std=$(round(std(cr.data),digits=4))\nmin=$(round(minimum(cr.data),digits=4))  max=$(round(maximum(cr.data),digits=4))"
        ax.text(0.97, 0.48, st, transform=ax.transAxes, fontsize=10.5, va="top", ha="right",
                bbox=Dict("boxstyle"=>"round,pad=0.3","facecolor"=>"lightyellow","edgecolor"=>"gray","alpha"=>0.9))
        ax.set_xlabel("Injection Rate (m³/s)", fontsize=14)
        if idx == 1
            ax.set_ylabel("Count", fontsize=14)
        end
    end
    PyPlot.savefig(fname, dpi=220, bbox_inches="tight"); PyPlot.close(fig)
    println("Saved selected histogram: $fname")
end

# ===================== Selected 1×3 CDF =====================
function plot_selected_cdf(results::Vector{CaseResult}, fname)
    fig = PyPlot.figure(figsize=(16, 5.2))
    PyPlot.suptitle("Optimized-endpoint ECDFs\nB = $(B_GRID); Opt. = Optimistic",
                    fontsize=20, fontweight="bold", y=1.04)
    PyPlot.subplots_adjust(wspace=0.14, top=0.86, bottom=0.15, left=0.06, right=0.98)
    global_xmin = minimum(minimum(cr.data) for cr in results)
    global_xmax = maximum(maximum(cr.data) for cr in results)
    xpad = 0.03 * (global_xmax - global_xmin)
    all_zpts = Float64[]
    for cr in results
        for xv in [cr.x_conservative, cr.x_ecdf, cr.x_optimistic]
            xv !== nothing && push!(all_zpts, xv)
        end
    end
    global_zxmin = minimum(all_zpts) * 0.75
    global_zxmax = maximum(all_zpts) * 1.25
    zymax = THRESH * 100 * 8
    for (idx, cr) in enumerate(results)
        ax = fig.add_subplot(1, 3, idx)
        ax.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5, zorder=1)
        ax.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=1.8, zorder=2)
        ax.axhline(y=THRESH*100, color="#D62728", lw=1.2, ls="--", zorder=3)
        for (xv, col) in [(cr.x_conservative,"#FF6F00"),(cr.x_ecdf,"#2E7D32"),(cr.x_optimistic,"#1565C0")]
            xv !== nothing && ax.plot(xv, THRESH*100, "*", color=col, ms=8, zorder=5)
        end
        ax.set_title("$(cr.title)", fontsize=14, fontweight="bold")
        ax.set_xlim(global_xmin - xpad, global_xmax + xpad)
        ax.set_ylim(0, 100)
        ax.tick_params(labelsize=12)
        ax.grid(true, ls="--", lw=0.3, alpha=0.4)
        ax.set_xlabel("Injection Rate (m³/s)", fontsize=14)
        if idx == 1
            ax.set_ylabel("Violation probability (%)", fontsize=14)
        end
        ins = ax.inset_axes([0.40, 0.10, 0.55, 0.45])
        ins.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5)
        ins.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=1.2)
        ins.axhline(y=THRESH*100, color="#D62728", lw=0.8, ls="--")
        afs = 9
        if cr.x_conservative !== nothing
            ins.plot(cr.x_conservative, THRESH*100, "*", color="#FF6F00", ms=10, zorder=5)
            ins.annotate("\$q_k^{\\star}\$\n$(round(cr.x_conservative,digits=4))", xy=(cr.x_conservative,THRESH*100),
                        xytext=(-28,18), textcoords="offset points", fontsize=afs, color="#E65100", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#FFF3E0","alpha"=>0.9,"edgecolor"=>"#FF6F00"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#FF6F00"))
        end
        if cr.x_ecdf !== nothing
            ins.plot(cr.x_ecdf, THRESH*100, "*", color="#2E7D32", ms=10, zorder=5)
            ins.annotate("ECDF\n$(round(cr.x_ecdf,digits=4))", xy=(cr.x_ecdf,THRESH*100),
                        xytext=(0,38), textcoords="offset points", fontsize=afs, color="#1B5E20", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#E8F5E9","alpha"=>0.9,"edgecolor"=>"#2E7D32"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#2E7D32"))
        end
        if cr.x_optimistic !== nothing
            ins.plot(cr.x_optimistic, THRESH*100, "*", color="#1565C0", ms=10, zorder=5)
            ins.annotate("Opt.\n$(round(cr.x_optimistic,digits=4))", xy=(cr.x_optimistic,THRESH*100),
                        xytext=(28,18), textcoords="offset points", fontsize=afs, color="#0D47A1", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#E3F2FD","alpha"=>0.9,"edgecolor"=>"#1565C0"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#1565C0"))
        end
        ins.set_xlim(global_zxmin, global_zxmax); ins.set_ylim(0, zymax)
        ins.set_title("Zoom (0-$(Int(zymax))%)", fontsize=9.5)
        ins.tick_params(labelsize=8.5)
        ins.grid(true, ls="--", lw=0.2, alpha=0.4)
        ax.indicate_inset_zoom(ins, edgecolor="gray", alpha=0.4)
    end
    ax1 = fig.axes[1]
    ax1.fill_between([], [], [], color="#BBDEFB", alpha=0.5, label="95% Bootstrap CI")
    ax1.plot([], [], color="#1565C0", lw=1.8, label="Empirical CDF")
    ax1.plot([], [], color="#D62728", lw=1.2, ls="--", label="Target p = 1%")
    ax1.legend(loc="upper left", fontsize=11, framealpha=0.9)
    PyPlot.savefig(fname, dpi=220, bbox_inches="tight"); PyPlot.close(fig)
    println("Saved selected CDF: $fname")
end

# ===================== 4×3 Grid: CDF Zoom (standalone) =====================
function plot_grid_cdf_zoom(results::Vector{CaseResult}, fname)
    nrows, ncols = 4, 3
    fig, axes = PyPlot.subplots(nrows, ncols, figsize=(15, 13))
    PyPlot.suptitle("CDF Zoom at $(Int(THRESH*100))% Fracture Threshold with Bootstrap CI\n(B=$(B_GRID), $(Int(CONF*100))% CI)",
                    fontsize=22, fontweight="bold", y=1.01)
    PyPlot.subplots_adjust(hspace=0.20, wspace=0.12, top=0.94, bottom=0.05, left=0.06, right=0.98)
    all_zpts = Float64[]
    for cr in results
        for xv in [cr.x_conservative, cr.x_ecdf, cr.x_optimistic]
            xv !== nothing && push!(all_zpts, xv)
        end
    end
    global_zxmin = minimum(all_zpts) * 0.75
    global_zxmax = maximum(all_zpts) * 1.25
    zymax = THRESH * 100 * 10
    for idx in 1:length(results)
        cr = results[idx]
        r = div(idx-1, ncols) + 1; c = mod(idx-1, ncols) + 1
        ax = axes[r, c]
        ax.fill_between(cr.xg, cr.ci_lo.*100, cr.ci_hi.*100, color="#BBDEFB", alpha=0.5, zorder=1)
        ax.plot(cr.xg, cr.ecdf_v.*100, color="#1565C0", lw=2, zorder=2)
        ax.axhline(y=THRESH*100, color="#D62728", lw=1.2, ls="--", zorder=3)
        afs = 10
        zpts_all = filter(!isnothing, [cr.x_conservative, cr.x_ecdf, cr.x_optimistic])
        spread = length(zpts_all) >= 2 ? (maximum(zpts_all) - minimum(zpts_all)) / (global_zxmax - global_zxmin) : 0.5
        tight = spread < 0.15
        y_lo = tight ? 8 : 12; y_hi = tight ? 50 : 42
        x_off = tight ? -35 : -28
        if cr.x_conservative !== nothing
            ax.plot(cr.x_conservative, THRESH*100, "*", color="#FF6F00", ms=12, zorder=5)
            ax.annotate("\$q_k^{\\star}\$\n$(round(cr.x_conservative,digits=4))", xy=(cr.x_conservative,THRESH*100),
                        xytext=(x_off, y_lo), textcoords="offset points", fontsize=afs, color="#E65100", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#FFF3E0","alpha"=>0.9,"edgecolor"=>"#FF6F00"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#FF6F00"))
        end
        if cr.x_ecdf !== nothing
            ax.plot(cr.x_ecdf, THRESH*100, "*", color="#2E7D32", ms=12, zorder=5)
            ax.annotate("ECDF\n$(round(cr.x_ecdf,digits=4))", xy=(cr.x_ecdf,THRESH*100),
                        xytext=(0, y_hi), textcoords="offset points", fontsize=afs, color="#1B5E20", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#E8F5E9","alpha"=>0.9,"edgecolor"=>"#2E7D32"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#2E7D32"))
        end
        if cr.x_optimistic !== nothing
            ax.plot(cr.x_optimistic, THRESH*100, "*", color="#1565C0", ms=12, zorder=5)
            ax.annotate("Opt.\n$(round(cr.x_optimistic,digits=4))", xy=(cr.x_optimistic,THRESH*100),
                        xytext=(-x_off, y_lo), textcoords="offset points", fontsize=afs, color="#0D47A1", fontweight="bold", ha="center",
                        bbox=Dict("boxstyle"=>"round,pad=0.12","facecolor"=>"#E3F2FD","alpha"=>0.9,"edgecolor"=>"#1565C0"),
                        arrowprops=Dict("arrowstyle"=>"->","color"=>"#1565C0"))
        end
        ax.set_xlim(global_zxmin, global_zxmax); ax.set_ylim(0, zymax)
        ax.set_title("$(cr.title)", fontsize=15, fontweight="bold")
        ax.tick_params(labelsize=13)
        ax.grid(true, ls="--", lw=0.3, alpha=0.4)
        if r == nrows; ax.set_xlabel("Injection Rate (m³/s)", fontsize=14); end
        if c == 1; ax.set_ylabel("Fracture Prob. (%)", fontsize=14); end
    end
    ax1 = axes[1,1]
    ax1.fill_between([], [], [], color="#BBDEFB", alpha=0.5, label="95% Bootstrap CI")
    ax1.plot([], [], color="#1565C0", lw=2, label="Empirical CDF")
    ax1.plot([], [], color="#D62728", lw=1.2, ls="--", label="$(Int(THRESH*100))% Fracture Prob.")
    ax1.legend(loc="upper left", fontsize=12, framealpha=0.9)
    PyPlot.savefig(fname, dpi=200, bbox_inches="tight"); PyPlot.close(fig)
    println("Saved grid CDF zoom: $fname")
end

# ===================== Main =====================
"""
CDF + hist for PoF ε=0 and CVaR γ=0.1 α=0.01 — **same scalar definition as** `run_part1_only!` / `cdf_POF_eps0.01.png`:
`last_nonzero_inj_rate` (ramp 6th step from col-1 endpoint), not `inj_rate_arr[end, 6]`.
"""
function run_part1b_inj6!(; root=ROOT, outdir=OUTDIR)
    mkpath(outdir)
    println("\n=== Part 1b: CDF for PoF ε=0 & CVaR γ=0.1 α=0.01 (same extractor as Part 1) ===")
    for (pat, tag, label) in [
        ("POF__HARD__eps=0.0__",               "POF_eps0",        "PoF (ε=0)"),
        ("CVaR__HARD__alpha=0.01__gamma=0.1__", "CVaR_g0.1_a0.01", "CVaR (γ=0.1, α=0.01)"),
    ]
        println("Processing $label ...")
        data = collect_data(root, pat; extractor=last_nonzero_inj_rate)
        println("  Loaded $(length(data)) samples")
        if length(data) < 2
            @warn "Skipping $tag: need ≥2 samples"
            continue
        end
        cr = compute_case(data, label; B=B_SINGLE)
        plot_single_hist(cr, joinpath(outdir, "hist_$(tag).png"))
        plot_single_cdf(cr, joinpath(outdir, "cdf_$(tag).png"))
    end
end

"""Part 1 only: `cdf_POF_eps0.01.png`, `cdf_CVaR_g0.05_a0.05.png`, and matching hists (same style as before)."""
function run_part1_only!(; root=ROOT, outdir=OUTDIR)
    mkpath(outdir)
    println("\n=== Part 1: Split single-panel plots ===")
    for (pat, tag, label) in [
        ("POF__HARD__eps=0.01__",              "POF_eps0.01",       "PoF (eps=0.01)"),
        ("CVaR__HARD__alpha=0.05__gamma=0.05__","CVaR_g0.05_a0.05", "CVaR (g=0.05 a=0.05)"),
    ]
        println("Processing $label...")
        data = collect_data(root, pat)
        println("  Loaded $(length(data)) samples")
        length(data) < 2 && continue
        cr = compute_case(data, label; B=B_SINGLE)
        plot_single_hist(cr, joinpath(outdir, "hist_$(tag).png"))
        plot_single_cdf(cr, joinpath(outdir, "cdf_$(tag).png"))
    end
end

function main()
    mkpath(OUTDIR)
    run_part1_only!(root=ROOT, outdir=OUTDIR)
    run_part1b_inj6!(root=ROOT, outdir=OUTDIR)

    # --- Part 2 & 3: 4×3 grids ---
    println("\n=== Part 2 & 3: Computing 12 cases for 4×3 grids (B=$B_GRID) ===")

    grid_results = CaseResult[]
    for (i, (pat, title)) in enumerate(GRID)
        println("  [$i/12] $title ...")
        data = collect_data(ROOT, pat)
        println("         $(length(data)) samples loaded")
        if length(data) < 2
            @warn "Skipping $title: only $(length(data)) samples"
            continue
        end
        push!(grid_results, compute_case(data, title; B=B_GRID))
    end

    if length(grid_results) == 12
        println("\nPlotting 4×3 histogram grid...")
        plot_grid_histogram(grid_results, joinpath(OUTDIR, "grid_histogram_4x3.png"))
        println("Plotting 4×3 CDF grid...")
        plot_grid_cdf(grid_results, joinpath(OUTDIR, "grid_cdf_4x3.png"))
        println("Plotting 4×3 CDF zoom grid...")
        plot_grid_cdf_zoom(grid_results, joinpath(OUTDIR, "grid_cdf_zoom_4x3.png"))
        selected_results = select_cases(grid_results, SELECTED_GRID)
        println("Plotting selected 1×3 histogram grid...")
        plot_selected_histogram(selected_results, joinpath(OUTDIR, "grid_histogram_selected_1x3.png"))
        println("Plotting selected 1×3 CDF grid...")
        plot_selected_cdf(selected_results, joinpath(OUTDIR, "grid_cdf_selected_1x3.png"))
    else
        @warn "Only $(length(grid_results))/12 cases computed, skipping grids"
    end

    println("\n=== All done! ===")
end

if get(ENV, "BOOTSTRAP_DEFINE_ONLY", "") == "1"
    # Load plotting functions without collecting data or recomputing statistics.
elseif get(ENV, "BOOTSTRAP_ONLY_INJ6", "") == "1"
    run_part1b_inj6!()
elseif get(ENV, "BOOTSTRAP_ONLY_PART1", "") == "1"
    run_part1_only!()
    println("\n=== Part 1 only: done ===")
else
    main()
end
