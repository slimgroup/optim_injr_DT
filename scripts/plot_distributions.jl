#!/usr/bin/env julia
# Plot distributions of last_inj_rate for CVaR vs POF (using latest detail CSV)

using Pkg
Pkg.activate(".")

using CSV, DataFrames, Dates
using PyPlot

# ====== Config ======
const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const USE_LOGX = false  # 如果注入率跨多个数量级，设为 true 使用对数横轴

# ====== Locate latest inj_rate_detail_*.csv ======
function latest_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && error("找不到 inj_rate_detail_*.csv，请先运行收集脚本。")
    joinpath(root, sort(files)[end])
end

detail_csv = latest_detail_csv(ROOT)
println("Using detail CSV: ", detail_csv)

# ====== Load & filter ======
df = CSV.read(detail_csv, DataFrame)
df_ok = df[df.status .== "ok_final", :]

# 统一成 Vector{String} 再做 startswith
case_tags = String.(df_ok.case_tag)
is_cvar = startswith.(case_tags, "CVaR")
is_pof  = startswith.(case_tags, "POF")

# 收集为普通向量，避免 SkipMissing 上的 length/plot 问题
vals_cvar = collect(skipmissing(df_ok.last_inj_rate[is_cvar]))
vals_pof  = collect(skipmissing(df_ok.last_inj_rate[is_pof]))

println("Counts -> CVaR: ", length(vals_cvar), " ; POF: ", length(vals_pof))

# ====== Plot helper ======
function plot_hist(x::Vector{<:Real}; ttl::AbstractString, outpath::AbstractString, use_logx::Bool=false)
    if isempty(x)
        @warn "No data to plot for $ttl"
        return
    end
    fig = PyPlot.figure(figsize=(6,4))
    ax  = PyPlot.gca()

    vals = copy(x)
    if use_logx
        vals = filter(>(0.0), vals)   # log 轴要求正数
        if isempty(vals)
            @warn "All values non-positive for $ttl under log scale, skip."
            return
        end
        PyPlot.hist(vals, bins=30, density=true, alpha=0.8)
        PyPlot.xscale("log")
    else
        PyPlot.hist(vals, bins=30, density=true, alpha=0.8)
    end

    PyPlot.xlabel(use_logx ? "last_inj_rate (log scale)" : "last_inj_rate")
    PyPlot.ylabel("density")
    PyPlot.title(ttl)
    PyPlot.grid(true, linestyle="--", linewidth=0.5, alpha=0.6)
    PyPlot.tight_layout()
    PyPlot.savefig(outpath, dpi=200)
    PyPlot.close(fig)
    println("Saved: ", outpath)
end

# ====== Save figures ======
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
out_cvar = joinpath(ROOT, "dist_last_inj_rate_CVaR_$ts.png")
out_pof  = joinpath(ROOT, "dist_last_inj_rate_POF_$ts.png")

plot_hist(vals_cvar; ttl="Distribution of last_inj_rate (CVaR, ok_final)", outpath=out_cvar, use_logx=USE_LOGX)
plot_hist(vals_pof;  ttl="Distribution of last_inj_rate (POF, ok_final)",  outpath=out_pof,  use_logx=USE_LOGX)

println("Done.")
