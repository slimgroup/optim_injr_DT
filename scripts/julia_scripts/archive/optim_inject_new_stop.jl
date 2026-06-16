# Backtracking line search gradient descent optimization solver for geological
# carbon storage. Maximize injected CO2 integral + risk penalties (no log barrier).
# Supports POF/CVaR soft penalties AND hard constraints. Persists r_vals / w_vals.
# Adds: zero-baseline penalties, penalty breakdown logging, lambda suggestions, plots,
# configurable kappa for softplus, optional softplus demo plot.

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
using JutulDarcyRules
using LinearAlgebra
using PyPlot
using SlimOptim
using JLD2
using Random
using PyCall
using SlimPlotting
using ArgParse
@pyimport cmasher
using StatsBase
using Dates
using Printf

# ─────────────────────────────────────────────────────────────────────────────
# PyCall setup
function setup_pycall()
    if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
        println("PACE environment detected. Setting PyCall Python path...")
        ENV["PYTHON"] = "/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python"
        Pkg.build("PyCall")
    else
        println("Non-PACE environment detected. Skipping PyCall config.")
    end
end
setup_pycall()

# ─────────────────────────────────────────────────────────────────────────────
# CLI
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--idx_num", "-i"
            help = "Index (1-based) into the provided set; selects the geological sample to run"
            arg_type = Int
            default = 128

        "--alpha"
            help = "Tail level for space–time CVaR (e.g., 0.05)"
            arg_type = Float64
            default = 0.05

        # Risk toggles and weights
        "--use_pof"
            help = "Include smoothed POF penalty in the objective"
            action = :store_true

        "--lambda_pof"
            help = "Weight λ_pof for POF penalty"
            arg_type = Float64
            default = 0.0

        "--eps_pof"
            help = "Target POF ε (e.g., 0.01 == 1%)"
            arg_type = Float64
            default = 0.01

        "--tau_pof"
            help = "Smoothing temperature τ for POF (on r)"
            arg_type = Float64
            default = 0.05

        "--use_cvar"
            help = "Include CVaR penalty in the objective"
            action = :store_true

        "--lambda_cvar"
            help = "Weight λ_cvar for CVaR penalty"
            arg_type = Float64
            default = 0.0

        "--gamma_cvar"
            help = "Allowable CVaR level γ (often 0)"
            arg_type = Float64
            default = 0.0

        "--risk_mode"
            help = "Risk margin mode: relative | window"
            arg_type = String
            default = "relative"

        "--weight_mode"
            help = "Space–time weighting: voltime (default) | uniform (1/M)"
            arg_type = String
            default = "voltime"

        "--cvar_soft"
            help = "Use softplus-smoothed RU CVaR (better FD stability)"
            action = :store_true

        # hard constraints
        "--pof_as_constraint"
            help = "Treat POF as a hard constraint: if metric>ε, objective=Inf"
            action = :store_true

        "--cvar_as_constraint"
            help = "Treat CVaR as a hard constraint: if CVaR>γ, objective=Inf"
            action = :store_true

        # kappa 与演示
        "--kappa_pof"
            help = "κ for POF softplus (zero-baseline)"
            arg_type = Float64
            default = 50.0

        "--kappa_cvar"
            help = "κ for CVaR softplus (zero-baseline)"
            arg_type = Float64
            default = 50.0

        "--plot_softplus_demo"
            help = "Save a demo plot of zero-baseline softplus for given kappas"
            action = :store_true

        # λ 标定（可选）
        "--target_share"
            help = "目标：软罚在边界附近占 |base| 的比例（例如 0.01 = 1%）"
            arg_type = Float64
            default = 0.01

        "--delta_ref"
            help = "用于标定 λ 的代表性小违约量 δ（例如 0.01）"
            arg_type = Float64
            default = 0.01

        # 优化/保存/出图
        "--niterations"
            help = "Max GD iterations"
            arg_type = Int
            default = 20

        "--inj_start"
            help = "★ 起始注入速率（取代全局 init_inj_rate）"
            arg_type = Float64
            default = 0.0001

        "--inj_guess"
            help = "初始猜测注入速率（上限端）"
            arg_type = Float64
            default = 0.05

        "--save_plots"
            help = "Save plots during optimization"
            action = :store_true

        "--plot_stride"
            help = "Plot every k iterations"
            arg_type = Int
            default = 5

        "--save_states"
            help = "Persist sat/pres/BHP arrays each save interval"
            action = :store_true

        "--save_every"
            help = "Save JLD2 every k iterations"
            arg_type = Int
            default = 1

        "--grad_forward"
            help = "Use forward-diff FD gradient (default central)"
            action = :store_true
    end

    return parse_args(s)
end

# ─────────────────────────────────────────────────────────────────────────────
# Smooth helpers
σ(u) = 1.0 / (1.0 + exp(-u))

function softplus(x; κ::Float64 = 50.0)
    y = κ * x
    y = clamp(y, -50.0, 50.0)
    return log1p(exp(y)) / κ
end

@inline function dsoftplus(x; κ::Float64=50.0)
    y = clamp(κ*x, -50.0, 50.0)
    return 1.0/(1.0 + exp(-y))
end

