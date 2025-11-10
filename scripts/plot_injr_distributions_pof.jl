#!/usr/bin/env julia

using CSV, DataFrames, Dates, Printf
using PyPlot

const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:32
const NBINS   = 12        # 直方图 bins
const DPI     = 200

# ── 选“最新”的 inj_rate_detail_*.csv ─────────────────────────────────────────
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

# ── 加载 & 过滤为 POF + sample∈1..32 + ok_final ──────────────────────────────
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

# ── 画直方图面板（像你截图那样） ──────────────────────────────────────────────
function plot_hist_panels(df::DataFrame; nbins::Int=NBINS)
    eps_vals = sort(unique(df.eps))
    n = length(eps_vals)
    nrows = ceil(Int, n/3)           # 每行 3 个子图（可改成 2 或 4）
    ncols = min(n, 3)

    fig, axes = subplots(nrows, ncols; figsize=(12, 6))
    if nrows == 1 && ncols == 1
        axes = [axes]
    elseif nrows == 1
        axes = collect(axes)         # 1×N
    elseif ncols == 1
        axes = collect(axes)         # N×1
    else
        axes = vec(axes)             # 展平成一维
    end

    global_xmax = maximum(df.last_inj_rate[isfinite.(df.last_inj_rate)])
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

        ax.hist(x; bins=nbins, alpha=0.8, edgecolor="none")
        ax.set_title(@sprintf("POF_eps=%.4g", epsv))
        ax.grid(true, linestyle="--", alpha=0.3)
        ax.set_xlim(0, global_xmax * 1.05)
        # 只有左列加 y label，底行加 x label
        # （让版式更干净）
    end

    # 清掉多余空轴
    for j in (length(eps_vals)+1):length(axes)
        axes[j].axis("off")
    end

    fig.suptitle("POF: Histogram of last_inj_rate by case (frequency, ok_final)", y=0.98, fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    return fig
end

# ── main ─────────────────────────────────────────────────────────────────────
df_pof = load_pof_detail(ROOT)
@info "POF rows (ok_final, samples 1..32)" nrow(df_pof)
@info "EPS set" sort(unique(df_pof.eps))
ts = Dates.format(now(), "yyyymmdd_HHMMSS")

fig = plot_hist_panels(df_pof)
savefig(joinpath(ROOT, "panel_POF_last_inj_rate_hist_$ts.png"), dpi=DPI)
close("all")
println("Saved: panel_POF_last_inj_rate_hist_$ts.png")
