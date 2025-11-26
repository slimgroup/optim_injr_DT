# scripts/compare_injrate.jl
using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2, Printf
using PyPlot
using ArgParse

const INJ_EPS_DEFAULT = 1e-9

# ------------------------ CLI ------------------------
function parse_cmd()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--run1";   help = "Path to RUN-1 (final.jld2 / sample dir / case dir)"; required = true
        "--run2";   help = "Path to RUN-2 (final.jld2 / sample dir / case dir)"; required = true
        "--label1"; help = "Label for RUN-1"; default = "POF"
        "--label2"; help = "Label for RUN-2"; default = "CVaR"
        "--out";    help = "Bar chart output path"; default = "injrate_compare.png"
        "--traj";   help = "Trajectory chart output path"; default = "injrate_trajectories.png"
        "--inj_eps"; help = "Threshold to pick last positive injection rate"; arg_type=Float64; default = INJ_EPS_DEFAULT
    end
    return parse_args(s)
end

# --------------------- Finder helpers -----------------
function collect_final_candidates(path::String)::Vector{String}
    cands = String[]
    if endswith(path, "final.jld2") && isfile(path)
        push!(cands, path); return cands
    end
    if isdir(path)
        direct = joinpath(path, "final.jld2")
        if isfile(direct); push!(cands, direct); end
        for (root, _, files) in walkdir(path)
            for f in files
                if f == "final.jld2"
                    push!(cands, joinpath(root, f))
                end
            end
        end
    end
    return cands
end

function pick_best_final(cands::Vector{String})::String
    @assert !isempty(cands) "No final.jld2 found."
    function score(p::String)
        s1 = occursin(r"sample=1($|/)", p)      ? 0 :
             occursin(r"sample=000001($|/)", p) ? 1 : 2
        return (s1, length(p), p)
    end
    sort!(cands; by=score)
    return first(cands)
end

function resolve_final(path::String)::String
    cands = collect_final_candidates(path)
    @assert !isempty(cands) "not found: final.jld2 under $path"
    return pick_best_final(cands)
end

# ----------------------- Utils ------------------------
# pick the last element > eps; if none, return last element and its index
function last_positive(x::Vector{Float64}; eps::Float64=INJ_EPS_DEFAULT)
    idx = findlast(>(eps), x)
    if idx === nothing
        return (x[end], length(x))
    else
        return (x[idx], idx)
    end
end

# ----------------------- Loader -----------------------
function load_final_any(pathlike::String; inj_eps::Float64=INJ_EPS_DEFAULT)
    f = resolve_final(pathlike)
    d = JLD2.load(f)

    inj_rate_arr = d["inj_rate_arr"]
    @assert size(inj_rate_arr, 2) ≥ 1 "inj_rate_arr has no columns"
    traj  = vec(inj_rate_arr[:, 1])
    inj_final, idx_final = last_positive(traj; eps=inj_eps)

    pof_last  = let v = get(d, "pof_hard_iter", nothing); v === nothing ? NaN : v[end]; end
    cvar_last = let v = get(d, "cvar_iter",      nothing); v === nothing ? NaN : v[end]; end
    meta = haskey(d, "meta") ? d["meta"] : nothing
    return (inj=inj_final, idx=idx_final, traj=traj, pof=pof_last, cvar=cvar_last, meta=meta, file=f)
end

# ----------------------- Main -------------------------
function main()
    args = parse_cmd()

    A = load_final_any(args["run1"]; inj_eps=args["inj_eps"])
    B = load_final_any(args["run2"]; inj_eps=args["inj_eps"])

    @printf "[%s]\n" args["label1"]
    @printf "  final injection rate (last>%.1e) = %.10g  @iter=%d\n" args["inj_eps"] A.inj A.idx-1
    println("  traj min/max = ", minimum(A.traj), " / ", maximum(A.traj))
    if !isnan(A.pof);  @printf "  POF(hard)  = %.6g %%\n" (100A.pof); end
    if !isnan(A.cvar); @printf "  CVaR       = %.6g\n"    A.cvar;     end
    println("  picked file → ", A.file)

    @printf "[%s]\n" args["label2"]
    @printf "  final injection rate (last>%.1e) = %.10g  @iter=%d\n" args["inj_eps"] B.inj B.idx-1
    println("  traj min/max = ", minimum(B.traj), " / ", maximum(B.traj))
    if !isnan(B.pof);  @printf "  POF(hard)  = %.6g %%\n" (100B.pof); end
    if !isnan(B.cvar); @printf "  CVaR       = %.6g\n"    B.cvar;     end
    println("  picked file → ", B.file)

    Δ = A.inj - B.inj
    @printf "Δ(injection rate) = %+.10g   (%s - %s)\n" Δ args["label1"] args["label2"]

    # 1) 条形对比
    fig, ax = subplots(figsize=(5,4))
    ax.bar(1:2, [A.inj, B.inj])
    ax.set_xticks(1:2, [args["label1"], args["label2"]])
    ax.set_ylabel("Final injection rate")
    ax.set_title("Final injection rate: $(args["label1"]) vs $(args["label2"])")
    plt.tight_layout(); savefig(args["out"]); close(fig)
    println("Saved → ", args["out"])

    # 2) 轨迹对比 + 标注选中的“最后非零”点
    nA = length(A.traj); nB = length(B.traj)
    fig, ax = subplots(figsize=(6,4))
    ax.plot(0:nA-1, A.traj, label=args["label1"])
    ax.plot(0:nB-1, B.traj, label=args["label2"])
    ax.plot(A.idx-1, A.traj[A.idx], "o", label="$(args["label1"]) final>0")
    ax.plot(B.idx-1, B.traj[B.idx], "o", label="$(args["label2"]) final>0")
    ax.set_xlabel("iteration"); ax.set_ylabel("injection rate")
    ax.set_title("Injection-rate trajectories (marked = last > $(args["inj_eps"]))")
    ax.legend(); plt.tight_layout()
    savefig(args["traj"]); close(fig)
    println("Saved → ", args["traj"])
end

main()
