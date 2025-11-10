#!/usr/bin/env julia
# POF distributions + left 1% tail with KDE smoothing (pure PyPlot)

using CSV, DataFrames, Dates, Printf
using PyPlot
using Statistics           # mean / std / quantile

# ==================== CONFIG ====================
const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const NBINS   = 12
const LEFT_TAIL_Q = 0.01      # 1%
const DRAW_ECDF_PANEL   = false
const DRAW_MEANSTD_BARS = true
# KDE 设置
const KDE_POINTS = 512        # KDE 评估网格点数
const KDE_MARGIN = 0.05       # 在[min,max]两侧各加5%范围
# ================================================

# ---------- 选最新 inj_rate_detail_*.csv ----------
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

# ---------- 只取 POF + sample∈1..32 + ok_final ----------
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
    # 解析 eps，支持科学计数/小数
    df.eps = map(df.case_tag) do s
        m = match(r"eps\s*=\s*([0-9.eE+-]+)", String(s))
        m === nothing ? NaN : parse(Float64, m.captures[1])
    end
    df = df[.!isnan.(df.eps), :]
    sort!(df, [:eps, :sample])
    return df
end

# ---------- 简易 Gaussian KDE + smoothed quantile ----------
# Silverman 带宽；为避免 std=0，给个极小值兜底
silverman_bandwidth(x::Vector{Float64}) = begin
    n = length(x); n == 0 && return 1e-8
    s = std(x); s = s > 0 ? s : (maximum(x) - minimum(x) + eps())/1.349
    1.06 * s * n^(-1/5)
end

# 在网格上计算 KDE pdf（高斯核）
function kde_pdf(x::Vector{Float64}; xmin=nothing, xmax=nothing, npts::Int=KDE_POINTS)
    @assert !isempty(x)
    x = sort(x)
    xmin === nothing && (xmin = x[1] - KDE_MARGIN*(x[end]-x[1]+eps()))
    xmax === nothing && (xmax = x[end] + KDE_MARGIN*(x[end]-x[1]+eps()))
    xs = range(xmin, xmax; length=npts)
    h = max(silverman_bandwidth(x), eps())
    # pdf(u) = mean φ((u-x)/h) / h
    function φ(z)  # 标准正态密度
        invsqrt2π = 0.3989422804014327
        return invsqrt2π * exp(-0.5*z*z)
    end
    pdf = zeros(Float64, npts)
    invh = 1/h
    for (i,u) in enumerate(xs)
        s = 0.0
        for xi in x
            s += φ((u - xi)*invh)
        end
        pdf[i] = s / (length(x) * h)
    end
    # 归一化（数值稳健）
    area = trapz(xs, pdf)
    if area > 0
        pdf ./= area
    end
    return xs, pdf
end

# 累积积分（梯形法）得到 CDF
trapz(x::AbstractVector, y::AbstractVector) = sum( (y[1:end-1] .+ y[2:end]) .* diff(x) ) / 2
function kde_cdf(xs::Vector{Float64}, pdf::Vector{Float64})
    cdf = zeros(Float64, length(xs))
    for i in 2:length(xs)
        cdf[i] = cdf[i-1] + (pdf[i] + pdf[i-1]) * (xs[i] - xs[i-1]) / 2
    end
    # 归一化到[0,1]
    if cdf[end] > 0
        cdf ./= cdf[end]
    end
    return cdf
end

# 求给定 q 的 smoothed quantile：在 KDE-CDF 上反解
function kde_quantile(x::Vector{Float64}, q::Float64)
    xs, pdf = kde_pdf(x)
    cdf = kde_cdf(xs, pdf)
    # 找到第一个 cdf >= q，线性插值
    idx = findfirst(>=(q), cdf)
    if idx === nothing
        return xs[end]
    elseif idx == 1
        return xs[1]
    else
        x1, x2 = xs[idx-1], xs[idx]
        y1, y2 = cdf[idx-1], cdf[idx]
        t = (q - y1) / max(y2 - y1, eps())
        return x1 + t*(x2 - x1)
    end
end

# ---------- 直方图（全范围） ----------
function plot_hist_panels(df::DataFrame; nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    ncols = n >= 10 ? 5 : min(4, n)
    nrows = ceil(Int, n / ncols)

    fig, axes = subplots(nrows, ncols; figsize=(3.2*ncols, 2.6*nrows))
    axes = (nrows == 1 || ncols == 1) ? collect(axes) : vec(axes)

    valid = df.last_inj_rate[isfinite.(df.last_inj_rate) .& (df.last_inj_rate .>= 0)]
    global_xmax = isempty(valid) ? 1.0 : maximum(valid)

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .>= 0)]
        if isempty(x)
            ax.set_title(@sprintf("POF_eps=%.4g (n=0)", epsv)); ax.axis("off"); continue
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

