# Backtracking line search gradient descent optimization solver for geological
# carbon storage. Maximize injected CO2 integral + risk penalties (no log barrier).
# Supports POF/CVaR soft penalties AND hard constraints. Persists r_vals / w_vals.

# ─────────────────────────────────────────────────────────────────────────────
# Activate environment & deps
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

# ─────────────────────────────────────────────────────────────────────────────
# PyCall setup
function setup_pycall()
    if get(ENV, "LMOD_SITE_NAME", "") == "PACE"
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

        # NEW: hard constraints
        "--pof_as_constraint"
            help = "Treat POF as a hard constraint: if metric>ε, objective=Inf"
            action = :store_true

        "--cvar_as_constraint"
            help = "Treat CVaR as a hard constraint: if CVaR>γ, objective=Inf"
            action = :store_true
    end

    return parse_args(s)
end

# ─────────────────────────────────────────────────────────────────────────────
# Smooth helpers for penalties
σ(u) = 1.0 / (1.0 + exp(-u))  # logistic

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
# Plotting helper
function plot_state(data, title_str, file_suffix, plot_path, sample, h, n, d, type, iter=-1, threshold=-1)
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
        data_diff = data - p0
        lower_cmap_size = round(Int, 256 * threshold * 1e6 / maximum(data_diff))
        upper_cmap_size = 256 - lower_cmap_size
        if lower_cmap_size > 256
            lower_cmap_size = 256; upper_cmap_size = 0
            imshow(data_diff / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="Blues", vmin=0, vmax=threshold)
            clb = colorbar(fraction=0.046*im_ratio, pad=0.04, extend="max")
            clb.set_ticks([0, threshold]); clb.set_ticklabels(["0.0", string(threshold)])
        else
            np = pyimport("numpy")
            lower_cmap = PyPlot.cm.Blues(np.linspace(0, 1, lower_cmap_size))
            upper_cmap = transpose(repeat(collect(PyPlot.cm.colors.to_rgba("red")), outer=(1, upper_cmap_size)))
            colors = vcat(lower_cmap, upper_cmap)
            bounds = vcat(range(0, threshold; length=lower_cmap_size+1),
                          range(threshold, maximum(data)/1e6; length=upper_cmap_size+1)[2:end])
            norm = PyPlot.matplotlib.colors.BoundaryNorm(bounds, size(colors, 1))
            imshow(data_diff / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h),
                   cmap=PyPlot.cm.colors.ListedColormap(colors), norm=norm)
            clb = colorbar(fraction=0.046*im_ratio, pad=0.04, extend="max")
            clb.set_ticks([0, threshold, maximum(data_diff/1e6)])
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

# ─────────────────────────────────────────────────────────────────────────────
# Space–time risk metrics
"""
Compute space–time relative/window margin r and normalized weights.
- relative: r = (p_max - p_res) / p_max
- window:   r = (p_max - p_res) / (p_max - p0)
Weights are (cell volume)*(dt), normalized to sum to 1   (voltime).
If weight_mode=:uniform, use 1/M averaging (slides 1/M).
"""
function r_spacetime_distribution(pres_arr::Vector{Array{Float64,2}},
                                  p_max::Array{Float64,2};
                                  dx::Float64, dz::Float64,
                                  dt_seq::AbstractVector{<:Real},
                                  mode::Symbol=:relative,
                                  p0::Union{Nothing,Array{Float64,2}}=nothing,
                                  mask::Union{Nothing,Array{Float64,2}}=nothing,
                                  weight_mode::Symbol=:voltime)
    @assert length(pres_arr) == length(dt_seq)
    vol = dx * 1.0 * dz  # dy=1 m for 2D slice
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

    # vol*time weighting
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

# Hard POF
pof_weighted(r::Vector{Float64}, w::Vector{Float64}) =
    sum(w[i] for i in eachindex(r) if r[i] < 0.0)

