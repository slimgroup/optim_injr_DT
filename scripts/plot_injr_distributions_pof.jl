#!/usr/bin/env julia
# POF distribution panel + sensitivity table (pure PyPlot)
#
# Outputs:
#   panel_POF_last_inj_rate_hist_*.png     # 直方图面板（所有 POF eps）
#   panel_POF_last_inj_rate_ecdf_*.png     # （可选）每个 eps 的 ECDF 面板
#   panel_POF_last_inj_rate_meanstd_*.png  # （可选）mean±std 误差棒
#   pof_sensitivity_table_*.csv            # 敏感性表（mean/std/quantiles/KS to eps=0）

using CSV, DataFrames, Dates, Printf
using PyPlot

# ==================== CONFIG ====================
const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const NBINS   = 12

const DRAW_ECDF_PANEL     = true    # 画 ECDF 面板
const DRAW_MEANSTD_BARS   = true    # 画 mean±std 误差棒
# ================================================

# ---------- helper: select latest inj_rate_detail_*.csv ----------
function latest_detail_csv(root::String)
    files = filter(f -> occursin(r"^inj_rate_detail_\d{8}_\d{6}\.csv$", f), readdir(root))
    if !isempty(files)
        parse_ts(s) = try
            DateTime(match(r"(\d{8}_\d{6})", s).captures[1], dateformat"yyyymmdd_HHMMSS")
        catch; DateTime(0); end
        files_sorted = sort(files, by=parse_ts)
        return joinpath(root, last(files_sorted))
    else
        allcsv = filter(f -> endswith(f, ".csv") && occursin("inj_rate_detail_", f), readdir(root))
        @assert !isempty(allcsv) "No inj_rate_detail_*.csv found under $root"
        files_sorted = sort(allcsv, by=f -> stat(joinpath(root, f)).mtime)
        return joinpath(root, last(files_sorted))
    end
end

# ---------- load & filter POF, samples 1..32, ok_final ----------
function load_pof_detail(root::String)
    path = latest_detail_csv(root)
    @info "Loading detail CSV" path
    df = CSV.read(path, DataFrame)
    for c in (:case_tag, :sample, :status, :last_inj_rate)
        @assert hasproperty(df, c) "Missing column $(c) in $(path)"
    end
    df = df[occursin.("POF", df.case_tag), :]
    df = df[in.(df.sample, Ref(collect(SAMPLES))), :]
    df = df[df.status .== "ok_final", :]
    df.eps = map(df.case_tag) do s
        m = match(r"POF_eps\s*=\s*([0-9]*\.?[0-9]+)", String(s))
        m === nothing ? NaN : parse(Float64, m.captures[1])
    end
    df = df[.!isnan.(df.eps), :]
    sort!(df, [:eps, :sample])
    return df
end