# ─────────────────────────────────────────────────────────────────────────────
# Plotting helpers
# 关键：pres_thres 需要 p0_ref（参考水压）作为关键字参数传入
function plot_state(data, title_str, file_suffix, plot_path, sample, h, n, d, type, iter=-1, threshold=-1; p0_ref=nothing)
    rc("font", family="serif")
    rc("xtick", labelsize=15); rc("ytick", labelsize=15)
    fig, ax = subplots(figsize=(10, 5))
    im_ratio = n[3] * d[3]/(n[1] * d[1])

    if type == "perm"
        im_K = ax.imshow(data, vmin=0, vmax=4, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="cet_rainbow4")
        clb = fig.colorbar(im_K, fraction=0.046*im_ratio, pad=0.04)
        clb.ax.set_title("Md", fontsize=15)
        clb.set_ticks(log10.([1, 10, 1000])); clb.set_ticklabels(["1", "1e1", "1e3"])
    elseif type == "pres"
        im_pres = ax.imshow(data / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="cet_CET_L3_r")
        clb = fig.colorbar(im_pres, fraction=0.046 * im_ratio, pad=0.04); clb.ax.set_title("MPa", fontsize=15)
    elseif type == "pres_thres"
        @assert p0_ref !== nothing "plot_state: p0_ref must be provided for type='pres_thres'"
        data_diff = data - p0_ref
        maxdiff = max(1e-9, maximum(data_diff))
        lower_cmap_size = clamp(round(Int, 256 * threshold * 1e6 / maxdiff), 0, 256)
        upper_cmap_size = 256 - lower_cmap_size

        if lower_cmap_size >= 256
            im = ax.imshow(data_diff / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h),
                           cmap="Blues", vmin=0, vmax=threshold)
            clb = fig.colorbar(im, fraction=0.046*im_ratio, pad=0.04, extend="max")
            clb.set_ticks([0, threshold]); clb.set_ticklabels(["0.0", string(threshold)])
        else
            np = pyimport("numpy")
            lower_cmap = PyPlot.cm.Blues(np.linspace(0, 1, lower_cmap_size))
            upper_cmap = transpose(repeat(collect(PyPlot.cm.colors.to_rgba("red")), outer=(1, upper_cmap_size)))
            colors = vcat(lower_cmap, upper_cmap)

            bounds = vcat(
                range(0, threshold; length=lower_cmap_size+1),
                range(threshold, maximum(data_diff)/1e6; length=upper_cmap_size+1)[2:end]
            )
            norm = PyPlot.matplotlib.colors.BoundaryNorm(bounds, size(colors, 1))
            im = ax.imshow(data_diff / 1e6,
                           extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h),
                           cmap=PyPlot.cm.colors.ListedColormap(colors), norm=norm)
            clb = fig.colorbar(im, fraction=0.046*im_ratio, pad=0.04, extend="max")
            clb.set_ticks([0, threshold, maximum(data_diff)/1e6])
            clb.set_ticklabels(["0.0", string(threshold), ">" * string(threshold)])
        end
        clb[:ax][:set_title]("MPa", fontsize=15)
    elseif type == "sat"
        im_state = ax.imshow(data, vmin=0, vmax=1, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap=cmasher.rainforest_r)
        clb = fig.colorbar(im_state, fraction=0.046 * im_ratio, pad=0.04)
    else
        im_state = ax.imshow(data, vmin=0, vmax=1, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h))
        clb = fig.colorbar(im_state, fraction=0.046 * im_ratio, pad=0.04)
    end

    ax.set_title(title_str, fontsize=20)
    ax.set_xlabel("X[m]", fontsize=15); ax.set_ylabel("Depth[m]", fontsize=15)
    plt.tight_layout(pad=0.6, w_pad=0.5, h_pad=1.0)

    if iter < 0
        safesave(joinpath(plot_path, savename(@strdict(sample); digits=6) * file_suffix), fig)
    else
        safesave(joinpath(plot_path, savename(@strdict(sample, iter); digits=6) * file_suffix), fig)
    end
    close(fig)
end

function plot_softplus_demo!(plot_path; κ_pof::Float64, κ_cvar::Float64)
    xs = collect(range(-0.05, 0.05; length=400))
    yp = [softplus(x; κ=κ_pof)  - softplus(0.0; κ=κ_pof)  for x in xs]
    yc = [softplus(x; κ=κ_cvar) - softplus(0.0; κ=κ_cvar) for x in xs]

    fig, ax = subplots(figsize=(6,4))
    ax.plot(xs, yp, label="PoF κ=$(κ_pof)")
    ax.plot(xs, yc, label="CVaR κ=$(κ_cvar)")
    ax.axvline(0.0; linestyle="--", linewidth=1)
    ax.set_xlabel("violation x (metric - threshold)")
    ax.set_ylabel("softplus(x) - softplus(0)")
    ax.set_title("Zero-baseline softplus shapes")
    ax.legend()
    plt.tight_layout()
    safesave(joinpath(plot_path, "softplus_demo.png"), fig); close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# Space–time risk metrics
function r_spacetime_distribution(pres_arr::Vector{Array{Float64,2}},
                                  p_max::Array{Float64,2};
                                  dx::Float64, dz::Float64,
                                  dt_seq::AbstractVector{<:Real},
                                  mode::Symbol=:relative,
                                  p0::Union{Nothing,Array{Float64,2}}=nothing,
                                  mask::Union{Nothing,Array{Float64,2}}=nothing,
                                  weight_mode::Symbol=:voltime)
    @assert length(pres_arr) == length(dt_seq)
    vol = dx * 1.0 * dz
    r_vals  = Float64[]
    w_vals  = Float64[]

    if weight_mode == :uniform
        for (k, P) in enumerate(pres_arr)
            R = if mode == :window
                @assert p0 !== nothing
                (p_max .- P) ./ max.(1e-9, (p_max .- p0))
            else
                (p_max .- P) ./ max.(1e-9, p_max)
            end
            if mask !== nothing; R = R .* mask; end
            append!(r_vals, vec(R))
        end
        M = length(r_vals)
        w_vals = fill(1.0/M, M)
        return r_vals, w_vals
    end

    for (k, P) in enumerate(pres_arr)
        R = if mode == :window
            @assert p0 !== nothing
            (p_max .- P) ./ max.(1e-9, (p_max .- p0))
        else
            (p_max .- P) ./ max.(1e-9, p_max)
        end
        if mask !== nothing; R = R .* mask; end
        append!(r_vals, vec(R))
        append!(w_vals,  fill(vol * dt_seq[k], length(R)))
    end

    keep = findall(w_vals .> 0)
    r_vals = r_vals[keep]; w_vals = w_vals[keep]
    wsum = sum(w_vals)
    if wsum > 0; w_vals ./= wsum; end
    return r_vals, w_vals
