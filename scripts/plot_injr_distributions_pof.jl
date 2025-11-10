#!/usr/bin/env julia

using CSV, DataFrames, Dates, Printf, StatsBase, KernelDensity
using PyPlot

const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const LOG10_X_FOR_KDE = true   # KDE 横轴是否用 log10
const LOG10_Y_FOR_VIOLIN = true

# ---- 选“最新”的 inj_rate_detail_*.csv ----
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

# ---- 加载 & 过滤为 POF + sample∈1..32 + ok_final ----
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

# ---- 画 KDE 叠加图 ----
function plot_kde_overlay(df::DataFrame; log10x::Bool=LOG10_X_FOR_KDE)
    groups = groupby(df, :eps)
    figure(figsize=(10, 5))
    for g in groups
        epsv = first(g.eps)
        x = collect(skipmissing(g.last_inj_rate))
        x = x[isfinite.(x) .& (x .> 0)]
        isempty(x) && continue
        xplot = log10x ? log10.(x) : x
        kd = kde(xplot)
        plot(kd.x, kd.density, label = @sprintf("eps=%.4g (n=%d)", epsv, length(x)))
    end
    xlabel(log10x ? "log10(last_inj_rate)" : "last_inj_rate")
    ylabel("density")
    title("POF KDE per eps (samples 1..32)")
    legend(loc="upper right")
    tight_layout()
end

# ---- 画 Violin 图（y 轴 log）----
function plot_violin(df::DataFrame; log10y::Bool=LOG10_Y_FOR_VIOLIN)
    eps_vals = sort(unique(df.eps))
    data = Vector{Vector{Float64}}()
    for e in eps_vals
        y = collect(skipmissing(df.last_inj_rate[df.eps .== e]))
        y = y[isfinite.(y) .& (y .> 0)]
        push!(data, y)
    end
    figure(figsize=(10, 5))
    vp = violinplot(data; showmeans=true, showextrema=true, widths=0.8)
    if log10y
        gca().set_yscale("log")
    end
    xticks(1:length(eps_vals), string.(round.(eps_vals, sigdigits=4)))
    xlabel("POF eps")
    ylabel("last_inj_rate" * (log10y ? " (log scale)" : ""))
    title("POF Violin (samples 1..32)")
    grid(true, linestyle="--", alpha=0.3)
    tight_layout()
end

# ---- main ----
df_pof = load_pof_detail(ROOT)
@info "POF rows (ok_final, samples 1..32)" nrow(df_pof)
@info "EPS set" sort(unique(df_pof.eps))
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

plot_kde_overlay(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_KDE_$ts.png"), dpi=200)
close("all")

plot_violin(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_violin_$ts.png"), dpi=200)
close("all")

println("Saved:")
println("  panel_POF_last_inj_rate_KDE_$ts.png")
println("  panel_POF_last_inj_rate_violin_$ts.png")
