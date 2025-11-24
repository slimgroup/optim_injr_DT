# Threshold sensitivity analysis for relative pressure margin boundary
# Runs optimization for different threshold values and collects results
#
# IMPORTANT: (eps, gamma) CONSISTENCY
# - eps (POF threshold): Target violation probability, e.g., 0.01 = 1%
# - gamma (CVaR threshold): Allowable CVaR level when POF ≈ eps
# - These should be calibrated together before running threshold sensitivity
# - Use --calibrate_gamma to auto-determine gamma for a given eps
# - Or manually set both based on your risk tolerance
# - RECOMMENDED WORKFLOW:
#   1. First, run optimization at a reference threshold with desired eps
#   2. Check the resulting (POF, CVaR) pair at optimal solution
#   3. Use that CVaR value as gamma_cvar
#   4. Then run threshold sensitivity with consistent (eps, gamma) pair
#
# GRADIENT COMPUTATION ANALYSIS:
# - Each iteration computes gradient once via grad_wrt_inj()
# - For central difference (default): 2 objective calls per parameter (fwd + bwd)
# - For forward difference: 2 objective calls per parameter (fwd + cur, but cur can be reused)
# - With 1 parameter (inj_rate[1]): ~2-3 objective calls per gradient
# - Line search adds ~3-10 objective calls per iteration (BackTracking with order=3)
# - Total per iteration: ~5-13 objective calls
# - For niterations=20: ~100-260 objective calls total
#
# CVaR vs POF CONTROL VARIABLES:
# - Both use the SAME r_vals and w_vals (from r_spacetime_distribution)
# - Both use the SAME p_max (determined by threshold)
# - Both use the SAME risk parameters (mode, weight_mode, α, etc.)
# - POF: probability of violation = sum(w[i] where r[i] < 0)
# - CVaR: conditional expectation of losses = E[L | L >= Q_α] where L = max(0, -r)
# - They are DIFFERENT metrics but share the same underlying distribution (r_vals, w_vals)
# - Threshold affects both through p_max: p_max = p0 + threshold * 10^6

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
# Import functions from optim_inject.jl
# Read source file, remove main() call, write to temp file and include
let
    source_file = joinpath(@__DIR__, "optim_inject.jl")
    source_code = read(source_file, String)
    
    # Remove the main() call at the very end (last non-empty line)
    lines = split(source_code, '\n')
    # Find last non-empty line that contains main()
    last_idx = length(lines)
    while last_idx > 0 && isempty(strip(lines[last_idx]))
        last_idx -= 1
    end
    if last_idx > 0 && occursin(r"^\s*main\(\)\s*$", strip(lines[last_idx]))
        lines = lines[1:last_idx-1]
    end
    
    source_code_modified = join(lines, '\n')
    
    # Write to temp file and include
    temp_file = joinpath(@__DIR__, "optim_inject_temp_$(getpid()).jl")
    try
        write(temp_file, source_code_modified)
        include(temp_file)
    finally
        # Clean up temp file
        if isfile(temp_file)
            try
                rm(temp_file)
            catch
                # Ignore cleanup errors
            end
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# CLI
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--idx_num", "-i"
            help = "Index (1-based) into the provided set; selects the geological sample to run"
            arg_type = Int
            default = 128

        "--threshold_min"
            help = "Minimum threshold value (MPa) for sensitivity analysis"
            arg_type = Float64
            default = 2.0

        "--threshold_max"
            help = "Maximum threshold value (MPa) for sensitivity analysis"
            arg_type = Float64
            default = 6.0

        "--threshold_num"
            help = "Number of threshold values to test"
            arg_type = Int
            default = 5

        "--threshold_list"
            help = "Comma-separated list of specific threshold values to test (overrides min/max/num)"
            arg_type = String
            default = ""

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

        # kappa
        "--kappa_pof"
            help = "κ for POF softplus (zero-baseline)"
            arg_type = Float64
            default = 50.0

        "--kappa_cvar"
            help = "κ for CVaR softplus (zero-baseline)"
            arg_type = Float64
            default = 50.0

        # 优化/保存/出图
        "--niterations"
            help = "Max GD iterations"
            arg_type = Int
            default = 20

        "--inj_start"
            help = "起始注入速率（取代全局 init_inj_rate）"
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

        "--calibrate_gamma"
            help = "Auto-calibrate gamma_cvar based on eps_pof using a reference threshold (requires --use_pof and --use_cvar)"
            action = :store_true

        "--calibration_threshold"
            help = "Threshold value to use for gamma calibration (default: first threshold in range)"
            arg_type = Float64
            default = NaN
    end

    return parse_args(s)
