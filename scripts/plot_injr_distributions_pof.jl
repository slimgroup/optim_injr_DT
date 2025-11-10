#!/usr/bin/env julia
# POF distribution panels + sensitivity & left-tail (1%) analysis  (pure PyPlot)
#
# 产物：
#   panel_POF_last_inj_rate_hist_*.png     # 全范围直方图面板（每个 eps 一格）
#   panel_POF_left1pct_hist_*.png          # 左 1% 放大直方图面板（红线=1%分位点）
#   panel_POF_last_inj_rate_ecdf_*.png     # （可选）ECDF 面板
#   panel_POF_last_inj_rate_meanstd_*.png  # （可选）mean±std 误差棒
#   pof_sensitivity_table_*.csv            # 敏感性表（mean/std/p10/p50/p90/KS→eps=0）
#   pof_left_tail_1pct_*.csv               # 左 1% 明细（阈值、样本编号等）

using CSV, DataFrames, Dates, Printf
using PyPlot
using Statistics           # quantile, mean, std

# ==================== CONFIG ====================
const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const NBINS   = 12

const DRAW_ECDF_PANEL     = false   # 如需 ECDF 面板改 true
const DRAW_MEANSTD_BARS   = true    # 是否输出 mean±std 误差棒图
const LEFT_TAIL_Q         = 0.01    # 左侧 1%（改成 0.005 / 0.02 等）
# ================================================

# ---------- helper: 选最新 inj_rate_detail_*.csv ----------
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

# ---------- load & filter：只取 POF + sample∈1..32 + ok_final ----------
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
    # 解析 eps
    df.eps = map(df.case_tag) do s
        m = match(r"POF_eps\s*=\s*([0-9]*\.?[0-9]+)", String(s))
        m === nothing ? NaN : parse(Float64, m.captures[1])
    end
    df = df[.!isnan.(df.eps), :]
    sort!(df, [:eps, :sample])
    return df
end