# Smoothed POF
function pof_smooth(r::Vector{Float64}, w::Vector{Float64}; τ::Float64=0.05)
    return sum(w .* σ.(-r ./ τ))
end

# Rockafellar–Uryasev CVaR (weighted; optional softplus smoothing)
"""
CVaR_α = min_t [ t + (1/α) * Σ w_i * φ(L_i - t) ], L_i = max(0, -r_i)
φ = (·)_+  or softplus(·) if smooth=true
"""
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
# Problem setup (domain & data)
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0
ϕ = 0.25

monitoring_step = 1
# monitoring_step = 2

perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
perm_data = JLD2.load(perm_path)
BroadK = perm_data["BroadK"]

state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2")
state_data = JLD2.load(state_path)

args = parse_commandline()
s = args["idx_num"]
println("idx_num: ", s)
α_tail = args["alpha"]

# risk mode
risk_mode = args["risk_mode"] == "window" ? :window : :relative

# Permeability sample
idices = state_data["idx_t" * string(monitoring_step)]
idx = idices[s]
K = BroadK[idx, :, :]

# Hydrostatic & fracture limit
p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
threshold = 4.0
p_max = p0' .+ threshold * 10^6

# ─────────────────────────────────────────────────────────────────────────────
# Prior state (defines sat_init and optional pres_init)
sat_init = nothing
pres_init = nothing

if monitoring_step == 1
    inj_t1 = 191 + argmax(K[250, 191:200]) - 1
    S = zeros(Float64, n[1], n[end])
    Random.seed!(2025 + s - 1)
    value = 0.2 + rand(Float64) * 0.6
    S[249:251, inj_t1-4] .= value
    S[248:252, inj_t1-3] .= value
    S[247:253, inj_t1-2] .= value
    S[246:254, inj_t1-1] .= value
    S[246:254, inj_t1]   .= value
    S[246:254, inj_t1+1] .= value
    S[247:253, inj_t1+2] .= value
    S[248:252, inj_t1+3] .= value
    S[249:251, inj_t1+4] .= value
    sat_init = S
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

# ─────────────────────────────────────────────────────────────────────────────
# Risk options (soft + hard)
risk_opts = (
    use_pof = get(args, "use_pof", false),
    λ_pof   = args["lambda_pof"],
    ε       = args["eps_pof"],
    τ       = args["tau_pof"],

    use_cvar = get(args, "use_cvar", false),
    λ_cvar   = args["lambda_cvar"],
    γ        = args["gamma_cvar"],
    α        = α_tail,

    mode     = risk_mode,
    weight_mode = (args["weight_mode"] == "uniform" ? :uniform : :voltime),
    cvar_soft = get(args, "cvar_soft", false),

    # hard constraints
    pof_as_constraint  = get(args, "pof_as_constraint", false),
    cvar_as_constraint = get(args, "cvar_as_constraint", false)
)

println("Risk options: ", risk_opts)

# ─────────────────────────────────────────────────────────────────────────────
# Build tags + output roots
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
        risk.cvar_soft ? "cvarsoft" : "cvarhinge"
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
        risk.use_cvar ? "gamma$(risk.γ)" : "",
        "w=$(String(risk.weight_mode))",
        "mode=$(String(risk.mode))",
        risk.cvar_soft ? "cvarsoft" : "cvarhinge"
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

# ─────────────────────────────────────────────────────────────────────────────
# MPC forward steps
forward_step = 2