end

# ─────────────────────────────────────────────────────────────────────────────
# Helper function: Compute CVaR corresponding to a given POF level
# This helps establish the relationship between eps (POF threshold) and gamma (CVaR threshold)
function compute_cvar_for_pof_level(r_vals::Vector{Float64}, w_vals::Vector{Float64},
                                    target_pof::Float64, α::Float64=0.05)
    """
    Given r_vals and w_vals, find the CVaR value when POF = target_pof.
    This helps determine what gamma should be for a given eps.
    
    Strategy: Find the quantile Q such that POF(Q) = target_pof, then compute CVaR at that level.
    """
    # Sort by r (ascending, so violations are at the beginning)
    perm = sortperm(r_vals)
    r_sorted = r_vals[perm]
    w_sorted = w_vals[perm]
    
    # Find the quantile where cumulative POF = target_pof
    cumsum_w = cumsum(w_sorted)
    idx = findfirst(cumsum_w .>= target_pof)
    
    if idx === nothing
        # If target_pof is larger than total violation probability, use all violations
        L = max.(0.0, .-r_vals)
        cvar, _ = cvar_clean(L, w_vals; α=α)
        return cvar
    end
    
    # Use the quantile at this index as the threshold
    # Then compute CVaR for losses L = max(0, -r) above this quantile
    L = max.(0.0, .-r_vals)
    cvar, _ = cvar_clean(L, w_vals; α=α)
    return cvar
end

# ─────────────────────────────────────────────────────────────────────────────
# Helper function: Run a quick forward pass to determine appropriate gamma for given eps
function calibrate_gamma_for_eps(threshold::Float64, args::Dict{String,Any}, 
                                  eps_target::Float64, α::Float64=0.05;
                                  inj_rate_guess::Float64=0.05)
    """
    Run a single forward simulation to determine what gamma (CVaR threshold) 
    corresponds to a given eps (POF threshold) at a specific threshold.
    
    This helps establish consistent (eps, gamma) pairs before doing full optimization.
    """
    # Setup (similar to run_optimization_for_threshold but minimal)
    s = args["idx_num"]
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
    
    idices = state_data["idx_t" * string(monitoring_step)]
    idx = idices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md
    
    p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ threshold * 10^6
    
    # Initial state
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
    
    risk_mode = args["risk_mode"] == "window" ? :window : :relative
    risk_opts = (
        use_pof = false,  # Just for calibration
        λ_pof   = 0.0,
        ε       = eps_target,
        τ       = args["tau_pof"],
        use_cvar = false,
        λ_cvar   = 0.0,
        γ        = 0.0,
        α        = α,
        mode     = risk_mode,
        weight_mode = (args["weight_mode"] == "uniform" ? :uniform : :voltime),
        cvar_soft = Base.get(args, "cvar_soft", false),
        kappa_pof  = args["kappa_pof"],
        kappa_cvar = args["kappa_cvar"],
        pof_as_constraint  = false,
        cvar_as_constraint = false
    )
    
    time_step = 80 / ds * ones(6 * ds * forward_step)
    inj_loc_grid = (250, 1, inj_y0)
    inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])
    BHP_max = p_max[inj_y0, 250]
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)
    
    # Run one forward pass
    _, _, _, _, _, _, _, _, _, _, _, _, pof_smooth, cvar, pof_hard, r_vals, w_vals =
        objective([inj_rate_guess], time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                  sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                  forward_step=forward_step, ds=ds, collect_states=false,
                  inj_start=args["inj_start"])
    
    # The CVaR at this point gives us an idea of what gamma should be
    # when POF is around eps_target
    return (pof_hard=pof_hard, pof_smooth=pof_smooth, cvar=cvar, 
            suggested_gamma=cvar)  # Use current CVaR as suggested gamma
end