# ---------- plotting: histogram panel ----------
function plot_hist_panels(df::DataFrame; nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    # 布局：尽量 2×5；否则根据数量自动分配
    ncols = n >= 10 ? 5 : min(4, n)
    nrows = ceil(Int, n / ncols)

    fig, axes = subplots(nrows, ncols; figsize=(3.2*ncols, 2.6*nrows))
    axes = (nrows == 1 || ncols == 1) ? collect(axes) : vec(axes)

    valid = df.last_inj_rate[isfinite.(df.last_inj_rate) .& (df.last_inj_rate .>= 0)]
    global_xmax = isempty(valid) ? 1.0 : maximum(valid)
    global_xmax = isfinite(global_xmax) ? global_xmax : 1.0

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .>= 0)]
        if isempty(x)
            ax.set_title(@sprintf("POF_eps=%.4g (n=0)", epsv))
            ax.axis("off")
            continue
        end
        ax.hist(x; bins=nbins, alpha=0.85, edgecolor="none")
        ax.set_title(@sprintf("POF_eps=%.4g (n=%d)", epsv, length(x)), fontsize=11)
        ax.grid(true, linestyle="--", alpha=0.3)
        ax.set_xlim(0, global_xmax * 1.05)
        if (i - 1) % ncols == 0
            ax.set_ylabel("frequency")
        end
        if i > ncols*(nrows-1)
            ax.set_xlabel("last_inj_rate")
        end
    end
    for j in (n+1):length(axes)
        axes[j].axis("off")
    end
    fig.suptitle("POF: Histogram of last_inj_rate (samples 1..32, ok_final)", y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- plotting: ECDF panel (optional) ----------
function ecdf(x::Vector{Float64})
    x = sort(x)
    n = length(x)
    y = (1:n) ./ n
    return x, y
end

function plot_ecdf_panels(df::DataFrame)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    ncols = n >= 10 ? 5 : min(4, n)
    nrows = ceil(Int, n / ncols)

    fig, axes = subplots(nrows, ncols; figsize=(3.2*ncols, 2.6*nrows))
    axes = (nrows == 1 || ncols == 1) ? collect(axes) : vec(axes)

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .>= 0)]
        if isempty(x)
            ax.set_title(@sprintf("POF_eps=%.4g (n=0)", epsv))
            ax.axis("off")
            continue
        end
        xs, ys = ecdf(x)
        ax.plot(xs, ys)
        ax.set_title(@sprintf("POF_eps=%.4g", epsv), fontsize=11)
        ax.grid(true, linestyle="--", alpha=0.3)
        if (i - 1) % ncols == 0
            ax.set_ylabel("ECDF")
        end
        if i > ncols*(nrows-1)
            ax.set_xlabel("last_inj_rate")
        end
    end
    for j in (n+1):length(axes)
        axes[j].axis("off")
    end
    fig.suptitle("POF: ECDF of last_inj_rate (samples 1..32, ok_final)", y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- sensitivity table & mean±std bars ----------
function ks_statistic(x::Vector{Float64}, y::Vector{Float64})
    # two-sample KS
    xs, cdfx = ecdf(x); ys, cdfy = ecdf(y)
    grid = sort(unique(vcat(xs, ys)))
    # step cdf
    function stepcdf(xx, xgrid, cdfvals)
        out = similar(xx)
        i = 1
        for (k, v) in enumerate(xx)
            while i <= length(xgrid) && xgrid[i] <= v
                i += 1
            end
            out[k] = (i == 1) ? 0.0 : cdfvals[i-1]
        end
        return out
    end
    max(abs.(stepcdf(grid, xs, cdfx) .- stepcdf(grid, ys, cdfy))...)
end

function build_sensitivity_table(df::DataFrame)
    eps_vals = sort(unique(df.eps))
    rows = DataFrame(eps=Float64[], count=Int[], mean=Float64[], std=Float64[],
                     p10=Float64[], p50=Float64[], p90=Float64[], ks_to_eps0=Float64[])
    # baseline for KS
    base_eps = minimum(eps_vals)
    base = collect(skipmissing(df.last_inj_rate[df.eps .== base_eps]))
    base = base[isfinite.(base) .& (base .>= 0)]

    for e in eps_vals
        x = collect(skipmissing(df.last_inj_rate[df.eps .== e]))
        x = x[isfinite.(x) .& (x .>= 0)]
        if isempty(x)
            push!(rows, (e, 0, NaN, NaN, NaN, NaN, NaN, NaN))
            continue
        end
        p10 = quantile(x, 0.10); p50 = quantile(x, 0.50); p90 = quantile(x, 0.90)
        ks  = ks_statistic(x, base)
        push!(rows, (e, length(x), mean(x), std(x), p10, p50, p90, ks))
    end
    return rows
end

function plot_meanstd_bars(sens::DataFrame)
    fig, ax = subplots(1,1; figsize=(8,4))
    xlab = string.(round.(sens.eps, sigdigits=4))
    ax.errorbar(1:nrow(sens), sens.mean, yerr=sens.std, fmt="o-")
    ax.set_xticks(1:nrow(sens), xlab, rotation=0)
    ax.set_xlabel("POF eps")
    ax.set_ylabel("mean(last_inj_rate) ± std")
    ax.grid(true, linestyle="--", alpha=0.3)
    fig.tight_layout()
    return fig
end

# ==================== main ====================
df_pof = load_pof_detail(ROOT)
@info "POF rows (ok_final, samples 1..32)" nrow(df_pof)
@info "EPS set" sort(unique(df_pof.eps))
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

# panel: histogram
fig1 = plot_hist_panels(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_hist_$ts.png"), dpi=200)
close("all")

# sensitivity table
sens = build_sensitivity_table(df_pof)
CSV.write(joinpath(ROOT, "pof_sensitivity_table_$ts.csv"), sens)

# optional: ECDF panel
if DRAW_ECDF_PANEL
    fig2 = plot_ecdf_panels(df_pof)
    savefig(joinpath(ROOT, "panel_POF_last_inj_rate_ecdf_$ts.png"), dpi=200)
    close("all")
end

# optional: mean ± std bars
if DRAW_MEANSTD_BARS
    fig3 = plot_meanstd_bars(sens)
    savefig(joinpath(ROOT, "panel_POF_last_inj_rate_meanstd_$ts.png"), dpi=200)
    close("all")
end

println("Saved:")
println("  panel_POF_last_inj_rate_hist_$ts.png")
if DRAW_ECDF_PANEL
    println("  panel_POF_last_inj_rate_ecdf_$ts.png")
end
if DRAW_MEANSTD_BARS
    println("  panel_POF_last_inj_rate_meanstd_$ts.png")
end
println("  pof_sensitivity_table_$ts.csv")
