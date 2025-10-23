#!/usr/bin/env julia
# =============================================================================
# 规则：
# - 假定每个 case 下 sample=1..64 目录都存在
# - 仅当 sample 目录下存在 final.jld2 才读取并统计，否则记为 missing
# - 严禁使用 j=*.jld2 回退
# 导出：
#   1) inj_rate_detail_*.csv        逐样本明细（含 missing/load_error）
#   2) inj_rate_stats_*.csv         仅 OK 样本的均值/方差
#   3) inj_rate_missing_*.csv       按 case 汇总的 missing 样本列表
#   4) inj_rate_load_errors_*.csv   罕见：读取出错样本列表
#   5) inj_rate_all_*.jld2          打包以上内容
# =============================================================================

using Pkg
Pkg.activate(".")

using JLD2
using DataFrames
using CSV
using Statistics
using Dates
using Printf
using DrWatson

# ─────────────────────────────────────────────────────────────────────────────
# 参数
# ─────────────────────────────────────────────────────────────────────────────
const ROOT    = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES = 1:64
const INIT_RATE = 1e-4  # 若 inj_rate_arr 全 0 的兜底值

# ─────────────────────────────────────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────────────────────────────────────

# 规范化 case 标签
function normalize_case_tag(risk_dir_name::String)
    if occursin("POF", risk_dir_name)
        if (m = match(r"eps\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)) !== nothing
            return "POF_eps=$(m.captures[1])"
        else
            return "POF"
        end
    end
    if occursin("CVaR", risk_dir_name)
        ma = match(r"alpha\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)
        mg = match(r"gamma\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)
        a = ma === nothing ? "?" : ma.captures[1]
        g = mg === nothing ? "?" : mg.captures[1]
        return "CVaR_g=$(g)_a=$(a)"
    end
    return risk_dir_name
end

# 读取最后一个非零注入率（第一列）
function last_nonzero_inj_rate(data::Dict{String,Any}; init_rate::Float64=INIT_RATE)
    if !haskey(data, "inj_rate_arr")
        return init_rate
    end
    inj = data["inj_rate_arr"]
    col1 = inj[:, 1]
    idx = findlast(x -> x != 0, col1)
    return idx === nothing ? init_rate : col1[idx]
end

# 分组统计（仅 OK 样本）
function group_stats(df::DataFrame)
    g = groupby(df, :case_tag)
    combine(g,
        nrow => :count,
        :last_inj_rate => mean => :mean,
        :last_inj_rate => std  => :std,
    )
end

# 按 case 汇总样本编号列表
function summarize_samples(df_sub::DataFrame)
    if nrow(df_sub) == 0
        return DataFrame(case_tag=String[], count=Int[], samples=Vector{Vector{Int}}[])
    end
    g = groupby(df_sub, :case_tag)
    combine(g,
        :sample => (v -> sort(collect(skipmissing(v)))) => :samples,
        nrow    => :count,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# 主过程
# ─────────────────────────────────────────────────────────────────────────────
# 列出 ROOT 下的所有 case 目录（仅目录）
risk_dirs = filter(d -> isdir(joinpath(ROOT, d)), readdir(ROOT))
sort!(risk_dirs)

rows = NamedTuple[]

for risk_name in risk_dirs
    case_tag = normalize_case_tag(risk_name)
    risk_dir = joinpath(ROOT, risk_name)

    for s in SAMPLES
        sdir = joinpath(risk_dir, "sample=$(s)")
        final_path = joinpath(sdir, "final.jld2")

        if isfile(final_path)
            # OK：读取 final.jld2
            status = "ok_final"
            note = ""
            last_inj = NaN
            try
                data = load(final_path)
                last_inj = last_nonzero_inj_rate(data; init_rate=INIT_RATE)
            catch err
                status = "load_error"
                note = string(err)
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
            # final.jld2 缺失 → 记为 missing
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
println("Scanned rows (cases × samples in 1..64): ", nrow(df))

# 统计（仅 OK）
df_ok = df[df.status .== "ok_final", :]
stats = group_stats(df_ok)

# 缺失与加载错误汇总
df_missing = df[df.status .== "missing", [:case_tag, :sample, :risk_dir, :status, :note]]
df_loaderr = df[df.status .== "load_error", [:case_tag, :sample, :risk_dir, :status, :note]]

missing_summary = summarize_samples(df_missing)
loaderr_summary = summarize_samples(df_loaderr)

# ─────────────────────────────────────────────────────────────────────────────
# 保存
# ─────────────────────────────────────────────────────────────────────────────
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
csv_detail  = joinpath(ROOT, "inj_rate_detail_$ts.csv")
csv_stats   = joinpath(ROOT, "inj_rate_stats_$ts.csv")
csv_missing = joinpath(ROOT, "inj_rate_missing_$ts.csv")
csv_loaderr = joinpath(ROOT, "inj_rate_load_errors_$ts.csv")
jld_path    = joinpath(ROOT, "inj_rate_all_$ts.jld2")

CSV.write(csv_detail, df)
CSV.write(csv_stats,  stats)
CSV.write(csv_missing, missing_summary)
CSV.write(csv_loaderr, loaderr_summary)

@tagsave(jld_path, Dict(
    "detail"       => df,
    "stats"        => stats,
    "missing"      => missing_summary,
    "load_errors"  => loaderr_summary,
    "meta" => (root=ROOT, samples=collect(SAMPLES), timestamp=ts)
))

# ─────────────────────────────────────────────────────────────────────────────
# 终端输出
# ─────────────────────────────────────────────────────────────────────────────
println("\nSaved:")
println("  detail CSV      : ", csv_detail)
println("  stats  CSV      : ", csv_stats)
println("  missing CSV     : ", csv_missing)
println("  load errors CSV : ", csv_loaderr)
println("  JLD2            : ", jld_path)

println("\n=== SUMMARY (samples 1..64) ===")
println("OK (final)        : ", sum(df.status .== "ok_final"))
println("Missing (no final): ", sum(df.status .== "missing"))
println("Load errors       : ", sum(df.status .== "load_error"))

println("\n=== MISSING SAMPLES BY CASE (final.jld2 absent) ===")
if nrow(missing_summary) == 0
    println("No missing samples.")
else
    for r in eachrow(missing_summary)
        println(@sprintf("%-22s | count=%-3d | samples=[%s]",
                         r.case_tag, r.count, join(r.samples, ", ")))
    end
end

println("\n=== LOAD ERRORS BY CASE (rare) ===")
if nrow(loaderr_summary) == 0
    println("No load errors.")
else
    for r in eachrow(loaderr_summary)
        println(@sprintf("%-22s | count=%-3d | samples=[%s]",
                         r.case_tag, r.count, join(r.samples, ", ")))
    end
end