# Objective (no log barrier; soft+hard risk)
function objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max,
                   sat_init=nothing, pres_init=nothing;
                   risk = (use_pof=false, λ_pof=0.0, ε=0.01, τ=0.05,
                           use_cvar=false, λ_cvar=0.0, γ=0.0, α=0.05, mode=:relative,
                           weight_mode=:voltime, cvar_soft=false,
                           pof_as_constraint=false, cvar_as_constraint=false))

    inj_rate = collect(range(init_inj_rate[1], inj_rate[1], forward_step * 6))
    ds = 10
    inj_len  = length(inj_rate)
    time_len = length(time_step)

    obj_first = zeros(Float64, inj_len)   # integral of q(t)
    obj       = 0.0
    obj_arr   = zeros(Float64, inj_len)

    sat_arr  = [zeros(n[1], n[end]) for _ in 1:time_len]
    pres_arr = [zeros(n[1], n[end]) for _ in 1:time_len]
    BHP_arr  = [zeros(8) for _ in 1:time_len]  # for logging
    pres_bound_diff_arr = [zeros(n[1], n[end]) for _ in 1:time_len]  # logging
    BHP_bound_diff_arr  = [zeros(8) for _ in 1:time_len]             # logging

    previous_state = nothing
    for i in 1:inj_len
        if i == 1
            model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
            f = jutulVWell(inj_rate[i], [(inj_loc[1], inj_loc[2])]; startz = [inj_loc[3]], endz = [inj_loc[3]+6*d[3]])
            S = jutulModeling(model, time_step[1:ds])
            Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
            state0 = jutulSimpleState(model)
            state0[1:n[1]*n[3]] = vec(sat_init)
            if !isnothing(pres_init); state0[n[1]*n[3]+1:end] = vec(pres_init); end
            @time states = S(log.(Trans), f; state0=state0)
            previous_state = states.states[end]
        else
            model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
            f = jutulVWell(inj_rate[i], [(inj_loc[1],inj_loc[2])]; startz = [inj_loc[3]], endz = [inj_loc[3]+6*d[3]])
            S = jutulModeling(model, time_step[1:ds])
            Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
            @time states = S(log.(Trans), f; state0=previous_state)
            previous_state = states.states[end]
        end

        sat_tmp  = [reshape(states.states[k][1:n[1]*n[3]], n[1], n[end]) for k in 1:ds]
        pres_tmp = [reshape(states.states[k][n[1]*n[3]+1:end], n[1], n[end]) for k in 1:ds]
        BHP_tmp  = [states.states[k].state[:Injector][:Pressure] for k in 1:ds]

        sat_arr[(i-1)*ds+1:i*ds]  = sat_tmp
        pres_arr[(i-1)*ds+1:i*ds] = pres_tmp
        BHP_arr[(i-1)*ds+1:i*ds]  = BHP_tmp

        for j in 1:ds
            obj_first[i] -= inj_rate[i] * time_step[ds*(i-1)+j] * JutulDarcyRules.day * JutulDarcyRules.ρCO2
            # logging only
            pres_bound_diff_arr[ds*(i-1)+j] = p_max - pres_arr[ds*(i-1)+j]
            BHP_bound_diff_arr[ds*(i-1)+j]  = BHP_max .- BHP_arr[ds*(i-1)+j]
        end

        obj_i = obj_first[i]
        obj_arr[i] = obj_i
        obj += obj_i
    end

    # RISK: compute r_vals/w_vals; POF (hard/smooth); CVaR
    dx, dz = d[1], d[3]; dt_seq = time_step
    r_vals, w_vals = r_spacetime_distribution(
        pres_arr, p_max; dx=dx, dz=dz, dt_seq=dt_seq,
        mode=risk.mode, p0=(risk.mode==:window ? transpose(p0) : nothing),
        mask=nothing, weight_mode=risk.weight_mode
    )

    pof_hard_hat   = pof_weighted(r_vals, w_vals)
    pof_smooth_hat = pof_smooth(r_vals, w_vals; τ=risk.τ)

    L = max.(0.0, .-r_vals)
    cvar_val, _ = cvar_ru(L, w_vals; α=risk.α, smooth=risk.cvar_soft, κ=50.0)

    # HARD constraints
    if risk.use_pof && risk.pof_as_constraint && (pof_hard_hat > risk.ε + 1e-12)
        previous_state = nothing; GC.gc()
        return Inf, sat_arr, pres_arr, BHP_arr,
               pres_bound_diff_arr, BHP_bound_diff_arr,
               obj_first, obj_arr,
               pof_smooth_hat, cvar_val, pof_hard_hat,
               r_vals, w_vals
    end
    if risk.use_cvar && risk.cvar_as_constraint && (cvar_val > risk.γ + 1e-12)
        previous_state = nothing; GC.gc()
        return Inf, sat_arr, pres_arr, BHP_arr,
               pres_bound_diff_arr, BHP_bound_diff_arr,
               obj_first, obj_arr,
               pof_smooth_hat, cvar_val, pof_hard_hat,
               r_vals, w_vals
    end

    # SOFT penalties
    penalty = 0.0
    if risk.use_pof
        penalty += risk.λ_pof  * softplus(pof_smooth_hat - risk.ε; κ=50.0)
    end
    if risk.use_cvar
        penalty += risk.λ_cvar * softplus(cvar_val - risk.γ; κ=50.0)
    end

    obj_total = obj + penalty
    previous_state = nothing; GC.gc()

    return obj_total, sat_arr, pres_arr, BHP_arr,
           pres_bound_diff_arr, BHP_bound_diff_arr,
           obj_first, obj_arr,
           pof_smooth_hat, cvar_val, pof_hard_hat,
           r_vals, w_vals
