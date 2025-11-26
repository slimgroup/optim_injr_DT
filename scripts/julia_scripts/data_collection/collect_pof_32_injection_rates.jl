#!/usr/bin/env julia
# =============================================================================
# Collect POF cases only, sample range 1..32
# Rules:
# - Assumes sample=1..32 directories exist under each case
# - Only reads and counts if final.jld2 exists in sample directory, otherwise marks as missing
# - Strictly prohibits using j=*.jld2 fallback
# Exports:
#   1) pof_inj_rate_detail_*.csv              Per-sample details (including missing/load_error)
#   2) pof_inj_rate_stats_*.csv               Mean/variance for OK samples only
#   3) pof_inj_rate_missing_*.csv             Missing list aggregated by normalized tag (case_tag)
#   4) pof_inj_rate_load_errors_*.csv         Load error list aggregated by normalized tag (case_tag)
#   5) pof_inj_rate_all_*.jld2                Package containing all above content
#   6) pof_inj_rate_missing_by_dir_*.csv       Missing aggregated by directory (risk_dir)
#   7) pof_inj_rate_load_errors_by_dir_*.csv  Load errors aggregated by directory (risk_dir)
# =============================================================================

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using DataFrames
using CSV
using Statistics
using Dates
using Printf

# ─────────────────────────────────────────────────────────────────────────────
# Parameters
# ─────────────────────────────────────────────────────────────────────────────
const ROOT      = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES   = 1:32           # Only collect 1..32
const INIT_RATE = 1e-4           # Fallback value if inj_rate_arr is all zeros

# ─────────────────────────────────────────────────────────────────────────────
# Utility functions
# ─────────────────────────────────────────────────────────────────────────────

# Normalize case tag (extract only POF eps; supports scientific notation)
function normalize_case_tag(risk_dir_name::String)
    if occursin("POF", risk_dir_name)
        # Supports 0.0005, .005, 1e-3, 1E-03, etc.
        if (m = match(r"eps\s*=\s*((?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+\-]?\d+)?)", risk_dir_name)) !== nothing
            return "POF_eps=$(m.captures[1])"
        else
            return "POF"
        end
    end
    return risk_dir_name
end

# Compatible with String/Symbol keys
@inline function _get(data, k::AbstractString)
    if haskey(data, k)
        return data[k]
    elseif haskey(data, Symbol(k))
        return data[Symbol(k)]
    else
        return nothing
    end
end

# 取第一列（容忍向量或矩阵；若是一维向量就直接用）
function _first_column(v)
    if ndims(v) == 1
        return collect(v)
    elseif ndims(v) == 2
        return vec(view(v, :, 1))
    else
        error("inj_rate_arr has unexpected dimension: $(ndims(v))")
    end
end

# 读取最后一个非零注入率（第一列），忽略 missing/NaN；若全零/不存在则用 INIT_RATE
function last_nonzero_inj_rate(data; init_rate::Float64=INIT_RATE)
    raw = _get(data, "inj_rate_arr")
    raw === nothing && return init_rate
    col1 = _first_column(raw)
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? init_rate : clean[idx]
end

# 分组统计（仅 OK 样本），单样本 std=0.0
function group_stats(df::DataFrame)
    g = groupby(df, :case_tag)
    combine(g,
        nrow => :count,
        :last_inj_rate => mean => :mean,
        :last_inj_rate => (v -> (length(v) > 1 ? std(v) : 0.0)) => :std,
    )
end

# 通用汇总：按给定列分组，汇总缺失 sample 列表；count=length(samples)
function summarize_samples_by(df_sub::DataFrame, group_cols::Vector{Symbol})
    if nrow(df_sub) == 0
        return DataFrame([c => Vector{String}() for c in group_cols if c != :sample]...,
                         :count => Int[], :samples => Vector{Vector{Int}}[], :samples_str => String[])
    end
    g = groupby(df_sub, group_cols)
    tmp = combine(g, :sample => (v -> sort(collect(skipmissing(v)))) => :samples)
    tmp.count = length.(tmp.samples)
    tmp.samples_str = join.(string.(tmp.samples), ", ")
    select!(tmp, vcat(group_cols, [:count, :samples, :samples_str]))
    sort!(tmp, group_cols)
    return tmp
end

# 兼容旧名：按标签(case_tag)汇总
summarize_samples(df_sub::DataFrame) = summarize_samples_by(df_sub, [:case_tag])

# ─────────────────────────────────────────────────────────────────────────────
# 主过程（仅 POF 目录）
# ─────────────────────────────────────────────────────────────────────────────
risk_dirs = filter(d ->
    isdir(joinpath(ROOT, d)) &&
    occursin("POF", d) &&         # 只收集 POF
    d != "geo" &&                 # 跳过 geo
    !startswith(d, ".")           # 跳过隐藏目录
, readdir(ROOT))
sort!(risk_dirs)

rows = NamedTuple[]

