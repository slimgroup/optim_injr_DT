#!/usr/bin/env julia
# POF distributions + left 1% tail with KDE smoothing (pure PyPlot)

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using CSV, DataFrames, Dates, Printf
using PyPlot
using Statistics           # mean / std / quantile
using JLD2                 # 兜底扫描 final.jld2 需要

# ==================== CONFIG ====================
const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const NBINS   = 12
const LEFT_TAIL_Q = 0.01      # 1%
const DRAW_ECDF_PANEL   = false
const DRAW_MEANSTD_BARS = true

# 期望 10 个 eps（按你的目录约定；不同可改）
const EXPECTED_EPS = sort([0.0, 0.0005, 0.001, 0.002, 0.003, 0.005, 0.01, 0.02, 0.03, 0.05])

# 可选：手动指定要读的 CSV（留空则自动找最新）
const DETAIL_CSV_OVERRIDE = ""

# KDE 设置
const KDE_POINTS = 512
const KDE_MARGIN = 0.05

# 可选视觉微调
const PRETTY_AXES = true
# ================================================

# ---------- 选最新明细：优先 pof_*，再 inj_* ----------
function latest_detail_csv(root::String)
    if !isempty(DETAIL_CSV_OVERRIDE)
        return DETAIL_CSV_OVERRIDE
    end
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

# ---------- eps 解析（case_tag 优先，risk_dir 兜底；支持科学计数） ----------
function _extract_eps(case_tag::AbstractString, risk_dir::AbstractString)
    m = match(r"eps\s*=\s*([0-9.eE+\-]+)", case_tag)
    m === nothing && (m = match(r"eps\s*=\s*([0-9.eE+\-]+)", risk_dir))
    return m === nothing ? NaN : parse(Float64, m.captures[1])
end

# ---------- 只取 POF + sample∈1..32 + ok_final（从 CSV） ----------
function load_pof_from_csv(root::String)
    path = latest_detail_csv(root)
    @info "Loading detail CSV" path
    df = CSV.read(path, DataFrame)
    for c in (:case_tag, :sample, :status, :last_inj_rate)
        @assert hasproperty(df, c) "Missing column $(c) in $(path)"
    end
    df = df[occursin.("POF", df.case_tag), :]
    df = df[in.(df.sample, Ref(collect(SAMPLES))), :]
    df = df[df.status .== "ok_final", :]

    has_rd = hasproperty(df, :risk_dir)
    df.eps = Vector{Float64}(undef, nrow(df))
    for i in 1:nrow(df)
        ct = String(df.case_tag[i])
        rd = has_rd ? String(df.risk_dir[i]) : ""
        df.eps[i] = _extract_eps(ct, rd)
    end
    df = df[.!isnan.(df.eps), :]
    sort!(df, [:eps, :sample])
    return df
end

# ---------- 兜底：直接扫 POF 目录，读 final.jld2 ----------
@inline function _get(data, k::AbstractString)
    haskey(data, k) ? data[k] : (haskey(data, Symbol(k)) ? data[Symbol(k)] : nothing)
end
function _first_column(v)
    ndims(v) == 1 && return collect(v)
    ndims(v) == 2 && return vec(view(v, :, 1))
    error("inj_rate_arr has unexpected dimension: $(ndims(v))")
end
function last_nonzero_inj_rate(data; init_rate::Float64=1e-4)
    raw = _get(data, "inj_rate_arr"); raw === nothing && return init_rate
    col1 = _first_column(raw)
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? init_rate : clean[idx]
end

function scan_pof_dirs(root::String)
    risk_dirs = filter(d ->
        isdir(joinpath(root, d)) && occursin("POF", d) && d != "geo" && !startswith(d, ".")
    , readdir(root))
    sort!(risk_dirs)
    rows = NamedTuple[]
    for risk_name in risk_dirs
        risk_dir = joinpath(root, risk_name)
        case_tag = occursin("eps", risk_name) ?
                   "POF_eps=" * match(r"eps\s*=\s*([0-9.eE+\-]+)", risk_name).captures[1] :
                   "POF"
        for s in SAMPLES
            final_path = joinpath(risk_dir, "sample=$(s)", "final.jld2")
            if isfile(final_path)
                try
                    data = load(final_path)
                    last_inj = last_nonzero_inj_rate(data)
                    push!(rows, (case_tag=case_tag, risk_dir=risk_name, sample=s,
                                 status="ok_final", last_inj_rate=last_inj))
                catch
                    # 忽略异常样本；如需可记录 load_error 表
                end
            end
        end
    end
    df = DataFrame(rows)
    df.eps = [ _extract_eps(String(df.case_tag[i]), String(df.risk_dir[i])) for i in 1:nrow(df) ]
    df = df[.!isnan.(df.eps), :]
    sort!(df, [:eps, :sample])
    return df
end

# ---------- 简易 Gaussian KDE + smoothed quantile ----------
silverman_bandwidth(x::Vector{Float64}) = begin
    n = length(x); n == 0 && return 1e-8
    s = std(x); s = s > 0 ? s : (maximum(x) - minimum(x) + eps())/1.349
    1.06 * s * n^(-1/5)