end

# Finite-difference gradient (central)
function grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max,
                      sat_init=nothing, pres_init=nothing; risk=nothing)
    grad = zeros(size(inj_rate, 1))
    for i in 1:size(inj_rate, 1)
        obj_forward = objective(inj_rate + delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max,
                                sat_init, pres_init; risk=risk)[1]
        obj_backward = objective(inj_rate - delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max,
                                 sat_init, pres_init; risk=risk)[1]
        grad[i] = (obj_forward - obj_backward) / (2 * delta_inj_rate[i])
    end
    return grad
end

# ─────────────────────────────────────────────────────────────────────────────
# Initial injection rate (step 1)
init_inj_rate = [0.0001]
# Time discretization & initial guess
ds = 10
forward_step = 2
time_step = 80 / ds * ones(6 * ds * forward_step)  # uniform dt
inj_rate = [0.05]
delta_inj_rate = 10.0^-8 * ones(size(inj_rate, 1))

# Units & injector location
K = K * JutulDarcyRules.md
inj_y = 191 + argmax(K[250, 191:200]) - 1
inj_loc_grid = (250, 1, inj_y)
inj_loc = inj_loc_grid .* d

# BHP bound (only for logging/plots)
BHP_max = p_max[inj_y, 250]

# ── Fixed-field plots
if s == 1
    plot_state(transpose(p_max), "Fracture pressure", "_fracture_pressure.png", plot_path, s, h, n, d, "pres")
    plot_state(p0, "Water pressure", "_water_pressure.png", plot_path, s, h, n, d, "pres")
    fracture_pressure_diff = transpose(p_max) - p0
    plot_state(fracture_pressure_diff, "Fracture pressure difference", "_fracture_pressure_diff.png", plot_path, s, h, n, d, "pres")
    plot_ϕ = ϕ * ones(n); plot_ϕ = transpose(plot_ϕ[:, 1, :])
    plot_state(plot_ϕ, "Porosity", "_poro.png", plot_path, s, h, n, d, "poro")
end

# Permeability plot
logK = log10.(transpose(K/JutulDarcyRules.md))
plot_state(logK, "Permeability", "_perm.png", plot_path, s, h, n, d, "perm")

# ─────────────────────────────────────────────────────────────────────────────
# Optimization storage
niterations = 20
inj_rate_arr = zeros(Float64, niterations+1, size(inj_rate, 1))
inj_rate_arr[1, :] = inj_rate