# ---------- 直方图面板（全范围） ----------
function plot_hist_panels(df::DataFrame; nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    ncols = n >= 10 ? 5 : min(4, n)        # 10 个时 2×5
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
        if (i - 1) % ncols == 0; ax.set_ylabel("frequency"); end
        if i > ncols*(nrows-1);  ax.set_xlabel("last_inj_rate"); end
    end
    for j in (n+1):length(axes); axes[j].axis("off"); end
    fig.suptitle("POF: Histogram of last_inj_rate (samples 1..32, ok_final)", y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- 左侧 1% 面板（放大到 q=1%） ----------
function plot_hist_left1pct_panels(df::DataFrame; q::Float64=LEFT_TAIL_Q, nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    ncols = n >= 10 ? 5 : min(4, n)
    nrows = ceil(Int, n / ncols)

    fig, axes = subplots(nrows, ncols; figsize=(3.2*ncols, 2.6*nrows))
    axes = (nrows == 1 || ncols == 1) ? collect(axes) : vec(axes)

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .> 0)]
        if isempty(x)
            ax.set_title(@sprintf("POF_eps=%.4g (n=0)", epsv))
            ax.axis("off")
            continue
        end
        qx = quantile(x, q)
        # 避免 qx 为 0 时无法放大
        xmax = qx > 0 ? qx * 1.10 : maximum(x) * 0.05
        ax.hist(x; bins=nbins, alpha=0.85, edgecolor="none")
        ax.axvline(qx, color="r", linestyle="--", linewidth=1.5)  # 1% 分位线
        ax.set_xlim(0, xmax)
        n_tail = sum(x .<= qx)  # 左 1% 样本数
        ax.set_title(@sprintf("POF_eps=%.4g | q1%%=%.3e | n_tail=%d", epsv, qx, n_tail), fontsize=9)
        ax.grid(true, linestyle="--", alpha=0.3)
        if (i - 1) % ncols == 0; ax.set_ylabel("frequency"); end
        if i > ncols*(nrows-1);  ax.set_xlabel("last_inj_rate (zoomed to 1%)"); end
    end
    for j in (n+1):length(axes); axes[j].axis("off"); end
    fig.suptitle(@sprintf("POF: Left %.1f%% Tail (samples 1..32, ok_final)", q*100), y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- ECDF（可选） ----------
function ecdf(x::Vector{Float64})
    x = sort(x); n = length(x); y = (1:n) ./ n; return x, y
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
        if isempty(x); ax.set_title(@sprintf("POF_eps=%.4g (n=0)", epsv)); ax.axis("off"); continue; end
        xs, ys = ecdf(x); ax.plot(xs, ys)
        ax.set_title(@sprintf("POF_eps=%.4g", epsv), fontsize=11)
        ax.grid(true, linestyle="--", alpha=0.3)
        if (i - 1) % ncols == 0; ax.set_ylabel("ECDF"); end
        if i > ncols*(nrows-1);  ax.set_xlabel("last_inj_rate"); end
    end
    for j in (n+1):length(axes); axes[j].axis("off"); end
    fig.suptitle("POF: ECDF of last_inj_rate (samples 1..32, ok_final)", y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- KS 距离 & 敏感性表 ----------
function ks_statistic(x::Vector{Float64}, y::Vector{Float64})
    xs, cdfx = ecdf(x); ys, cdfy = ecdf(y)
    grid = sort(unique(vcat(xs, ys)))
    function stepcdf(xx, xgrid, cdfvals)
        out = similar(xx); i = 1
        for (k, v) in enumerate(xx)
            while i <= length(xgrid) && xgrid[i] <= v; i += 1; end
            out[k] = (i == 1) ? 0.0 : cdfvals[i-1]
        end
        return out
    end
    maximum(abs.(stepcdf(grid, xs, cdfx) .- stepcdf(grid, ys, cdfy)))
end

function build_sensitivity_table(df::DataFrame)
    eps_vals = sort(unique(df.eps))
    rows = DataFrame(eps=Float64[], count=Int[], mean=Float64[], std=Float64[],
                     p10=Float64[], p50=Float64[], p90=Float64[], ks_to_eps0=Float64[])
    # 以最小 eps 作为 KS 的基线（通常是 eps=0）
    base_eps = minimum(eps_vals)
    base = collect(skipmissing(df.last_inj_rate[df.eps .== base_eps]))
    base = base[isfinite.(base) .& (base .>= 0)]
    for e in eps_vals
        x = collect(skipmissing(df.last_inj_rate[df.eps .== e]))
        x = x[isfinite.(x) .& (x .>= 0)]
        if isempty(x)
            push!(rows, (e, 0, NaN, NaN, NaN, NaN, NaN, NaN)); continue
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

# ---------- 左 1% 明细表（样本编号回溯） ----------
function build_left_tail_table(df::DataFrame; q::Float64=LEFT_TAIL_Q)
    eps_vals = sort(unique(df.eps))
    rows = DataFrame(eps=Float64[], q_left=Float64[], n_tail=Int[],
                     min_tail=Float64[], max_tail=Float64[], mean_tail=Float64[],
                     samples_tail=String[])
    for e in eps_vals
        sub = df[df.eps .== e, :]
        x = collect(skipmissing(sub.last_inj_rate))
        x = x[isfinite.(x) .& (x .> 0)]
        if isempty(x)
            push!(rows, (e, NaN, 0, NaN, NaN, NaN, ""))
            continue
        end
        qx = quantile(x, q)
        idx = findall(t -> t <= qx, sub.last_inj_rate)  # 左尾样本索引
        tail_vals = Vector(sub.last_inj_rate[idx])
        samples = Vector(sub.sample[idx])
        push!(rows, (e, qx, length(idx),
                     isempty(tail_vals) ? NaN : minimum(tail_vals),
                     isempty(tail_vals) ? NaN : maximum(tail_vals),
                     isempty(tail_vals) ? NaN : mean(tail_vals),
                     join(samples, ",")))
    end
    return rows
end

# ==================== main ====================
df_pof = load_pof_detail(ROOT)
@info "POF rows (ok_final, samples 1..32)" nrow(df_pof)
@info "EPS set" sort(unique(df_pof.eps))
ts  = Dates.format(now(), "yyyymmdd_HHMMSS")
pct = Int(round(LEFT_TAIL_Q * 100))   # 1% → 1, 2% → 2 ...

# 面板 1：全范围直方图
fig1 = plot_hist_panels(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_hist_$(ts).png"), dpi=200)
close("all")

# 面板 2：左 1% 放大
fig2 = plot_hist_left1pct_panels(df_pof; q=LEFT_TAIL_Q)
savefig(joinpath(ROOT, "panel_POF_left$(pct)pct_hist_$(ts).png"), dpi=200)
close("all")

# 表：敏感性 & 左尾
sens = build_sensitivity_table(df_pof)
CSV.write(joinpath(ROOT, "pof_sensitivity_table_$(ts).csv"), sens)

left_tbl = build_left_tail_table(df_pof; q=LEFT_TAIL_Q)
CSV.write(joinpath(ROOT, "pof_left_tail_$(pct)pct_$(ts).csv"), left_tbl)

# 可选图：ECDF & mean±std
if DRAW_ECDF_PANEL
    fig3 = plot_ecdf_panels(df_pof)
    savefig(joinpath(ROOT, "panel_POF_last_inj_rate_ecdf_$(ts).png"), dpi=200)
    close("all")
end
if DRAW_MEANSTD_BARS
    fig4 = plot_meanstd_bars(sens)
    savefig(joinpath(ROOT, "panel_POF_last_inj_rate_meanstd_$(ts).png"), dpi=200)
    close("all")
end

println("Saved:")
println("  panel_POF_last_inj_rate_hist_$(ts).png")
println("  panel_POF_left$(pct)pct_hist_$(ts).png")
if DRAW_ECDF_PANEL;   println("  panel_POF_last_inj_rate_ecdf_$(ts).png"); end
if DRAW_MEANSTD_BARS; println("  panel_POF_last_inj_rate_meanstd_$(ts).png"); end
println("  pof_sensitivity_table_$(ts).csv")
println("  pof_left_tail_$(pct)pct_$(ts).csv")