for risk_name in risk_dirs
    case_tag = normalize_case_tag(risk_name)
    risk_dir = joinpath(ROOT, risk_name)

    for s in SAMPLES
        sdir = joinpath(risk_dir, "sample=$(s)")
        final_path = joinpath(sdir, "final.jld2")

        if isfile(final_path)
            status = "ok_final"
            note = ""
            last_inj = NaN
            try
                data = load(final_path)
                last_inj = last_nonzero_inj_rate(data; init_rate=INIT_RATE)
            catch err
                status = "load_error"
                note = sprint(showerror, err)
            end
            push!(rows, (
                case_tag = case_tag,
                risk_dir = risk_name,
                sample   = s,
                status   = status,             # ok_final / load_error
                last_inj_rate = last_inj,
                file_used = final_path,
                note = note
            ))
        else
            push!(rows, (
                case_tag = case_tag,
                risk_dir = risk_name,
                sample   = s,
                status   = "missing",
                last_inj_rate = NaN,
                file_used = "",
                note = "no final.jld2"
            ))
        end
    end
end

df = DataFrame(rows)
println("Scanned rows (POF cases × samples in 1..32): ", nrow(df))

# 统计（仅 OK）
df_ok = df[df.status .== "ok_final", :]
stats = group_stats(df_ok)

# 缺失与加载错误明细
df_missing = df[df.status .== "missing", [:case_tag, :sample, :risk_dir, :status, :note]]
df_loaderr = df[df.status .== "load_error", [:case_tag, :sample, :risk_dir, :status, :note]]

# 汇总：按标签
missing_summary_tag = summarize_samples(df_missing)
loaderr_summary_tag = summarize_samples(df_loaderr)

# 汇总：按目录
missing_summary_dir = summarize_samples_by(df_missing, [:risk_dir])
loaderr_summary_dir = summarize_samples_by(df_loaderr, [:risk_dir])

# 也可查看 标签+目录（仅入包与打印，不额外导出）
missing_summary_both = summarize_samples_by(df_missing, [:case_tag, :risk_dir])
loaderr_summary_both = summarize_samples_by(df_loaderr, [:case_tag, :risk_dir])

# ─────────────────────────────────────────────────────────────────────────────
# 保存（带 pof_ 前缀）
# ─────────────────────────────────────────────────────────────────────────────
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
csv_detail          = joinpath(ROOT, "pof_inj_rate_detail_$ts.csv")
csv_stats           = joinpath(ROOT, "pof_inj_rate_stats_$ts.csv")
csv_missing         = joinpath(ROOT, "pof_inj_rate_missing_$ts.csv")          # by tag
csv_loaderr         = joinpath(ROOT, "pof_inj_rate_load_errors_$ts.csv")      # by tag
csv_missing_by_dir  = joinpath(ROOT, "pof_inj_rate_missing_by_dir_$ts.csv")   # by dir
csv_loaderr_by_dir  = joinpath(ROOT, "pof_inj_rate_load_errors_by_dir_$ts.csv")
jld_path            = joinpath(ROOT, "pof_inj_rate_all_$ts.jld2")

CSV.write(csv_detail, df)
CSV.write(csv_stats,  stats)
CSV.write(csv_missing, missing_summary_tag)
CSV.write(csv_loaderr, loaderr_summary_tag)
CSV.write(csv_missing_by_dir, missing_summary_dir)
CSV.write(csv_loaderr_by_dir, loaderr_summary_dir)

@tagsave(jld_path, Dict(
    "detail"       => df,
    "stats"        => stats,
    "missing_tag"  => missing_summary_tag,
    "loaderr_tag"  => loaderr_summary_tag,
    "missing_dir"  => missing_summary_dir,
    "loaderr_dir"  => loaderr_summary_dir,
    "missing_both" => missing_summary_both,
    "loaderr_both" => loaderr_summary_both,
    "meta" => (root=ROOT, samples=collect(SAMPLES), timestamp=ts, only="POF")
); safe=true)

# ─────────────────────────────────────────────────────────────────────────────
# 终端输出
# ─────────────────────────────────────────────────────────────────────────────
println("\nSaved:")
println("  detail CSV            : ", csv_detail)
println("  stats  CSV            : ", csv_stats)
println("  missing (by tag) CSV  : ", csv_missing)
println("  loaderr (by tag) CSV  : ", csv_loaderr)
println("  missing (by dir) CSV  : ", csv_missing_by_dir)
println("  loaderr (by dir) CSV  : ", csv_loaderr_by_dir)
println("  JLD2                  : ", jld_path)

println("\n=== SUMMARY (POF, samples 1..32) ===")
println("OK (final)        : ", sum(df.status .== "ok_final"))
println("Missing (no final): ", sum(df.status .== "missing"))
println("Load errors       : ", sum(df.status .== "load_error"))

println("\n=== MISSING SAMPLES BY DIRECTORY (final.jld2 absent) ===")
if nrow(missing_summary_dir) == 0
    println("No missing samples.")
else
    for r in eachrow(missing_summary_dir)
        @printf("%-70s | count=%-3d | samples=[%s]\n",
                r.risk_dir, r.count, r.samples_str)
    end
end

println("\n=== MISSING SAMPLES BY (case_tag, risk_dir) ===")
if nrow(missing_summary_both) == 0
    println("No missing samples.")
else
    for r in eachrow(missing_summary_both)
        @printf("%-22s | %-70s | count=%-3d | samples=[%s]\n",
                r.case_tag, r.risk_dir, r.count, r.samples_str)
    end
end

println("\n=== LOAD ERRORS BY DIRECTORY (rare) ===")
if nrow(loaderr_summary_dir) == 0
    println("No load errors.")
else
    for r in eachrow(loaderr_summary_dir)
        @printf("%-70s | count=%-3d | samples=[%s]\n",
                r.risk_dir, r.count, r.samples_str)
    end
end