# ─────────────────────────────────────────────────────────────────────────────
# Modified main function that accepts threshold as parameter
function run_optimization_for_threshold(threshold::Float64, args::Dict{String,Any})
    s = args["idx_num"]
    α_tail = args["alpha"]

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
    # ★ Use provided threshold instead of fixed 4.0
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

    # tags/paths
    function scenariotag(risk; step::Int, idx::Int, thresh::Float64)
        parts = String[
            "step$(step)", "idx$(idx)", "thresh=$(thresh)",
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

    sim_name = "DT_control"
    run_tag = scenariotag(risk_opts; step=monitoring_step, idx=s, thresh=threshold)
    exp_layer = "exp_name=step$(monitoring_step)"

    data_root  = datadir(sim_name, exp_layer, "threshold_sensitivity")
    sample_tag = savename(@strdict(sample=s, threshold=threshold); digits=6)
    out_root   = joinpath(data_root, sample_tag)
    mkpath(out_root)

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

    println("Threshold = $(threshold) MPa; Iteration 0; Objective = ", obj)
    println("  base = $(obj_base), penalty = $(pen_total) (pof=$(pen_pof), cvar=$(pen_cvar))")

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
        return (threshold=threshold, final_inj_rate=inj_rate[1], final_obj=obj,
                final_obj_base=obj_base, final_penalty=pen_total,
                final_pof_smooth=pof0_smooth, final_pof_hard=pof0_hard, final_cvar=cvar0,
                converged=false, niter=0)
    end
    p = -grad/gnorm
    grad_arr[1, :] = grad

    # 迭代
    proj(x) = max.(x, 0)
    ls = BackTracking(order=3, iterations=10)
    step_arr = zeros(niterations)
    ex_step_size = 0.1

    for j=1:niterations
        function θ(α)
            objective(proj(inj_rate + α * p), time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
        end

        stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
        ex_step_size = stp

        step_arr[j] = stp
        inj_rate = proj(inj_rate + stp * p)
        inj_rate_arr[j+1, :] = inj_rate

        need_states = save_states || (save_plots && (j % plot_stride == 0 || j == niterations))

        obj, obj_base, pen_total, pen_pof, pen_cvar,
        sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
        obj_first, obj_arr, pofj_smooth, cvarj, pofj_hard, r_valsj, w_valsj =
            objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=pres_init, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=need_states, inj_start=inj_start)

        if j % 5 == 0 || j == niterations
            println("Threshold = $(threshold) MPa; Iteration $j; Objective = ", obj)
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

        if stp < (inj_rate + [inj_start])[1] / 2 * 0.05 / 0.95
            break
        end
        GC.gc()
    end

    # Save results for this threshold
    @tagsave(joinpath(out_root, "final.jld2"),
    Dict(
        "threshold" => threshold,
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
        # ★ Save risk parameters explicitly
        "risk_params" => Dict(
            "use_pof" => risk_opts.use_pof,
            "eps_pof" => risk_opts.use_pof ? risk_opts.ε : nothing,
            "tau_pof" => risk_opts.use_pof ? risk_opts.τ : nothing,
            "lambda_pof" => risk_opts.use_pof ? risk_opts.λ_pof : nothing,
            "pof_as_constraint" => risk_opts.pof_as_constraint,
            "use_cvar" => risk_opts.use_cvar,
            "gamma_cvar" => risk_opts.use_cvar ? risk_opts.γ : nothing,
            "alpha_cvar" => risk_opts.use_cvar ? risk_opts.α : nothing,
            "lambda_cvar" => risk_opts.use_cvar ? risk_opts.λ_cvar : nothing,
            "cvar_as_constraint" => risk_opts.cvar_as_constraint,
            "cvar_soft" => risk_opts.cvar_soft,
            "risk_mode" => String(risk_opts.mode),
            "weight_mode" => String(risk_opts.weight_mode)
        ),
        "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step, threshold=threshold)
        );
    safe=true)

    final_iter = findlast(!isnan, pof_iter)
    final_iter = final_iter === nothing ? 1 : final_iter

    return (threshold=threshold,
            final_inj_rate=inj_rate[1],
            final_obj=obj_arr_niter[final_iter],
            final_obj_base=obj_base_arr[final_iter],
            final_penalty=pen_total_arr[final_iter],
            final_pof_smooth=pof_iter[final_iter],
            final_pof_hard=pof_hard_iter[final_iter],
            final_cvar=cvar_iter[final_iter],
            converged=(gnorm > 0),
            niter=final_iter)
end

# ─────────────────────────────────────────────────────────────────────────────
# Main sensitivity analysis
function main()
    args = parse_commandline()
    
    # Determine threshold values
    if args["threshold_list"] != ""
        # Use provided list
        threshold_values = [parse(Float64, x) for x in split(args["threshold_list"], ",")]
    else
        # Generate range
        threshold_min = args["threshold_min"]
        threshold_max = args["threshold_max"]
        threshold_num = args["threshold_num"]
        threshold_values = collect(range(threshold_min, threshold_max, length=threshold_num))
    end

    println("=" ^ 80)
    println("Threshold Sensitivity Analysis")
    println("=" ^ 80)
    println("Testing thresholds: ", threshold_values)
    println("Number of thresholds: ", length(threshold_values))
    println()
    
    # ★ CALIBRATION: If user wants to calibrate gamma for eps, do it first
    eps_pof = args["eps_pof"]
    gamma_cvar = args["gamma_cvar"]
    alpha_tail = args["alpha"]
    use_cvar = Base.get(args, "use_cvar", false)
    use_pof = Base.get(args, "use_pof", false)
    
    # ★ CALIBRATION: Auto-calibrate gamma for eps if requested
    if Base.get(args, "calibrate_gamma", false) && use_pof && use_cvar
        println("─" ^ 80)
        println("CALIBRATION: Determining gamma_cvar for eps_pof = $(eps_pof)")
        println("─" ^ 80)
        
        calib_thresh = args["calibration_threshold"]
        if isnan(calib_thresh)
            calib_thresh = threshold_values[1]  # Use first threshold
        end
        
        println("Running calibration forward pass at threshold = $(calib_thresh) MPa...")
        try
            calib_result = calibrate_gamma_for_eps(calib_thresh, args, eps_pof, alpha_tail;
                                                   inj_rate_guess=args["inj_guess"])
            suggested_gamma = calib_result.suggested_gamma
            
            println("Calibration results:")
            println("  At threshold = $(calib_thresh) MPa, with inj_rate ≈ $(args["inj_guess"]):")
            println("    POF (hard) = $(calib_result.pof_hard)")
            println("    POF (smooth) = $(calib_result.pof_smooth)")
            println("    CVaR = $(calib_result.cvar)")
            println()
            println("  → Suggested gamma_cvar ≈ $(suggested_gamma)")
            println("     (This is the CVaR value when POF is near eps_pof = $(eps_pof))")
            println()
            println("  ⚠️  NOTE: This is a rough estimate. For accurate calibration:")
            println("     1. Run optimization to convergence at a reference threshold")
            println("     2. Check the actual (POF, CVaR) pair at the optimal solution")
            println("     3. Use that CVaR value as gamma_cvar")
            println()
            
            # Update args with suggested gamma
            if gamma_cvar == 0.0
                args["gamma_cvar"] = suggested_gamma
                gamma_cvar = suggested_gamma
                println("  ✓ Auto-updated gamma_cvar to $(suggested_gamma)")
            else
                println("  ⚠️  gamma_cvar was already set to $(gamma_cvar), not overwriting")
            end
            println()
        catch e
            @warn "Calibration failed" exception=(e, catch_backtrace())
            println("  ⚠️  Calibration failed. Proceeding with gamma_cvar = $(gamma_cvar)")
            println()
        end
    elseif use_pof && use_cvar && gamma_cvar == 0.0
        println("⚠️  WARNING: POF and CVaR both enabled, but gamma_cvar = 0.0")
        println("   Consider using --calibrate_gamma to auto-determine gamma for eps_pof = $(eps_pof)")
        println("   Or set --gamma_cvar manually based on your risk tolerance.")
        println()
    elseif use_pof && eps_pof > 0 && use_cvar && gamma_cvar > 0.0
        println("ℹ️  Using (eps, gamma) = ($(eps_pof), $(gamma_cvar))")
        println("   Make sure these values are consistent for your risk tolerance.")
        println()
    end
    
    # Print and save (eps, gamma) settings
    println("=" ^ 80)
    println("RISK PARAMETER SETTINGS:")
    println("=" ^ 80)
    if use_pof
        println("  ✓ POF enabled:")
        println("     eps (ε) = $(eps_pof)  (target violation probability = $(eps_pof*100)%)")
        println("     tau (τ) = $(args["tau_pof"])  (smoothing temperature)")
        println("     kappa_pof = $(args["kappa_pof"])")
        if Base.get(args, "pof_as_constraint", false)
            println("     → Used as HARD constraint")
        else
            println("     → Used as SOFT penalty (lambda_pof = $(args["lambda_pof"]))")
        end
    else
        println("  ✗ POF disabled")
        println("     (Default eps = 0.01 if enabled, but currently NOT USED)")
    end
    println()
    if use_cvar
        println("  ✓ CVaR enabled:")
        println("     gamma (γ) = $(gamma_cvar)  (allowable CVaR level)")
        println("     alpha (α) = $(alpha_tail)  (tail level = $(alpha_tail*100)%)")
        println("     kappa_cvar = $(args["kappa_cvar"])")
        if Base.get(args, "cvar_soft", false)
            println("     → Using softplus smoothing")
        else
            println("     → Using hinge (no smoothing)")
        end
        if Base.get(args, "cvar_as_constraint", false)
            println("     → Used as HARD constraint")
        else
            println("     → Used as SOFT penalty (lambda_cvar = $(args["lambda_cvar"]))")
        end
        # Warning if gamma seems misaligned with eps
        if use_pof && gamma_cvar == 0.0 && eps_pof > 0
            println()
            println("     ⚠️  WARNING: gamma = 0.0 may be too strict for eps = $(eps_pof)")
            println("        Consider using --calibrate_gamma to find appropriate gamma")
        end
    else
        println("  ✗ CVaR disabled")
        println("     (Default gamma = 0.0 if enabled, but currently NOT USED)")
    end
    println("=" ^ 80)
    println()
    
    # Alignment check - only relevant if BOTH are enabled
    if use_pof && use_cvar
        println("⚠️  ALIGNMENT CHECK:")
        println("   Current (eps, gamma) = ($(eps_pof), $(gamma_cvar))")
        if gamma_cvar == 0.0 && eps_pof > 0
            println("   ⚠️  gamma = 0.0 is likely too strict for eps = $(eps_pof)")
            println("   → These values may NOT be aligned!")
            println("   → Recommendation: Use --calibrate_gamma or set gamma manually")
        else
            println("   → Values set, but alignment should be verified")
        end
        println()
    elseif !use_pof && !use_cvar
        println("ℹ️  NOTE: Both POF and CVaR are disabled for optimization.")
        println("   → No risk constraints/penalties are applied to the objective function")
        println("   → Optimization only maximizes CO2 injection (no risk penalties)")
        println()
        println("   ✓ IMPORTANT: POF and CVaR values ARE STILL COMPUTED and saved!")
        println("   → They are calculated at each iteration and stored in results")
        println("   → This enables sensitivity analysis: how POF/CVaR respond to threshold t")
        println("   → You can analyze: POF(t), CVaR(t) even though they don't affect optimization")
        println()
        println("   → Alignment (eps, gamma) is NOT relevant for optimization")
        println("     (since these values don't affect the objective)")
        println("   → But you can still plot and analyze POF/CVaR sensitivity to threshold")
        println()
    elseif use_pof && !use_cvar
        println("ℹ️  NOTE: Only POF is enabled, CVaR is disabled.")
        println("   → Alignment is NOT relevant (only POF is used)")
        println()
    elseif !use_pof && use_cvar
        println("ℹ️  NOTE: Only CVaR is enabled, POF is disabled.")
        println("   → Alignment is NOT relevant (only CVaR is used)")
        println()
    end
    
    # Save risk parameters to a separate file for easy reference
    s = args["idx_num"]
    risk_params_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                               "risk_params__sample=$(s).jld2")
    mkpath(dirname(risk_params_path))
    
    risk_params_dict = Dict(
        "use_pof" => use_pof,
        "eps_pof" => use_pof ? eps_pof : nothing,
        "tau_pof" => use_pof ? args["tau_pof"] : nothing,
        "kappa_pof" => use_pof ? args["kappa_pof"] : nothing,
        "lambda_pof" => use_pof ? args["lambda_pof"] : nothing,
        "pof_as_constraint" => use_pof ? Base.get(args, "pof_as_constraint", false) : false,
        
        "use_cvar" => use_cvar,
        "gamma_cvar" => use_cvar ? gamma_cvar : nothing,
        "alpha_cvar" => use_cvar ? alpha_tail : nothing,
        "kappa_cvar" => use_cvar ? args["kappa_cvar"] : nothing,
        "lambda_cvar" => use_cvar ? args["lambda_cvar"] : nothing,
        "cvar_soft" => use_cvar ? Base.get(args, "cvar_soft", false) : false,
        "cvar_as_constraint" => use_cvar ? Base.get(args, "cvar_as_constraint", false) : false,
        
        "risk_mode" => args["risk_mode"],
        "weight_mode" => args["weight_mode"],
        "idx_num" => s,
        "timestamp" => now()
    )
    
    @tagsave(risk_params_path, risk_params_dict; safe=true)
    println("✓ Risk parameters saved to: ", risk_params_path)
    println()

    # Run optimization for each threshold
    results = []
    for (i, thresh) in enumerate(threshold_values)
        println("\n" * "─" ^ 80)
        println("Running optimization for threshold = $(thresh) MPa ($(i)/$(length(threshold_values)))")
        println("─" ^ 80)
        
        try
            result = run_optimization_for_threshold(thresh, args)
            push!(results, result)
            println("✓ Completed: threshold=$(thresh), final_inj_rate=$(result.final_inj_rate), final_obj=$(result.final_obj)")
        catch e
            @warn "Failed for threshold=$(thresh)" exception=(e, catch_backtrace())
            push!(results, (threshold=thresh, final_inj_rate=NaN, final_obj=NaN,
                           final_obj_base=NaN, final_penalty=NaN,
                           final_pof_smooth=NaN, final_pof_hard=NaN, final_cvar=NaN,
                           converged=false, niter=0))
        end
    end

    # Collect results into arrays
    thresholds = [r.threshold for r in results]
    final_inj_rates = [r.final_inj_rate for r in results]
    final_objs = [r.final_obj for r in results]
    final_obj_bases = [r.final_obj_base for r in results]
    final_penalties = [r.final_penalty for r in results]
    final_pof_smooth = [r.final_pof_smooth for r in results]
    final_pof_hard = [r.final_pof_hard for r in results]
    final_cvar = [r.final_cvar for r in results]
    converged = [r.converged for r in results]
    niters = [r.niter for r in results]

    # Save summary results
    s = args["idx_num"]
    summary_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                          "summary__sample=$(s).jld2")
    mkpath(dirname(summary_path))
    
    @tagsave(summary_path,
    Dict(
        "thresholds" => thresholds,
        "final_inj_rates" => final_inj_rates,
        "final_objs" => final_objs,
        "final_obj_bases" => final_obj_bases,
        "final_penalties" => final_penalties,
        "final_pof_smooth" => final_pof_smooth,
        "final_pof_hard" => final_pof_hard,
        "final_cvar" => final_cvar,
        "converged" => converged,
        "niters" => niters,
        "args" => args,
        # ★ Save risk parameters explicitly for easy access
        "risk_params" => Dict(
            "use_pof" => use_pof,
            "eps_pof" => use_pof ? eps_pof : nothing,
            "tau_pof" => use_pof ? args["tau_pof"] : nothing,
            "lambda_pof" => use_pof ? args["lambda_pof"] : nothing,
            "pof_as_constraint" => use_pof ? Base.get(args, "pof_as_constraint", false) : false,
            "use_cvar" => use_cvar,
            "gamma_cvar" => use_cvar ? gamma_cvar : nothing,
            "alpha_cvar" => use_cvar ? alpha_tail : nothing,
            "lambda_cvar" => use_cvar ? args["lambda_cvar"] : nothing,
            "cvar_as_constraint" => use_cvar ? Base.get(args, "cvar_as_constraint", false) : false,
            "cvar_soft" => use_cvar ? Base.get(args, "cvar_soft", false) : false,
            "risk_mode" => args["risk_mode"],
            "weight_mode" => args["weight_mode"]
        ),
        "meta" => (idx=s, timestamp=now())
    );
    safe=true)

    println("\n" * "=" ^ 80)
    println("Sensitivity Analysis Complete")
    println("=" ^ 80)
    println("Summary saved to: ", summary_path)
    println()

    # Print summary table
    println("=" ^ 80)
    println("RESULTS SUMMARY")
    println("=" ^ 80)
    println("Risk parameters used:")
    if use_pof
        println("  POF: eps = $(eps_pof)")
    end
    if use_cvar
        println("  CVaR: gamma = $(gamma_cvar), alpha = $(alpha_tail)")
    end
    println()
    println("─" ^ 80)
    println(@sprintf("%-12s %-15s %-15s %-12s %-12s %-12s",
                     "Threshold", "Inj Rate", "Objective", "POF (smooth)", "POF (hard)", "CVaR"))
    println("─" ^ 80)
    for i in eachindex(thresholds)
        println(@sprintf("%-12.2f %-15.6e %-15.6e %-12.6f %-12.6f %-12.6f",
                         thresholds[i], final_inj_rates[i], final_objs[i],
                         final_pof_smooth[i], final_pof_hard[i], final_cvar[i]))
    end
    println("─" ^ 80)
    println()

    # Create visualization plots
    try
        plot_path = plotsdir("DT_control", "exp_name=step1", "threshold_sensitivity")
        mkpath(plot_path)

        # Plot 1: Injection rate vs threshold
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_inj_rates, "o-", linewidth=2, markersize=8)
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("Optimal Injection Rate", fontsize=14)
        ax.set_title("Optimal Injection Rate vs Threshold", fontsize=16)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "inj_rate_vs_threshold__sample=$(s).png"), fig)
        close(fig)

        # Plot 2: Objective vs threshold
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_objs, "o-", linewidth=2, markersize=8, label="Total Objective")
        ax.plot(thresholds, final_obj_bases, "s--", linewidth=2, markersize=6, label="Base Objective")
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("Objective Value", fontsize=14)
        ax.set_title("Objective vs Threshold", fontsize=16)
        ax.legend(fontsize=12)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "objective_vs_threshold__sample=$(s).png"), fig)
        close(fig)

        # Plot 3: POF vs threshold
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_pof_smooth, "o-", linewidth=2, markersize=8, label="POF (smooth)")
        ax.plot(thresholds, final_pof_hard, "s--", linewidth=2, markersize=6, label="POF (hard)")
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("Probability of Failure", fontsize=14)
        ax.set_title("POF vs Threshold", fontsize=16)
        ax.legend(fontsize=12)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "pof_vs_threshold__sample=$(s).png"), fig)
        close(fig)

        # Plot 4: CVaR vs threshold
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_cvar, "o-", linewidth=2, markersize=8)
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("CVaR", fontsize=14)
        ax.set_title("CVaR vs Threshold", fontsize=16)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "cvar_vs_threshold__sample=$(s).png"), fig)
        close(fig)

        # Plot 5: Combined view
        fig, axes = subplots(2, 2, figsize=(14, 10))
        
        axes[1,1].plot(thresholds, final_inj_rates, "o-", linewidth=2, markersize=8)
        axes[1,1].set_xlabel("Threshold t (MPa)", fontsize=12)
        axes[1,1].set_ylabel("Optimal Injection Rate", fontsize=12)
        axes[1,1].set_title("Injection Rate", fontsize=14)
        axes[1,1].grid(true, alpha=0.3)

        axes[1,2].plot(thresholds, final_objs, "o-", linewidth=2, markersize=8, label="Total")
        axes[1,2].plot(thresholds, final_obj_bases, "s--", linewidth=1.5, markersize=5, label="Base")
        axes[1,2].set_xlabel("Threshold t (MPa)", fontsize=12)
        axes[1,2].set_ylabel("Objective Value", fontsize=12)
        axes[1,2].set_title("Objective", fontsize=14)
        axes[1,2].legend(fontsize=10)
        axes[1,2].grid(true, alpha=0.3)

        axes[2,1].plot(thresholds, final_pof_smooth, "o-", linewidth=2, markersize=8, label="Smooth")
        axes[2,1].plot(thresholds, final_pof_hard, "s--", linewidth=1.5, markersize=5, label="Hard")
        axes[2,1].set_xlabel("Threshold t (MPa)", fontsize=12)
        axes[2,1].set_ylabel("POF", fontsize=12)
        axes[2,1].set_title("Probability of Failure", fontsize=14)
        axes[2,1].legend(fontsize=10)
        axes[2,1].grid(true, alpha=0.3)

        axes[2,2].plot(thresholds, final_cvar, "o-", linewidth=2, markersize=8)
        axes[2,2].set_xlabel("Threshold t (MPa)", fontsize=12)
        axes[2,2].set_ylabel("CVaR", fontsize=12)
        axes[2,2].set_title("CVaR", fontsize=14)
        axes[2,2].grid(true, alpha=0.3)

        plt.tight_layout()
        safesave(joinpath(plot_path, "sensitivity_summary__sample=$(s).png"), fig)
        close(fig)

        println("Plots saved to: ", plot_path)
    catch e
        @warn "Plotting failed" exception=(e, catch_backtrace())
    end
end

main()