end
trapz(x::AbstractVector, y::AbstractVector) =
    sum( (y[1:end-1] .+ y[2:end]) .* diff(x) ) / 2
function kde_pdf(x::Vector{Float64}; xmin=nothing, xmax=nothing, npts::Int=KDE_POINTS)
    @assert !isempty(x)
    x = sort(x)
    xmin === nothing && (xmin = x[1] - KDE_MARGIN*(x[end]-x[1] + eps()))
    xmax === nothing && (xmax = x[end] + KDE_MARGIN*(x[end]-x[1] + eps()))
    xs = collect(range(xmin, xmax; length=npts))
    h = max(silverman_bandwidth(x), eps())

    @inline φ(z) = 0.3989422804014327 * exp(-0.5*z*z)

    pdf = zeros(Float64, npts)
    invh = 1/h
    for (i,u) in enumerate(xs)
        s = 0.0
        @inbounds for xi in x
            s += φ((u - xi)*invh)
        end
        pdf[i] = s / (length(x) * h)
    end
    area = trapz(xs, pdf)
    area > 0 && (pdf ./= area)
    return xs, pdf
end
function kde_cdf(xs::AbstractVector{<:Real}, pdf::AbstractVector{<:Real})
    n = length(xs)
    cdf = zeros(Float64, n)
    for i in 2:n
        cdf[i] = cdf[i-1] + (pdf[i] + pdf[i-1]) * (xs[i] - xs[i-1]) / 2
    end
    cdf[end] > 0 && (cdf ./= cdf[end])
    return cdf
end
function kde_quantile(x::Vector{Float64}, q::Float64)
    xs, pdf = kde_pdf(x)
    xs = collect(xs)
    cdf = kde_cdf(xs, pdf)
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

# ---------- 小工具：美化坐标轴 ----------
function pretty_axes!(ax)
    !PRETTY_AXES && return
    try
        ax.grid(true, linestyle=":", alpha=0.35)
        ax.spines["top"].set_visible(false)
        ax.spines["right"].set_visible(false)
    catch
    end
end