obj_arr_niter = zeros(Float64, niterations+1)
obj_1_arr = zeros(Float64, niterations+1, forward_step * 6)
obj_arr_arr = zeros(Float64, niterations+1, forward_step * 6)
grad_arr = zeros(Float64, niterations+1, size(inj_rate, 1))

# Risk traces
pof_iter      = fill(NaN, niterations+1)   # smoothed
pof_hard_iter = fill(NaN, niterations+1)   # hard
cvar_iter     = fill(NaN, niterations+1)

# ─────────────────────────────────────────────────────────────────────────────
# First forward (fallback shrink if infeasible)
function first_forward!(inj_rate)
    obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
    obj_first, obj_arr, pof_smooth0, cvar0, pof_hard0, r_vals0, w_vals0 =
        objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init; risk=risk_opts)

    while obj == Inf
        inj_rate .*= 0.8
        inj_rate[1] = max(inj_rate[1], 0.0001)
        obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
        obj_first, obj_arr, pof_smooth0, cvar0, pof_hard0, r_vals0, w_vals0 =
            objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init; risk=risk_opts)
    end

    return obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
           obj_first, obj_arr, pof_smooth0, cvar0, pof_hard0, r_vals0, w_vals0
end

obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
obj_first, obj_arr, pof0_smooth, cvar0, pof0_hard, r_vals0, w_vals0 =
    first_forward!(inj_rate)

println("Iteration no: 0; Objective (with penalties) = ", obj)
pof_iter[1]      = pof0_smooth
pof_hard_iter[1] = pof0_hard
cvar_iter[1]     = cvar0
obj_arr_niter[1] = obj
obj_1_arr[1, :]  = obj_first
obj_arr_arr[1, :] = obj_arr

grad = grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init; risk=risk_opts)
p = -grad/norm(grad, Inf)
grad_arr[1, :] = grad

one_sixth = forward_step * ds
two_sixths = 2 * forward_step * ds
three_sixths = 3 * forward_step * ds
four_sixths = 4 * forward_step * ds
five_sixths = 5 * forward_step * ds
six_sixths = 6 * forward_step * ds

# Plots at iter 0
plot_state(transpose(sat_arr[one_sixth]), "CO2 Saturation", "_co2sat$(one_sixth).png", plot_path, s, h, n, d, "sat", 0)
plot_state(transpose(sat_arr[two_sixths]), "CO2 Saturation", "_co2sat$(two_sixths).png", plot_path, s, h, n, d, "sat", 0)
plot_state(transpose(sat_arr[three_sixths]), "CO2 Saturation", "_co2sat$(three_sixths).png", plot_path, s, h, n, d, "sat", 0)
plot_state(transpose(sat_arr[four_sixths]), "CO2 Saturation", "_co2sat$(four_sixths).png", plot_path, s, h, n, d, "sat", 0)
plot_state(transpose(sat_arr[five_sixths]), "CO2 Saturation", "_co2sat$(five_sixths).png", plot_path, s, h, n, d, "sat", 0)
plot_state(transpose(sat_arr[six_sixths]), "CO2 Saturation", "_co2sat$(six_sixths).png", plot_path, s, h, n, d, "sat", 0)

plot_state(transpose(pres_arr[one_sixth]), "Pressure", "_pres$(one_sixth).png", plot_path, s, h, n, d, "pres", 0)
plot_state(transpose(pres_arr[two_sixths]), "Pressure", "_pres$(two_sixths).png", plot_path, s, h, n, d, "pres", 0)
plot_state(transpose(pres_arr[three_sixths]), "Pressure", "_pres$(three_sixths).png", plot_path, s, h, n, d, "pres", 0)
plot_state(transpose(pres_arr[four_sixths]), "Pressure", "_pres$(four_sixths).png", plot_path, s, h, n, d, "pres", 0)
plot_state(transpose(pres_arr[five_sixths]), "Pressure", "_pres$(five_sixths).png", plot_path, s, h, n, d, "pres", 0)
plot_state(transpose(pres_arr[six_sixths]), "Pressure", "_pres$(six_sixths).png", plot_path, s, h, n, d, "pres", 0)

