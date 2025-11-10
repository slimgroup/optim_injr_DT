using CSV, DataFrames, Dates, Printf, StatsBase, KernelDensity
using CairoMakie  # 若想交互改用 GLMakie

const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const LOG10_X = true     # KDE 横轴是否用 log10(inj_rate)
const DPI = 200

# ── 选“最新” inj_rate_detail_*.csv ───────────────────────────────────────────
function latest_detail_csv(root::String)
    files = filter(f -> occursin(r"^inj_rate_detail_\d{8}_\d{6}\.csv$", f),
                   readdir(root))
    if !isempty(files)
        # 按文件名时间戳排序
        parse_ts(s) = try
            DateTime(match(r"(\d{8}_\d{6})", s).captures[1], dateformat"yyyymmdd_HHMMSS")
        catch; DateTime(0); end
        files_sorted = sort(files, by=parse_ts)
        return joinpath(root, last(files_sorted))
    else
        # 兜底：按 mtime 排
        allcsv = filter(f -> endswith(f, ".csv") && occursin("inj_rate_detail_", f),
                        readdir(root))
        @assert !isempty(allcsv) "No inj_rate_detail_*.csv found under $root"
        files_sorted = sort(allcsv, by=f -> stat(joinpath(root, f)).mtime)
        return joinpath(root, last(files_sorted))
    end
end

# ── 读取并过滤为 POF + sample∈1..32 + ok_final ───────────────────────────────
function load_pof_detail(root::String)
    path = latest_detail_csv(root)
    @info "Loading detail CSV" path
    df = CSV.read(path, DataFrame)

    # 兼容列名（必须有这些列）
    req = [:case_tag, :sample, :status, :last_inj_rate]
    for c in req
        @assert hasproperty(df, c) "Missing column $(c) in $(path)"
    end

    # 仅 POF
    df = df[occursin.("POF", df.case_tag), :]

    # 仅 sample 1..32
    df = df[in.(df.sample, Ref(collect(SAMPLES))), :]

    # 仅 ok_final
    df = df[df.status .== "ok_final", :]

    # 提取 eps 并排序
    df.eps = map(df.case_tag) do s
        m = match(r"POF_eps\s*=\s*([0-9]*\.?[0-9]+)", String(s))
        m === nothing ? NaN : parse(Float64, m.captures[1])
    end
    df = df[.!isnan.(df.eps), :]
    sort!(df, [:eps, :sample])

    return df
end

# ── 画 KDE 叠加图（可选 log10 横轴） ────────────────────────────────────────────
function plot_kde_overlay(df::DataFrame; log10x::Bool=LOG10_X)
    groups = groupby(df, :eps)
    fig = Figure(resolution=(1000, 600))
    ax = Axis(fig[1,1], xlabel=log10x ? "log10(last_inj_rate)" : "last_inj_rate",
                        ylabel="density", title="POF KDE per eps (samples 1..32)")

    for (i, g) in enumerate(groups)
        x = Vector(g.last_inj_rate)
        x = filter(isfinite, x)
        x = x[x .> 0]  # log10 需要 >0
        if isempty(x); continue; end
        xplot = log10x ? log10.(x) : x
        kd = kde(xplot)
        lines!(ax, kd.x, kd.density, label = @sprintf("eps=%.4g (n=%d)", first(g.eps), length(x)))
    end

    axislegend(ax, position=:rt)
    fig
end

# ── 画 Violin 图（y 轴 log 标度） ──────────────────────────────────────────────
function plot_violin(df::DataFrame)
    # 将 eps 转为有序的分类标签
    eps_sorted = sort(unique(df.eps))
    df.eps_str = @. string(round(df.eps, sigdigits=4))  # "0.01", "0.005", ...
    # 避免 1e-4 这种指数：如果你想指数形式，把 round 改成 @sprintf("%.4g", df.eps)
    fig = Figure(resolution=(1000, 600))
    ax = Axis(fig[1,1], xlabel="POF eps", ylabel="last_inj_rate",
              yscale=log10, title="POF Violin (samples 1..32, log scale)")

    # Makie 没有内置 violin 的分组 DataFrame API，这里手写一版
    xpos = 1:length(eps_sorted)
    for (i, epsv) in enumerate(eps_sorted)
        y = df.last_inj_rate[df.eps .== epsv]
        y = filter(>(0), y)  # 去掉非正
        if isempty(y); continue; end
        # 核密度估计近似 violin
        kd = kde(log10.(y))
        dens = kd.density ./ maximum(kd.density) .* 0.35  # 宽度归一化
        yy = 10 .^ kd.x
        xs_left  = fill(xpos[i], length(yy)) .- dens
        xs_right = fill(xpos[i], length(yy)) .+ dens
        poly!(ax, [xs_left; reverse(xs_right)], [yy; reverse(yy)], color = (:gray, 0.25), strokewidth=0.5)
        # 中位数 / 均值
        med = median(y); mn = mean(y)
        scatter!(ax, [xpos[i]], [med], markersize=8)
        vlines!(ax, xpos[i], minimum(y), maximum(y), linewidth=1)
        hlines!(ax, med, xpos[i]-0.2, xpos[i]+0.2, linewidth=2)
        hlines!(ax, mn, xpos[i]-0.15, xpos[i]+0.15, linestyle=:dash, linewidth=2)
    end
    ax.xticks = (xpos, string.(round.(eps_sorted, sigdigits=4)))
    fig
end

# ── main ─────────────────────────────────────────────────────────────────────
df_pof = load_pof_detail(ROOT)

@info "POF rows (ok_final, samples 1..32)" nrow(df_pof)
@info "EPS set" sort(unique(df_pof.eps))

ts = Dates.format(now(), "yyyymmdd_HHMMSS")

fig1 = plot_kde_overlay(df_pof; log10x=LOG10_X)
save(joinpath(ROOT, "panel_POF_last_inj_rate_KDE_$ts.png"), fig1, px_per_unit = DPI/96)

fig2 = plot_violin(df_pof)
save(joinpath(ROOT, "panel_POF_last_inj_rate_violin_$ts.png"), fig2, px_per_unit = DPI/96)

println("Saved figures:")
println("  panel_POF_last_inj_rate_KDE_$ts.png")
println("  panel_POF_last_inj_rate_violin_$ts.png")