# ---------- 直方图（全范围；固定 2×5 面板，避免拥挤） ----------
function plot_hist_panels(df::DataFrame; nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    nrows, ncols = 2, 5
    @assert length(eps_vals) <= nrows*ncols "eps count > 10"
    fig, axes = subplots(nrows, ncols; figsize=(16, 6.2))
    axes = vec(axes)

    valid = df.last_inj_rate[isfinite.(df.last_inj_rate) .& (df.last_inj_rate .>= 0)]
    global_xmax = isempty(valid) ? 1.0 : maximum(valid)

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .>= 0)]
        isempty(x) && (ax.axis("off"); continue)
        ax.hist(x; bins=nbins, alpha=0.85, edgecolor="none")
        ax.set_title(@sprintf("eps = %.4g", epsv), fontsize=10.5)
        ax.set_xlim(0, global_xmax * 1.05)
        (i > ncols) && ax.set_xlabel("last_inj_rate")
        ((i - 1) % ncols == 0) && ax.set_ylabel("frequency")
        pretty_axes!(ax)
    end
    for j in (length(eps_vals)+1):(nrows*ncols); axes[j].axis("off"); end
    fig.suptitle("POF: Histogram of last_inj_rate (samples 1..32, ok_final)", y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- 左 1% 面板：叠加 KDE（标题简化 + 图内角标） ----------
function plot_hist_left1pct_panels_kde(df::DataFrame; q::Float64=LEFT_TAIL_Q, nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    nrows, ncols = 2, 5
    @assert length(eps_vals) <= nrows*ncols "eps count > 10"
    fig, axes = subplots(nrows, ncols; figsize=(16, 6.2))
    axes = vec(axes)

    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .> 0)]
        isempty(x) && (ax.axis("off"); continue)

        q_raw = quantile(x, q)
        q_kde = kde_quantile(x, q)

        # hist
        ax.hist(x; bins=nbins, alpha=0.65, edgecolor="none")

        # KDE on twin y-axis
        xs, pdf = kde_pdf(x)
        ax2 = ax.twinx()
        ax2.plot(xs, pdf, linewidth=1.8)
        ax2.set_ylim(0, maximum(pdf)*1.2)
        ax2.set_yticks([])
        ax2.grid(false)

        # quantile markers
        ax.axvline(q_raw, color="r", linestyle="--", linewidth=1.5)
        ax.axvline(q_kde, color="C1", linestyle="-",  linewidth=1.5)

        # zoom window
        xmax = max(q_raw, q_kde) * 1.10
        (!isfinite(xmax) || xmax <= 0) && (xmax = maximum(x) * 0.05)
        xmax = max(xmax, quantile(x, 0.05) * 1.25)   # 保证不太窄
        ax.set_xlim(0, xmax)

        n_tail = sum(x .<= q_raw)

        # Title 精简，只显示 eps
        ax.set_title(@sprintf("eps = %.4g", epsv), fontsize=10.5)

        # 图内角标（右上角）
        info = @sprintf("raw=%.3e\nkde=%.3e\nn=%d", q_raw, q_kde, n_tail)
        ax.text(0.98, 0.98, info, ha="right", va="top",
                transform=ax.transAxes, fontsize=8.5,
                bbox=Dict("facecolor"=>"white", "alpha"=>0.6, "edgecolor"=>"none"))

        (i > ncols) && ax.set_xlabel("last_inj_rate (zoom 1%)")
        ((i - 1) % ncols == 0) && ax.set_ylabel("frequency")
        pretty_axes!(ax)
    end
    for j in (length(eps_vals)+1):(nrows*ncols); axes[j].axis("off"); end
    fig.suptitle(@sprintf("POF: Left %.1f%% Tail (empirical vs KDE, samples 1..32, ok_final)", q*100),
                 y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ---------- ECDF（可选；修正类型注解） ----------
function ecdf(x::AbstractVector{<:Real})
    xx = sort(Float64.(x))
    n  = length(xx)
    y  = (1:n) ./ n
    return xx, y
end
function plot_ecdf_panels(df::DataFrame)
    eps_vals = sort(unique(df.eps))
    nrows, ncols = 2, 5
    fig, axes = subplots(nrows, ncols; figsize=(16, 6.2))
    axes = vec(axes)
    for (i, epsv) in enumerate(eps_vals)
        ax = axes[i]
        x = collect(skipmissing(df.last_inj_rate[df.eps .== epsv]))
        x = x[isfinite.(x) .& (x .>= 0)]
        isempty(x) && (ax.axis("off"); continue)
        xs, ys = ecdf(x)
        ax.plot(xs, ys)
        ax.set_title(@sprintf("eps = %.4g", epsv), fontsize=11)
        (i > ncols) && ax.set_xlabel("last_inj_rate")
        ((i - 1) % ncols == 0) && ax.set_ylabel("ECDF")
        pretty_axes!(ax)
    end
    for j in (length(eps_vals)+1):(nrows*ncols); axes[j].axis("off"); end
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
        ks  = isempty(base) ? NaN : ks_statistic(x, base)
        push!(rows, (e, length(x), mean(x), std(x), p10, p50, p90, ks))
    end
    return rows
end

# ---------- 左 1% 明细表（raw vs KDE）【修复 missing/索引一致性】 ----------
function build_left_tail_table(df::DataFrame; q::Float64=LEFT_TAIL_Q)
    eps_vals = sort(unique(df.eps))
    rows = DataFrame(eps=Float64[], q1_raw=Float64[], q1_kde=Float64[],
                     n_tail_raw=Int[], min_tail_raw=Float64[], max_tail_raw=Float64[],
                     samples_tail_raw=String[])
    for e in eps_vals
        sub = df[df.eps .== e, :]
        vals = collect(skipmissing(sub.last_inj_rate))
        mask = map(t -> isfinite(t) && t > 0, vals)
        clean = vals[mask]
        if isempty(clean)
            push!(rows, (e, NaN, NaN, 0, NaN, NaN, "")); continue
        end
        q_raw = quantile(clean, q)
        q_kde = kde_quantile(clean, q)

        tail_mask = map(t -> t <= q_raw, clean)
        tail_vals = clean[tail_mask]

        samples_clean = Vector(sub.sample[.!ismissing.(sub.last_inj_rate) .& mask])
        samples_tail  = samples_clean[tail_mask]

        push!(rows, (e, q_raw, q_kde, sum(tail_mask),
                     isempty(tail_vals) ? NaN : minimum(tail_vals),
                     isempty(tail_vals) ? NaN : maximum(tail_vals),
                     join(samples_tail, ",")))
    end
    return rows
end

# ---------- mean±std 误差棒 ----------
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
df_pof = load_pof_from_csv(ROOT)
@info "POF rows (from CSV, ok_final, samples 1..32)" nrow(df_pof)
eps_csv = sort(unique(df_pof.eps))
@info "EPS set (CSV)" eps_csv

# CSV 不全 -> 兜底扫描目录
if length(eps_csv) < length(EXPECTED_EPS)
    @warn "EPS fewer than expected; fallback to scanning POF dirs" eps_csv EXPECTED_EPS
    df_scan = scan_pof_dirs(ROOT)
    eps_scan = sort(unique(df_scan.eps))
    @info "EPS set (scan)" eps_scan
    if length(eps_scan) >= length(eps_csv)
        df_pof = df_scan
        @info "Using scanned data (covers more eps)."
    end
end

ts  = Dates.format(now(), "yyyymmdd_HHMMSS")
pct = Int(round(LEFT_TAIL_Q * 100))

# 面板 1：全范围直方图（全部 eps）
fig1 = plot_hist_panels(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_hist_$(ts).png"), dpi=200)
close("all")

# 面板 2：左 1%，叠加 KDE（全部 eps）
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