plot_state(transpose(pres_arr[one_sixth]), "Pressure Difference", "_presdiff$(one_sixth).png", plot_path, s, h, n, d, "pres_thres", 0, threshold)
plot_state(transpose(pres_arr[two_sixths]), "Pressure Difference", "_presdiff$(two_sixths).png", plot_path, s, h, n, d, "pres_thres", 0, threshold)
plot_state(transpose(pres_arr[three_sixths]), "Pressure Difference", "_presdiff$(three_sixths).png", plot_path, s, h, n, d, "pres_thres", 0, threshold)
plot_state(transpose(pres_arr[four_sixths]), "Pressure Difference", "_presdiff$(four_sixths).png", plot_path, s, h, n, d, "pres_thres", 0, threshold)
plot_state(transpose(pres_arr[five_sixths]), "Pressure Difference", "_presdiff$(five_sixths).png", plot_path, s, h, n, d, "pres_thres", 0, threshold)
plot_state(transpose(pres_arr[six_sixths]), "Pressure Difference", "_presdiff$(six_sixths).png", plot_path, s, h, n, d, "pres_thres", 0, threshold)

# Save step 0
j = 0
@tagsave(joinpath(out_root, savename(@strdict(j), "jld2"; digits=6)),
Dict(
    "sat_arr" => sat_arr,
    "pres_arr" => pres_arr,
    "BHP_arr" => BHP_arr,
    "pres_bound_diff_arr" => pres_bound_diff_arr,
    "BHP_bound_diff_arr" => BHP_bound_diff_arr,
    "pof_iter" => [pof_iter[1]],
    "pof_hard_iter" => [pof_hard_iter[1]],
    "cvar_iter" => [cvar_iter[1]],
    "r_vals" => r_vals0,
    "w_vals" => w_vals0,
    "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step)
    );
safe=true)

# ─────────────────────────────────────────────────────────────────────────────
# Projected GD with backtracking line search
proj(x) = max.(x, 0)
ls = BackTracking(order=3, iterations=10)
step_arr = zeros(niterations)
ex_step_size = 0.1

