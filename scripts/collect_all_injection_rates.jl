using Pkg
Pkg.activate(".")

using Glob
using JLD2
using Printf
using DataFrames
using CSV
using Statistics
using Dates

# ─────────────────────────────────────────────────────────────────────────────
# 路径配置（按你的目录截图）
# ─────────────────────────────────────────────────────────────────────────────
ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"

# 初始注入率（当序列全为 0 时的兜底）
INIT_RATE = 1e-4

# final 缺失时，是否回退到 j=*.jld2 的最大迭代文件
ALLOW_FALLBACK_ITER = true

# ─────────────────────────────────────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────────────────────────────────────

# 解析 sample id（目录名形如 sample=64）
parse_sample_id(path::AbstractString) = begin
    m = match(r"sample=(\d+)", path)
    m === nothing ? missing : parse(Int, m.captures[1])
end

# 给风险目录起一个规范化 tag：POF_eps=... 或 CVaR_g=..._a=...
function normalize_case_tag(risk_dir_name::String)
    # POF: ... eps=0.05 ...
    if occursin("POF", risk_dir_name)
        if (m = match(r"eps\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)) !== nothing
            return "POF_eps=$(m.captures[1])"
        else
            return "POF"  # 保底
        end
    end
    # CVaR: ... alpha=0.05 ... gamma=0.02 ...
    if occursin("CVaR", risk_dir_name)
        ma = match(r"alpha\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)
        mg = match(r"gamma\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)
        a = ma === nothing ? "?" : ma.captures[1]
        g = mg === nothing ? "?" : mg.captures[1]
        return "CVaR_g=$(g)_a=$(a)"
    end
    # fallback
    return risk_dir_name
end

# 在 sample 目录中选择要读取的 jld2 文件：优先 final.jld2，否则最大迭代 j=*.jld2
function pick_jld2_file(sample_dir::String)
    final_path = joinpath(sample_dir, "final.jld2")
    if isfile(final_path)
        return final_path, "final"
    end
    if ALLOW_FALLBACK_ITER
        iter_files = glob("j=*.jld2", sample_dir)
        if !isempty(iter_files)
            # 解析 j=123.jld2 中的 123，取最大的
            iter_id(fp) = (m = match(r"j=(\d+)\.jld2$", fp)) === nothing ? -1 : parse(Int, m.captures[1])
            sorted = sort(iter_files; by=iter_id, rev=true)
            return first(sorted), "iter"
        end
    end
    return nothing, "missing"
end

# 提取最后一个非零注入率（第一列）
function last_nonzero_inj_rate(data::Dict{String,Any}; init_rate::Float64=INIT_RATE)
    inj = data["inj_rate_arr"]
    col1 = inj[:, 1]
    idx = findlast(x -> x != 0, col1)
    return idx === nothing ? init_rate : col1[idx]
end

# ─────────────────────────────────────────────────────────────────────────────
# 主过程：遍历所有 case / sample
# ─────────────────────────────────────────────────────────────────────────────
risk_dirs = sort(filter(isdir, glob(joinpath(ROOT, "*"))))

rows = Vector{NamedTuple}()

for risk_dir in risk_dirs
    risk_name = basename(risk_dir)
    case_tag  = normalize_case_tag(risk_name)

    sample_dirs = sort(filter(isdir, glob(joinpath(risk_dir, "sample=*"))))
    for sdir in sample_dirs
        sample_id = parse_sample_id(sdir)
        chosen, mode = pick_jld2_file(sdir)

        status = ""
        last_inj = NaN
        note = ""
        used_file = ""

        if chosen === nothing
            status = "missing"
            note = "no final.jld2 and no j=*.jld2"
        else
            used_file = chosen
            try
                data = load(chosen)
                last_inj = last_nonzero_inj_rate(data; init_rate=INIT_RATE)
                status = (mode == "final") ? "ok_final" : "ok_iter_fallback"
            catch err
                status = "load_error"
                note = string(err)
            end
        end

        push!(rows, (
            case_tag = case_tag,           # 规范化标签（POF_eps=... / CVaR_g=..._a=...）
            risk_dir = risk_name,          # 原始目录名（完整参数痕迹）
            sample   = sample_id,          # 样本号
            status   = status,             # ok_final / ok_iter_fallback / missing / load_error
            last_inj_rate = last_inj,      # 提取到的最后非零注入率（或 NaN）
            file_used = used_file,         # 实际读取的文件
            note     = note                # 错误或缺失备注
        ))
    end
end

df = DataFrame(rows)
println("Scanned rows: ", nrow(df))

# 只统计成功提值的样本
df_ok = df[df.status .∈ ["ok_final", "ok_iter_fallback"], :]

# 分组统计（每个 case_tag 一行）
function group_stats(df::DataFrame)
    g = groupby(df, :case_tag)
    DataFrame(
        case_tag = combine(g, first => first => :case_tag)[:, :case_tag],
        count    = combine(g, nrow => :count)[:, :count],
        mean     = combine(g, :last_inj_rate => mean => :mean)[:, :mean],
        std      = combine(g, :last_inj_rate => std  => :std)[:, :std],
        ok_final = combine(g, :status => (v->count(==( "ok_final"), v)) => :ok_final)[:, :ok_final],
        ok_iter  = combine(g, :status => (v->count(==( "ok_iter_fallback"), v)) => :ok_iter)[:, :ok_iter]
    )
end

stats = group_stats(df_ok)

# ─────────────────────────────────────────────────────────────────────────────
# 保存结果（CSV + JLD2）
# ─────────────────────────────────────────────────────────────────────────────
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
csv_detail = joinpath(ROOT, "inj_rate_detail_$ts.csv")
csv_stats  = joinpath(ROOT, "inj_rate_stats_$ts.csv")
jld_path   = joinpath(ROOT, "inj_rate_all_$ts.jld2")

CSV.write(csv_detail, df)
CSV.write(csv_stats,  stats)

@tagsave(jld_path, Dict(
    "detail" => df,
    "stats"  => stats,
    "meta"   => (root=ROOT, init_rate=INIT_RATE, allow_iter_fallback=ALLOW_FALLBACK_ITER, timestamp=ts)
))

println("\nSaved:")
println("  detail CSV: ", csv_detail)
println("  stats  CSV: ", csv_stats)
println("  JLD2      : ", jld_path)

println("\n=== SUMMARY ===")
println("Total samples       : ", nrow(df))
println("OK (final)          : ", sum(df.status .== "ok_final"))
println("OK (iter fallback)  : ", sum(df.status .== "ok_iter_fallback"))
println("Missing (no jld2)   : ", sum(df.status .== "missing"))
println("Load errors         : ", sum(df.status .== "load_error"))