end

# Hard/soft risk metrics
pof_weighted(r::Vector{Float64}, w::Vector{Float64}) =
    sum((r[i] < 0.0) ? w[i] : 0.0 for i in eachindex(r))

function pof_smooth(r::Vector{Float64}, w::Vector{Float64}; τ::Float64=0.05)
    return sum(w .* σ.(-r ./ τ))
end

function cvar_ru(L::Vector{Float64}, w::Vector{Float64};
                 α::Float64=0.05, smooth::Bool=true, κ::Float64=50.0,
                 tol::Float64=1e-8, maxit::Int=100)
    @assert length(L) == length(w)
    α = max(min(α, 0.9999), 1e-6)
    φ  = smooth ? (x->softplus(x; κ=κ)) : (x->max(0.0, x))
    dφ = smooth ? (x->dsoftplus(x; κ=κ)) : (x-> (x>0 ? 1.0 : 0.0))
    fprime(t) = 1.0 - (1.0/α) * sum(w .* map(li->dφ(li - t), L))

    lo, hi = 0.0, maximum(L)
    if hi == 0.0
        return 0.0, 0.0
    end
    flo, fhi = fprime(lo), fprime(hi)
    it = 0
    while flo*fhi > 0 && it < 20
        hi *= 2.0; fhi = fprime(hi); it += 1
    end

    t_lo, t_hi = lo, hi
    for _ in 1:maxit
        t_mid = 0.5*(t_lo + t_hi)
        fm = fprime(t_mid)
        if abs(fm) < tol || (t_hi - t_lo) < 1e-10
            t_star = t_mid
            cvar = t_star + (1.0/α) * sum(w .* map(li->φ(li - t_star), L))
            return cvar, t_star
        end
        if flo*fm <= 0
            t_hi = t_mid
        else
            t_lo = t_mid; flo = fm
        end
    end
    t_star = 0.5*(t_lo + t_hi)
    cvar = t_star + (1.0/α) * sum(w .* map(li->φ(li - t_star), L))
    return cvar, t_star
end

# ─────────────────────────────────────────────────────────────────────────────
# One-time sim builder（复用以提速）
function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_firstblock=80/ds)
    model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
    Sblk  = jutulModeling(model, dt_firstblock * ones(ds))
    Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
    return (model=model, logTrans=log.(Trans), Sblk=Sblk)
end

# ─────────────────────────────────────────────────────────────────────────────
# Objective（合并风险统计，避免二次仿真）
function objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                   sat_init, pres_init=nothing,
                   risk = (use_pof=false, λ_pof=0.0, ε=0.01, τ=0.05,
                           use_cvar=false, λ_cvar=0.0, γ=0.0, α=0.05, mode=:relative,
                           weight_mode=:voltime, cvar_soft=false,
                           kappa_pof=50.0, kappa_cvar=50.0,
                           pof_as_constraint=false, cvar_as_constraint=false),
                   forward_step::Int=2, ds::Int=10, collect_states::Bool=false,
                   inj_start::Float64=0.0001)

    inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
    inj_len  = length(inj_rate)
    time_len = length(time_step)

    obj_first = zeros(Float64, inj_len)
    obj       = 0.0
    obj_arr   = zeros(Float64, inj_len)

    sat_arr  = collect_states ? [zeros(n[1], n[end]) for _ in 1:time_len] : Vector{Array{Float64,2}}()
    pres_arr = collect_states ? [zeros(n[1], n[end]) for _ in 1:time_len] : Vector{Array{Float64,2}}()
    BHP_arr  = collect_states ? [zeros(8)             for _ in 1:time_len] : Vector{Vector{Float64}}()
    pres_bound_diff_arr = collect_states ? [zeros(n[1], n[end]) for _ in 1:time_len] : Vector{Array{Float64,2}}()
    BHP_bound_diff_arr  = collect_states ? [zeros(8)             for _ in 1:time_len] : Vector{Vector{Float64}}()

    # ★ 风险统计的压力序列（与前推合并收集）
    pres_for_risk = Vector{Array{Float64,2}}(undef, time_len)
    tcount = 0

    previous_state = nothing
    for i in 1:inj_len
        f = jutulVWell(inj_rate[i], [(inj_loc[1], inj_loc[2])];
                       startz = [inj_loc[3]], endz = [inj_loc[3] + 6*d[3]])

        if i == 1
            state0 = jutulSimpleState(sim.model)
            state0[1:n[1]*n[3]] = vec(sat_init)
            if !isnothing(pres_init); state0[n[1]*n[3]+1:end] = vec(pres_init); end
            states = sim.Sblk(sim.logTrans, f; state0=state0)
        else
            states = sim.Sblk(sim.logTrans, f; state0=previous_state)
        end
        previous_state = states.states[end]

        sat_tmp  = [reshape(states.states[k][1:n[1]*n[3]], n[1], n[end]) for k in 1:ds]
        pres_tmp = [reshape(states.states[k][n[1]*n[3]+1:end], n[1], n[end]) for k in 1:ds]
        BHP_tmp  = [states.states[k].state[:Injector][:Pressure] for k in 1:ds]

        if collect_states
            sat_arr[(i-1)*ds+1:i*ds]  = sat_tmp
            pres_arr[(i-1)*ds+1:i*ds] = pres_tmp
            BHP_arr[(i-1)*ds+1:i*ds]  = BHP_tmp
        end

        for j in 1:ds
            obj_first[i] -= inj_rate[i] * time_step[ds*(i-1)+j] * JutulDarcyRules.day * JutulDarcyRules.ρCO2
            if collect_states
                pres_bound_diff_arr[ds*(i-1)+j] = p_max - pres_tmp[j]
                BHP_bound_diff_arr[ds*(i-1)+j]  = BHP_max .- BHP_tmp[j]
            end
            tcount += 1
            pres_for_risk[tcount] = pres_tmp[j]
        end

        obj_arr[i] = obj_first[i]
        obj += obj_first[i]
    end

    # —— 风险分布与指标（用 pres_for_risk）——
    dx, dz = d[1], d[3]
    r_vals, w_vals = r_spacetime_distribution(
        pres_for_risk, p_max; dx=dx, dz=dz, dt_seq=time_step,
        mode=risk.mode, p0=(risk.mode==:window ? transpose(p0) : nothing),
        mask=nothing, weight_mode=risk.weight_mode
    )

    pof_hard_hat   = pof_weighted(r_vals, w_vals)
    pof_smooth_hat = pof_smooth(r_vals, w_vals; τ=risk.τ)

    L = max.(0.0, .-r_vals)
    cvar_smooth, _ = cvar_ru(L, w_vals; α=risk.α, smooth=risk.cvar_soft, κ=risk.kappa_cvar)
    cvar_eval,   _ = cvar_ru(L, w_vals; α=risk.α, smooth=false)

    # 硬约束
    if risk.use_pof && risk.pof_as_constraint && (pof_hard_hat > risk.ε + 1e-12)
        previous_state = nothing; GC.gc()
        return Inf, obj, 0.0, 0.0, 0.0,
               sat_arr, pres_arr, BHP_arr,
               pres_bound_diff_arr, BHP_bound_diff_arr,
               obj_first, obj_arr,
               pof_smooth_hat, cvar_eval, pof_hard_hat,
               r_vals, w_vals
    end
    if risk.use_cvar && risk.cvar_as_constraint && (cvar_eval > risk.γ + 1e-12)
        previous_state = nothing; GC.gc()
        return Inf, obj, 0.0, 0.0, 0.0,
               sat_arr, pres_arr, BHP_arr,
               pres_bound_diff_arr, BHP_bound_diff_arr,
               obj_first, obj_arr,
               pof_smooth_hat, cvar_eval, pof_hard_hat,
               r_vals, w_vals
    end

    # 软罚（零基线）
    κ_pof  = risk.kappa_pof
    κ_cvar = risk.kappa_cvar
    pen_pof  = risk.use_pof  ? risk.λ_pof  * (softplus(pof_smooth_hat - risk.ε; κ=κ_pof)  - softplus(0.0; κ=κ_pof))  : 0.0
    pen_cvar = risk.use_cvar ? risk.λ_cvar * (softplus(cvar_smooth     - risk.γ; κ=κ_cvar) - softplus(0.0; κ=κ_cvar)) : 0.0
    penalty  = pen_pof + pen_cvar

    obj_base  = obj
    obj_total = obj_base + penalty
    previous_state = nothing; GC.gc()

    return obj_total, obj_base, penalty, pen_pof, pen_cvar,
           sat_arr, pres_arr, BHP_arr,
           pres_bound_diff_arr, BHP_bound_diff_arr,
           obj_first, obj_arr,
           pof_smooth_hat, cvar_eval, pof_hard_hat,
           r_vals, w_vals