# ---------- 左 1% 面板：叠加 KDE，标 raw 与 KDE 的 1% ----------
function plot_hist_left1pct_panels_kde(df::DataFrame; q::Float64=LEFT_TAIL_Q, nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    ncols = n >= 10 ? 5 : min(4, n)
    nrows = ceil(Int, n / ncols)

    fig, axes = subplots(nrows, ncols; figsize=(3.4*ncols, 2.8*nrows))
    axes = (nrows == 1 || ncols == 1) ? collect(axes) : vec(axes)

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .> 0)]
        if isempty(x)
            ax.set_title(@sprintf("POF_eps=%.4g (n=0)", epsv)); ax.axis("off"); continue
        end

        # raw 1%
        q_raw = quantile(x, q)
        # KDE smoothed 1%
        q_kde = kde_quantile(x, q)

        # 直方图（原值）
        ax.hist(x; bins=nbins, alpha=0.65, edgecolor="none")

        # KDE 曲线（乘以样本数和bin宽近似到直方图高度，无需精确对齐，仅作形状参考）
        xs, pdf = kde_pdf(x)
        # 将 pdf 按当前轴y范围缩放：先画第二条y轴，（或直接标准画pdf）
        ax2 = ax.twinx()
        ax2.plot(xs, pdf, linewidth=1.8)  # 默认颜色=橙（matplotlib cycle）
        ax2.set_ylim(0, maximum(pdf)*1.2)
        ax2.set_yticks([])
        ax2.grid(false)

        # 阈值线
        ax.axvline(q_raw, color="r", linestyle="--", linewidth=1.5, label="raw q1%")
        ax.axvline(q_kde, color="C1", linestyle="-",  linewidth=1.5, label="KDE q1%")

        # 横轴缩放到 1% 区域
        xmax = (q_kde > 0 ? q_kde : q_raw) * 1.10
        if !isfinite(xmax) || xmax <= 0
            xmax = maximum(x) * 0.05
        end
        ax.set_xlim(0, xmax)

        n_tail = sum(x .<= q_raw)
        ax.set_title(@sprintf("POF_eps=%.4g | raw q1%%=%.3e | KDE q1%%=%.3e | n_tail=%d",
                              epsv, q_raw, q_kde, n_tail), fontsize=9)
        ax.grid(true, linestyle="--", alpha=0.3)

        if (i - 1) % ncols == 0; ax.set_ylabel("frequency"); end
        if i > ncols*(nrows-1);  ax.set_xlabel("last_inj_rate (zoomed to 1%)"); end
    end
    for j in (n+1):length(axes); axes[j].axis("off"); end
    fig.suptitle(@sprintf("POF: Left %.1f%% Tail (empirical vs KDE, samples 1..32, ok_final)", q*100),
                 y=0.98, fontsize=14)
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

# ---------- 左 1% 明细表（raw vs KDE） ----------
function build_left_tail_table(df::DataFrame; q::Float64=LEFT_TAIL_Q)
    eps_vals = sort(unique(df.eps))
    rows = DataFrame(eps=Float64[], q1_raw=Float64[], q1_kde=Float64[],
                     n_tail_raw=Int[], min_tail_raw=Float64[], max_tail_raw=Float64[],
                     samples_tail_raw=String[])
    for e in eps_vals
        sub = df[df.eps .== e, :]
        x = collect(skipmissing(sub.last_inj_rate))
        x = x[isfinite.(x) .& (x .> 0)]
        if isempty(x)
            push!(rows, (e, NaN, NaN, 0, NaN, NaN, "")); continue
        end
        q_raw = quantile(x, q)
        q_kde = kde_quantile(x, q)
        idx   = findall(t -> t <= q_raw, sub.last_inj_rate)  # raw 左尾样本
        tail_vals = Vector(sub.last_inj_rate[idx])
        samples   = Vector(sub.sample[idx])
        push!(rows, (e, q_raw, q_kde, length(idx),
                     isempty(tail_vals) ? NaN : minimum(tail_vals),
                     isempty(tail_vals) ? NaN : maximum(tail_vals),
                     join(samples, ",")))
    end
    return rows
end

# ==================== main ====================
df_pof = load_pof_detail(ROOT)
@info "POF rows (ok_final, samples 1..32)" nrow(df_pof)
@info "EPS set" sort(unique(df_pof.eps))
ts  = Dates.format(now(), "yyyymmdd_HHMMSS")
pct = Int(round(LEFT_TAIL_Q * 100))

# 面板 1：全范围直方图
fig1 = plot_hist_panels(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_hist_$(ts).png"), dpi=200)
close("all")

# 面板 2：左 1%，叠加 KDE（所有 eps，自动排版）
fig2 = plot_hist_left1pct_panels_kde(df_pof; q=LEFT_TAIL_Q)
savefig(joinpath(ROOT, "panel_POF_left$(pct)pct_hist_kde_$(ts).png"), dpi=240)
close("all")

# 表：敏感性 & 左尾
sens = build_sensitivity_table(df_pof)
CSV.write(joinpath(ROOT, "pof_sensitivity_table_$(ts).csv"), sens)

left_tbl = build_left_tail_table(df_pof; q=LEFT_TAIL_Q)
CSV.write(joinpath(ROOT, "pof_left_tail_$(pct)pct_$(ts).csv"), left_tbl)

# 可选：ECDF & mean±std
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
println("  panel_POF_left$(pct)pct_hist_kde_$(ts).png")
if DRAW_ECDF_PANEL;   println("  panel_POF_last_inj_rate_ecdf_$(ts).png"); end
if DRAW_MEANSTD_BARS; println("  panel_POF_last_inj_rate_meanstd_$(ts).png"); end
println("  pof_sensitivity_table_$(ts).csv")
println("  pof_left_tail_$(pct)pct_$(ts).csv")
