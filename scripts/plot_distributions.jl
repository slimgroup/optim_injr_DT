#!/usr/bin/env julia
using Pkg
Pkg.activate(".")

using CSV, DataFrames, Dates, StatsBase
using PyPlot

# ====== 配置 ======
const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const USE_LOGX = false  # 如注入率跨数量级可改为 true

# ====== 工具：找到最新 inj_rate_detail_*.csv ======
function latest_detail_csv(root::AbstractString)
    files = filter(f -> occursin(r"^inj_rate_detail_.*\.csv$", f), readdir(root))
    isempty(files) && error("找不到 inj_rate_detail_*.csv，请先运行收集脚本。")
    sort(files)[end] |> x -> joinpath(root, x)
end

detail_csv = latest_detail_csv(ROOT)
println("Using detail CSV: ", detail_csv)

df = CSV.read(detail_csv, DataFrame)

# 只用 ok_final
df_ok = df[df.status .== "ok_final", :]

# 按 case 类型拆分
is_cvar = startswith.((df_ok.case_tag,), "CVaR")
is_pof  = startswith.((df_ok.case_tag,), "POF")

vals_cvar = skipmissing(df_ok.last_inj_rate[is_cvar])
vals_pof  = skipmissing(df_ok.last_inj_rate[is_pof])

println("Counts -> CVaR: ", length(vals_cvar), " ; POF: ", length(vals_pof))

# ====== 画图函数 ======
function plot_hist(vals; title::AbstractString, outpath::AbstractString, use_logx::Bool=false)
    if isempty(vals)
        @warn "No data to plot for $title"
        return
    end
    fig = figure(figsize=(6,4))
    ax = gca()

    x = collect(vals)
    if use_logx
        x = filter(>(0.0), x)
        if isempty(x)
            @warn "All values non-positive for $title under log scale, skip."
            return
        end
        hist(x, bins=30, density=true, alpha=0.8)
        xscale("log")
    else
        hist(x, bins=30, density=true, alpha=0.8)
    end

    xlabel(use_logx ? "last_inj_rate (log scale)" : "last_inj_rate")
    ylabel("density")
    title(title)
    grid(true, linestyle="--", linewidth=0.5, alpha=0.6)
    tight_layout()
    savefig(outpath, dpi=200)
    close(fig)
    println("Saved: ", outpath)
end

# ====== 出图 ======
out_cvar = joinpath(ROOT, "dist_last_inj_rate_CVaR.png")
out_pof  = joinpath(ROOT, "dist_last_inj_rate_POF.png")

plot_hist(vals_cvar; title="Distribution of last_inj_rate (CVaR, ok_final)", outpath=out_cvar, use_logx=USE_LOGX)
plot_hist(vals_pof;  title="Distribution of last_inj_rate (POF, ok_final)",  outpath=out_pof,  use_logx=USE_LOGX)

println("Done.")