end

# ─────────────────────────────────────────────────────────────────────────────
# FD gradient（central / forward）
function grad_wrt_inj(inj_rate, delta_inj_rate, time_step,
                      sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init, pres_init=nothing, risk=nothing,
                      forward_step::Int=2, ds::Int=10,
                      inj_start::Float64=0.0001, use_forward::Bool=false)
    grad = zeros(size(inj_rate, 1))
    if use_forward
        for i in 1:size(inj_rate, 1)
            fwd = objective(inj_rate + delta_inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                            sat_init=sat_init, pres_init=pres_init, risk=risk,
                            forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
            cur = objective(inj_rate,                time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                            sat_init=sat_init, pres_init=pres_init, risk=risk,
                            forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
            grad[i] = (fwd - cur) / (delta_inj_rate[i])
        end
    else
        for i in 1:size(inj_rate, 1)
            fwd = objective(inj_rate + delta_inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                            sat_init=sat_init, pres_init=pres_init, risk=risk,
                            forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
            bwd = objective(inj_rate - delta_inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                            sat_init=sat_init, pres_init=pres_init, risk=risk,
                            forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
            grad[i] = (fwd - bwd) / (2 * delta_inj_rate[i])
        end
    end
    return grad
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
function main()
    args = parse_commandline()
    s = args["idx_num"]; println("idx_num: ", s)
    α_tail  = args["alpha"]

    # domain/data
    n = (512, 1, 256)
    d = (6.25, 100.0, 6.25)
    h = 0.0
    ϕ = 0.25
    ds = 10
    forward_step = 2

    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    perm_data = JLD2.load(perm_path)
    BroadK = perm_data["BroadK"]

    monitoring_step = 1
    state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2")
    state_data = JLD2.load(state_path)

    risk_mode = args["risk_mode"] == "window" ? :window : :relative

    idices = state_data["idx_t" * string(monitoring_step)]
    idx = idices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md

    p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
    threshold = 4.0
    p_max = p0' .+ threshold * 10^6

    # prior state
    sat_init = nothing
    pres_init = nothing
    if monitoring_step == 1
        inj_y0 = 191 + argmax(K[250, 191:200]) - 1
        S0 = zeros(Float64, n[1], n[end])
        Random.seed!(2025 + s - 1)
        value = 0.2 + rand(Float64) * 0.6
        S0[249:251, inj_y0-4] .= value
        S0[248:252, inj_y0-3] .= value
        S0[247:253, inj_y0-2] .= value
        S0[246:254, inj_y0-1] .= value
        S0[246:254, inj_y0]   .= value
        S0[246:254, inj_y0+1] .= value
        S0[247:253, inj_y0+2] .= value
        S0[248:252, inj_y0+3] .= value
        S0[249:251, inj_y0+4] .= value
        sat_init = S0
    else
        prior_path = datadir("state/Wise_128SatPres_for_Optim_Inj_vec_ir_k" * string(monitoring_step - 1) * ".jld2")
        prior_data = JLD2.load(prior_path)
        pres_samples = prior_data["pres_samples"]
        min_each_sample = map(i -> minimum(p_max - pres_samples[i, :, :]), 1:size(pres_samples, 1))
        global_min_idx = argmin(min_each_sample)
        sat_init = prior_data["sat_samples"][global_min_idx, :, :]
        pres_init = prior_data["pres_samples"][global_min_idx, :, :]
    end
    @assert sat_init !== nothing "sat_init must be defined before calling objective"

    # risk opts
    risk_opts = (
        use_pof = Base.get(args, "use_pof", false),
        λ_pof   = args["lambda_pof"],
        ε       = args["eps_pof"],
        τ       = args["tau_pof"],

        use_cvar = Base.get(args, "use_cvar", false),
        λ_cvar   = args["lambda_cvar"],
        γ        = args["gamma_cvar"],
        α        = α_tail,

        mode     = risk_mode,
        weight_mode = (args["weight_mode"] == "uniform" ? :uniform : :voltime),
        cvar_soft = Base.get(args, "cvar_soft", false),

        kappa_pof  = args["kappa_pof"],
        kappa_cvar = args["kappa_cvar"],

        pof_as_constraint  = Base.get(args, "pof_as_constraint", false),
        cvar_as_constraint = Base.get(args, "cvar_as_constraint", false)
    )
    println("Risk options: ", risk_opts)

    # tags/paths
    function scenariatag(risk; step::Int, idx::Int)
        parts = String[
            "step$(step)", "idx$(idx)",
            risk.use_pof ? "POF" : "", risk.use_cvar ? "CVaR" : "",
            ((risk.pof_as_constraint || risk.cvar_as_constraint) ? "HARD" : "SOFT"),
            risk.use_pof  ? "eps=$(risk.ε)" : "",
            risk.use_pof  ? "tau=$(risk.τ)" : "",
            risk.use_cvar ? "alpha=$(risk.α)" : "",
            risk.use_cvar ? "gamma=$(risk.γ)" : "",
            "w=$(String(risk.weight_mode))",
            "mode=$(String(risk.mode))",
            risk.cvar_soft ? "cvarsoft" : "cvarhinge",
            "kp=$(risk.kappa_pof)", "kc=$(risk.kappa_cvar)"
        ]
        join(filter(!isempty, parts), "__")
    end
    function casetag(risk)
        parts = String[
            risk.use_pof ? "POF" : "",
            risk.use_cvar ? "CVaR" : "",
            ((risk.pof_as_constraint || risk.cvar_as_constraint) ? "HARD" : "SOFT"),
            risk.use_pof  ? "eps=$(risk.ε)" : "",
            risk.use_pof  ? "tau=$(risk.τ)" : "",
            risk.use_cvar ? "alpha=$(risk.α)" : "",
            risk.use_cvar ? "gamma=$(risk.γ)" : "",
            "w=$(String(risk.weight_mode))",
            "mode=$(String(risk.mode))",
            risk.cvar_soft ? "cvarsoft" : "cvarhinge",
            "kp=$(risk.kappa_pof)", "kc=$(risk.kappa_cvar)"
        ]
        return join(filter(!isempty, parts), "__")
    end

    sim_name = "DT_control"
    run_tag = scenariatag(risk_opts; step=monitoring_step, idx=s)
    case_tag = casetag(risk_opts)
    exp_layer = "exp_name=step$(monitoring_step)"

    data_root  = datadir(sim_name, exp_layer, case_tag)
    sample_tag = savename(@strdict(sample=s); digits=6)
    out_root   = joinpath(data_root, sample_tag)
    mkpath(out_root)

    plot_path = plotsdir(sim_name, exp_layer, "states", case_tag)
    mkpath(plot_path)

    # 可选 softplus demo
    if Base.get(args, "plot_softplus_demo", false)
        plot_softplus_demo!(plot_path; κ_pof=risk_opts.kappa_pof, κ_cvar=risk_opts.kappa_cvar)
    end

    # 时间步与注入参数
    time_step = 80 / ds * ones(6 * ds * forward_step)
    inj_rate  = [args["inj_guess"]]
    δinj      = 1e-8 * ones(size(inj_rate, 1))
    inj_start = args["inj_start"]

    # 井位置
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc_grid = (250, 1, inj_y)
    inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])

    # BHP bound（仅日志/出图）
    BHP_max = p_max[inj_y, 250]

    # 预构建仿真块
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)

    # 固定场图（一次）
    if s == 1
        plot_state(transpose(p_max), "Fracture pressure", "_fracture_pressure.png", plot_path, s, h, n, d, "pres")
        plot_state(p0, "Water pressure", "_water_pressure.png", plot_path, s, h, n, d, "pres")
        fracture_pressure_diff = transpose(p_max) - p0
        plot_state(fracture_pressure_diff, "Fracture pressure difference", "_fracture_pressure_diff.png", plot_path, s, h, n, d, "pres")
        plot_ϕ = ϕ * ones(n); plot_ϕ = transpose(plot_ϕ[:, 1, :])
        plot_state(plot_ϕ, "Porosity", "_poro.png", plot_path, s, h, n, d, "poro")
    end
    logK = log10.(transpose(K/JutulDarcyRules.md))
    plot_state(logK, "Permeability", "_perm.png", plot_path, s, h, n, d, "perm")

    # 存储与开关
    niterations = args["niterations"]
    save_plots  = Base.get(args, "save_plots", false)
    plot_stride = args["plot_stride"]
    save_every  = args["save_every"]
    save_states = Base.get(args, "save_states", false)
    use_forward = Base.get(args, "grad_forward", false)

    inj_rate_arr = zeros(Float64, niterations+1, size(inj_rate, 1))
    inj_rate_arr[1, :] = inj_rate

    obj_arr_niter = zeros(Float64, niterations+1)
    obj_1_arr = zeros(Float64, niterations+1, forward_step * 6)
    obj_arr_arr = zeros(Float64, niterations+1, forward_step * 6)
    grad_arr = zeros(Float64, niterations+1, size(inj_rate, 1))

    pof_iter      = fill(NaN, niterations+1)
    pof_hard_iter = fill(NaN, niterations+1)
    cvar_iter     = fill(NaN, niterations+1)

    obj_base_arr  = zeros(Float64, niterations+1)
    pen_total_arr = zeros(Float64, niterations+1)
    pen_pof_arr   = zeros(Float64, niterations+1)
    pen_cvar_arr  = zeros(Float64, niterations+1)

    # <<< CHANGED: 记录线搜索“原因”的数组
    stp_cause      = fill(0, niterations)         # 1=constraint(Inf), 2=Armijo/curvature, 0=unknown
    stp_alpha_ratio= zeros(Float64, niterations)   # α_ok / stp

    # 首次前推（若不满足硬约束则回退缩小）
    function first_forward!(inj_rate)
        obj, obj_base, pen_total, pen_pof, pen_cvar,
        sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
        obj_first, obj_arr, pof_smooth0, cvar0, pof_hard0, r_vals0, w_vals0 =
            objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                      forward_step=forward_step, ds=ds,
                      collect_states=(save_states || save_plots),
                      inj_start=inj_start)

        while obj == Inf
            inj_rate .*= 0.8
            inj_rate[1] = max(inj_rate[1], 0.0001)
            obj, obj_base, pen_total, pen_pof, pen_cvar,
            sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
            obj_first, obj_arr, pof_smooth0, cvar0, pof_hard0, r_vals0, w_vals0 =
                objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                          sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                          forward_step=forward_step, ds=ds,
                          collect_states=(save_states || save_plots),
                          inj_start=inj_start)
        end
        return obj, obj_base, pen_total, pen_pof, pen_cvar,
               sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
               obj_first, obj_arr, pof_smooth0, cvar0, pof_hard0, r_vals0, w_vals0
    end

    obj, obj_base, pen_total, pen_pof, pen_cvar,
    sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
    obj_first, obj_arr, pof0_smooth, cvar0, pof0_hard, r_vals0, w_vals0 =
        first_forward!(inj_rate)

    println("Iteration no: 0; Objective (with penalties) = ", obj)
    println("  base = $(obj_base), penalty = $(pen_total) (pof=$(pen_pof), cvar=$(pen_cvar))")
    if abs(obj) > 0
        println(@sprintf("  penalty share = %.2f%%", 100*pen_total/obj))
    end

    # λ 建议
    target_share = args["target_share"]; delta_ref = args["delta_ref"]
    σ0 = 0.5
    absbase = max(1.0, abs(obj_base))
    if risk_opts.use_pof
        λ_pof_boundary = (target_share * absbase) / (σ0 * delta_ref + 1e-30)
        λ_pof_current  = (risk_opts.λ_pof > 0 && pen_pof > 0) ? (target_share * absbase) / (pen_pof / risk_opts.λ_pof) : NaN
        println(@sprintf("λ_pof 建议： boundary≈%.3e, current≈%s", λ_pof_boundary,
                isnan(λ_pof_current) ? "n/a" : @sprintf("%.3e", λ_pof_current)))
    end
    if risk_opts.use_cvar
        λ_cvar_boundary = (target_share * absbase) / (σ0 * delta_ref + 1e-30)
        λ_cvar_current  = (risk_opts.λ_cvar > 0 && pen_cvar > 0) ? (target_share * absbase) / (pen_cvar / risk_opts.λ_cvar) : NaN
        println(@sprintf("λ_cvar 建议： boundary≈%.3e, current≈%s", λ_cvar_boundary,
                isnan(λ_cvar_current) ? "n/a" : @sprintf("%.3e", λ_cvar_current)))
    end

    pof_iter[1]      = pof0_smooth
    pof_hard_iter[1] = pof0_hard
    cvar_iter[1]     = cvar0
    obj_arr_niter[1] = obj
    obj_1_arr[1, :]  = obj_first
    obj_arr_arr[1, :] = obj_arr
    obj_base_arr[1]  = obj_base
    pen_total_arr[1] = pen_total
    pen_pof_arr[1]   = pen_pof
    pen_cvar_arr[1]  = pen_cvar

    # 初始梯度（必须算）
    grad = grad_wrt_inj(inj_rate, δinj, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                        sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                        forward_step=forward_step, ds=ds,
                        inj_start=inj_start, use_forward=use_forward)
    gnorm = norm(grad, Inf)
    if gnorm == 0.0
        println("Gradient is zero at initialization; stopping.")
        return
    end
    p = -grad/gnorm
    grad_arr[1, :] = grad

    # 关键帧索引
    one_sixth   = forward_step * ds
    three_sixths= 3 * forward_step * ds
    six_sixths  = 6 * forward_step * ds

    # iter 0 图
    if save_plots
        plot_state(transpose(sat_arr[one_sixth]), "CO2 Saturation", "_co2sat$(one_sixth).png",    plot_path, s, h, n, d, "sat", 0)
        plot_state(transpose(sat_arr[three_sixths]), "CO2 Saturation", "_co2sat$(three_sixths).png", plot_path, s, h, n, d, "sat", 0)
        plot_state(transpose(sat_arr[six_sixths]), "CO2 Saturation", "_co2sat$(six_sixths).png",   plot_path, s, h, n, d, "sat", 0)

        plot_state(transpose(pres_arr[one_sixth]), "Pressure", "_pres$(one_sixth).png",            plot_path, s, h, n, d, "pres", 0)
        plot_state(transpose(pres_arr[three_sixths]), "Pressure", "_pres$(three_sixths).png",      plot_path, s, h, n, d, "pres", 0)
        plot_state(transpose(pres_arr[six_sixths]), "Pressure", "_pres$(six_sixths).png",          plot_path, s, h, n, d, "pres", 0)

        plot_state(transpose(pres_arr[one_sixth]), "Pressure Difference", "_presdiff$(one_sixth).png",    plot_path, s, h, n, d, "pres_thres", 0, threshold; p0_ref=p0)
        plot_state(transpose(pres_arr[three_sixths]), "Pressure Difference", "_presdiff$(three_sixths).png", plot_path, s, h, n, d, "pres_thres", 0, threshold; p0_ref=p0)
        plot_state(transpose(pres_arr[six_sixths]), "Pressure Difference", "_presdiff$(six_sixths).png",   plot_path, s, h, n, d, "pres_thres", 0, threshold; p0_ref=p0)
    end

    # 存第 0 次
    @tagsave(joinpath(out_root, savename(@strdict(j=0), "jld2"; digits=6)),
    Dict(
        "sat_arr" => (save_states || save_plots) ? sat_arr : nothing,
        "pres_arr" => (save_states || save_plots) ? pres_arr : nothing,
        "BHP_arr" => (save_states || save_plots) ? BHP_arr : nothing,
        "pres_bound_diff_arr" => (save_states || save_plots) ? pres_bound_diff_arr : nothing,
        "BHP_bound_diff_arr" => (save_states || save_plots) ? BHP_bound_diff_arr : nothing,
        "pof_iter" => [pof_iter[1]],
        "pof_hard_iter" => [pof_hard_iter[1]],
        "cvar_iter" => [cvar_iter[1]],
        "obj_base"  => obj_base,
        "pen_total" => pen_total,
        "pen_pof"   => pen_pof,
        "pen_cvar"  => pen_cvar,
        "r_vals" => r_vals0,
        "w_vals" => w_vals0,
        "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step)
        );
    safe=true)

    # 迭代
    proj(x) = max.(x, 0)
    ls = BackTracking(order=3, iterations=10)
    step_arr = zeros(niterations)
    ex_step_size = 0.1

    # <<< CHANGED: 新的停机阈值
    rel_impr_tol = 1e-6
    projgrad_tol = 1e-6
    stp_min_abs  = 1e-5

    for j=1:niterations
        # 保存上一次目标用于相对改进
        prev_obj = obj  # <<< CHANGED

        # 为避免闭包里 inj_rate 被更新，复制一份用于本轮线搜索与探针
        inj_rate_ls = copy(inj_rate)    # <<< CHANGED
        p_ls        = copy(p)           # <<< CHANGED

        function θ(α)
            objective(proj(inj_rate_ls + α * p_ls), time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
        end

        stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
        ex_step_size = stp

        # <<< CHANGED: 探针评估，判别 Inf-驱动 vs Armijo-驱动
        is_feasible = function(α)
            isfinite(
                objective(proj(inj_rate_ls + α * p_ls), time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                          sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                          forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
            )
        end

        α_ok = stp
        for scale in (1.0, 1.25, 1.5, 2.0, 3.0)
            α = scale * stp
            if is_feasible(α)
                α_ok = α
            else
                break
            end
        end
        cause = (!is_feasible(1.05*stp)) ? 1 : (α_ok >= 2.0*stp ? 2 : 0)
        stp_cause[j]       = cause
        stp_alpha_ratio[j] = stp > 0 ? (α_ok / stp) : 0.0
        # <<< CHANGED: 探针记录结束

        step_arr[j] = stp
        inj_rate = proj(inj_rate_ls + stp * p_ls)   # <<< CHANGED：用 ls 期间冻结的 inj_rate_ls/p_ls
        inj_rate_arr[j+1, :] = inj_rate

        need_plots  = save_plots && (j % plot_stride == 0 || j == niterations)
        need_save   = (j % save_every == 0 || j == niterations)
        need_states = save_states || need_plots

        obj, obj_base, pen_total, pen_pof, pen_cvar,
        sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
        obj_first, obj_arr, pofj_smooth, cvarj, pofj_hard, r_valsj, w_valsj =
            objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=need_states, inj_start=inj_start)

        println("Iteration no: ", j, "; Objective (with penalties) = ", obj)
        println("  base = $(obj_base), penalty = $(pen_total) (pof=$(pen_pof), cvar=$(pen_cvar))")
        if abs(obj) > 0
            println(@sprintf("  penalty share = %.2f%%", 100*pen_total/obj))
        end

        obj_arr_niter[j+1] = obj
        obj_1_arr[j+1, :]  = obj_first
        obj_arr_arr[j+1, :] = obj_arr

        obj_base_arr[j+1]  = obj_base
        pen_total_arr[j+1] = pen_total
        pen_pof_arr[j+1]   = pen_pof
        pen_cvar_arr[j+1]  = pen_cvar

        pof_iter[j+1]      = pofj_smooth
        pof_hard_iter[j+1] = pofj_hard
        cvar_iter[j+1]     = cvarj

        # 梯度（每次迭代都算）
        grad = grad_wrt_inj(inj_rate, δinj, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                            sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                            forward_step=forward_step, ds=ds,
                            inj_start=inj_start, use_forward=use_forward)
        gnorm = norm(grad, Inf)
        if gnorm == 0.0
            println("Gradient became zero; stopping at iter $j.")
            break
        end
        p = -grad/gnorm
        grad_arr[j+1, :] = grad

        # <<< CHANGED: 新停机准则（相对改进 + 投影梯度 + 绝对步长兜底）
        rel_impr = abs(prev_obj - obj) / max(1.0, abs(obj))
        proj_grad = inj_rate .- proj(inj_rate .- grad)
        if (rel_impr < rel_impr_tol && norm(proj_grad, Inf) < projgrad_tol * max(1.0, abs(obj))) || (stp < stp_min_abs)
            println(@sprintf("Stopping at iter %d: rel_impr=%.3e, proj_grad_inf=%.3e, stp=%.3e",
                             j, rel_impr, norm(proj_grad, Inf), stp))
            need_save = true
            # fall through to save below
            # break after save
            # (保存逻辑在下方 need_save 分支)
        end
        # <<< CHANGED: 停机准则结束

        # 存
        if need_save
            @tagsave(joinpath(out_root, savename(@strdict(j), "jld2"; digits=6)),
            Dict(
                "sat_arr" => need_states ? sat_arr : nothing,
                "pres_arr" => need_states ? pres_arr : nothing,
                "BHP_arr" => need_states ? BHP_arr : nothing,
                "pres_bound_diff_arr" => need_states ? pres_bound_diff_arr : nothing,
                "BHP_bound_diff_arr" => need_states ? BHP_bound_diff_arr : nothing,
                "pof_iter" => pof_iter[1:j+1],
                "pof_hard_iter" => pof_hard_iter[1:j+1],
                "cvar_iter" => cvar_iter[1:j+1],
                "obj_base"  => obj_base,
                "pen_total" => pen_total,
                "pen_pof"   => pen_pof,
                "pen_cvar"  => pen_cvar,
                "r_vals" => r_valsj,
                "w_vals" => w_valsj,
                # <<< CHANGED: 记录线搜索原因/最大可行步比
                "stp_cause" => stp_cause[1:j],
                "stp_alpha_ratio" => stp_alpha_ratio[1:j],
                "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step)
                );
            safe=true)
        end

        # 图（关键帧）
        if need_plots
            plot_state(transpose(sat_arr[one_sixth]),     "CO2 Saturation", "_co2sat$(one_sixth).png",    plot_path, s, h, n, d, "sat", j)
            plot_state(transpose(sat_arr[three_sixths]),  "CO2 Saturation", "_co2sat$(three_sixths).png", plot_path, s, h, n, d, "sat", j)
            plot_state(transpose(sat_arr[six_sixths]),    "CO2 Saturation", "_co2sat$(six_sixths).png",   plot_path, s, h, n, d, "sat", j)

            plot_state(transpose(pres_arr[one_sixth]),    "Pressure", "_pres$(one_sixth).png",            plot_path, s, h, n, d, "pres", j)
            plot_state(transpose(pres_arr[three_sixths]), "Pressure", "_pres$(three_sixths).png",         plot_path, s, h, n, d, "pres", j)
            plot_state(transpose(pres_arr[six_sixths]),   "Pressure", "_pres$(six_sixths).png",           plot_path, s, h, n, d, "pres", j)

            plot_state(transpose(pres_arr[one_sixth]),    "Pressure Difference", "_presdiff$(one_sixth).png",    plot_path, s, h, n, d, "pres_thres", j, threshold; p0_ref=p0)
            plot_state(transpose(pres_arr[three_sixths]), "Pressure Difference", "_presdiff$(three_sixths).png", plot_path, s, h, n, d, "pres_thres", j, threshold; p0_ref=p0)
            plot_state(transpose(pres_arr[six_sixths]),   "Pressure Difference", "_presdiff$(six_sixths).png",   plot_path, s, h, n, d, "pres_thres", j, threshold; p0_ref=p0)
        end

        # <<< CHANGED: 移除原“比例步长”早停；改为上面的复合停机
        # if stp < (inj_rate + [inj_start])[1] / 2 * 0.05 / 0.95
        #     break
        # end

        if ((abs(prev_obj - obj) / max(1.0, abs(obj)) < rel_impr_tol &&  # 已触发新停机
             (norm(inj_rate .- proj(inj_rate .- grad), Inf) < projgrad_tol * max(1.0, abs(obj)))) ||
            (stp < stp_min_abs))
            GC.gc()
            break
        end

        GC.gc()
    end

    # final
    @tagsave(joinpath(out_root, "final.jld2"),
    Dict(
        "inj_rate_arr"  => inj_rate_arr,
        "step_arr"      => step_arr,
        "obj_arr_niter" => obj_arr_niter,
        "obj_1_arr"     => obj_1_arr,
        "obj_arr_arr"   => obj_arr_arr,
        "grad_arr"      => grad_arr,
        "pof_iter"      => pof_iter,
        "pof_hard_iter" => pof_hard_iter,
        "cvar_iter"     => cvar_iter,
        "obj_base_arr"  => obj_base_arr,
        "pen_total_arr" => pen_total_arr,
        "pen_pof_arr"   => pen_pof_arr,
        "pen_cvar_arr"  => pen_cvar_arr,
        # <<< CHANGED: 把判别指标也写进 final
        "stp_cause" => stp_cause,
        "stp_alpha_ratio" => stp_alpha_ratio,
        "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step)
        );
    safe=true)

    # penalty 曲线
    try
        iters = 0:niterations
        share = [ pen_total_arr[k] / max(1.0, abs(obj_base_arr[k])) for k in eachindex(pen_total_arr) ]

        fig, ax = subplots(figsize=(6,4))
        ax.plot(iters, 100 .* share)
        ax.set_xlabel("iteration"); ax.set_ylabel("penalty share (%)")
        ax.set_title("Penalty share vs iteration")
        plt.tight_layout()
        safesave(joinpath(plot_path, "penalty_share__sample=$(s).png"), fig); close(fig)

        fig, ax = subplots(figsize=(6,4))
        ax.plot(iters, pen_total_arr, label="total")
        ax.plot(iters, pen_pof_arr,  label="PoF")
        ax.plot(iters, pen_cvar_arr, label="CVaR")
        ax.legend(); ax.set_xlabel("iteration"); ax.set_ylabel("penalty (abs units)")
        ax.set_title("Penalty components")
        plt.tight_layout()
        safesave(joinpath(plot_path, "penalty_components__sample=$(s).png"), fig); close(fig)

        println("Saved curves: penalty_share__sample=$(s).png, penalty_components__sample=$(s).png")
    catch e
        @warn "Plotting penalty curves failed" exception=(e, catch_backtrace())
    end
end

main()