for j=1:niterations
    function θ(α)
        misfit = objective(proj(inj_rate + α * p), time_step, K, inj_loc, p_max, BHP_max, sat_init; risk=risk_opts)[1]
        @show α, misfit
        return misfit
    end

    stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
    ex_step_size = stp

    step_arr[j] = stp
    inj_rate = proj(inj_rate + stp * p)
    inj_rate_arr[j+1, :] = inj_rate

    obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
    obj_first, obj_arr, pofj_smooth, cvarj, pofj_hard, r_valsj, w_valsj =
        objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init; risk=risk_opts)

    println("Iteration no: ", j, "; Objective (with penalties) = ", obj)

    obj_arr_niter[j+1] = obj
    obj_1_arr[j+1, :]  = obj_first
    obj_arr_arr[j+1, :] = obj_arr

    pof_iter[j+1]      = pofj_smooth
    pof_hard_iter[j+1] = pofj_hard
    cvar_iter[j+1]     = cvarj
    println("Space-time POF_smooth (iter=$j) = ", pofj_smooth)
    println("Space-time POF_hard   (iter=$j) = ", pofj_hard)
    println("Space-time CVaR_", α_tail, " (iter=$j) = ", cvarj)

    grad = grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init; risk=risk_opts)
    p = -grad/norm(grad, Inf)
    grad_arr[j+1, :] = grad

    @tagsave(joinpath(out_root, savename(@strdict(j), "jld2"; digits=6)),
    Dict(
        "sat_arr" => sat_arr,
        "pres_arr" => pres_arr,
        "BHP_arr" => BHP_arr,
        "pres_bound_diff_arr" => pres_bound_diff_arr,
        "BHP_bound_diff_arr" => BHP_bound_diff_arr,
        "pof_iter" => pof_iter[1:j+1],
        "pof_hard_iter" => pof_hard_iter[1:j+1],
        "cvar_iter" => cvar_iter[1:j+1],
        "r_vals" => r_valsj,
        "w_vals" => w_valsj,
        "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step)
        );
    safe=true)

    # plots ...
    plot_state(transpose(sat_arr[one_sixth]),  "CO2 Saturation", "_co2sat$(one_sixth).png",   plot_path, s, h, n, d, "sat", j)
    plot_state(transpose(sat_arr[two_sixths]), "CO2 Saturation", "_co2sat$(two_sixths).png",  plot_path, s, h, n, d, "sat", j)
    plot_state(transpose(sat_arr[three_sixths]), "CO2 Saturation", "_co2sat$(three_sixths).png", plot_path, s, h, n, d, "sat", j)
    plot_state(transpose(sat_arr[four_sixths]), "CO2 Saturation", "_co2sat$(four_sixths).png", plot_path, s, h, n, d, "sat", j)
    plot_state(transpose(sat_arr[five_sixths]), "CO2 Saturation", "_co2sat$(five_sixths).png", plot_path, s, h, n, d, "sat", j)
    plot_state(transpose(sat_arr[six_sixths]),  "CO2 Saturation", "_co2sat$(six_sixths).png",  plot_path, s, h, n, d, "sat", j)

    plot_state(transpose(pres_arr[one_sixth]),  "Pressure", "_pres$(one_sixth).png",  plot_path, s, h, n, d, "pres", j)
    plot_state(transpose(pres_arr[two_sixths]), "Pressure", "_pres$(two_sixths).png", plot_path, s, h, n, d, "pres", j)
    plot_state(transpose(pres_arr[three_sixths]), "Pressure", "_pres$(three_sixths).png", plot_path, s, h, n, d, "pres", j)
    plot_state(transpose(pres_arr[four_sixths]), "Pressure", "_pres$(four_sixths).png", plot_path, s, h, n, d, "pres", j)
    plot_state(transpose(pres_arr[five_sixths]), "Pressure", "_pres$(five_sixths).png", plot_path, s, h, n, d, "pres", j)
    plot_state(transpose(pres_arr[six_sixths]),  "Pressure", "_pres$(six_sixths).png",  plot_path, s, h, n, d, "pres", j)

    plot_state(transpose(pres_arr[one_sixth]),  "Pressure Difference", "_presdiff$(one_sixth).png",  plot_path, s, h, n, d, "pres_thres", j, threshold)
    plot_state(transpose(pres_arr[two_sixths]), "Pressure Difference", "_presdiff$(two_sixths).png", plot_path, s, h, n, d, "pres_thres", j, threshold)
    plot_state(transpose(pres_arr[three_sixths]), "Pressure Difference", "_presdiff$(three_sixths).png", plot_path, s, h, n, d, "pres_thres", j, threshold)
    plot_state(transpose(pres_arr[four_sixths]), "Pressure Difference", "_presdiff$(four_sixths).png", plot_path, s, h, n, d, "pres_thres", j, threshold)
    plot_state(transpose(pres_arr[five_sixths]), "Pressure Difference", "_presdiff$(five_sixths).png", plot_path, s, h, n, d, "pres_thres", j, threshold)
    plot_state(transpose(pres_arr[six_sixths]),  "Pressure Difference", "_presdiff$(six_sixths).png",  plot_path, s, h, n, d, "pres_thres", j, threshold)

    if stp < (inj_rate + init_inj_rate)[1] / 2 * 0.05 / 0.95
        break
    end
    GC.gc()
end

# Save final per-sample outputs
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
    "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step)
    );
safe=true)
