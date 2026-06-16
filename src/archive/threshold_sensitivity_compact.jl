# Threshold sensitivity analysis: runs optimization for different pressure thresholds
# Key concepts:
# - eps (POF threshold): Target violation probability (e.g., 0.01 = 1%)
# - gamma (CVaR threshold): Allowable CVaR level when POF ≈ eps
# - Use --calibrate_gamma to auto-determine gamma for a given eps

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules, LinearAlgebra, PyPlot, SlimOptim, JLD2, Random, PyCall
using SlimPlotting, ArgParse, StatsBase, Dates, Printf, Base.Threads
@pyimport cmasher

include("utils.jl")
setup_pycall()

# Import functions from optim_inject.jl
let
    source_file = joinpath(@__DIR__, "optim_inject.jl")
    source_code = read(source_file, String)
    lines = split(source_code, '\n')
    last_idx = length(lines)
    while last_idx > 0 && isempty(strip(lines[last_idx]))
        last_idx -= 1
    end
    if last_idx > 0 && occursin(r"^\s*main\(\)\s*$", strip(lines[last_idx]))
        lines = lines[1:last_idx-1]
    end
    temp_file = joinpath(@__DIR__, "optim_inject_temp_$(getpid()).jl")
    try
        write(temp_file, join(lines, '\n'))
        include(temp_file)
    finally
        isfile(temp_file) && try rm(temp_file) catch end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# CLI Parsing
# ─────────────────────────────────────────────────────────────────────────────
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--idx_num", "-i"; arg_type=Int; default=128; help="Geological sample index"
        "--threshold_min"; arg_type=Float64; default=2.0; help="Min threshold (MPa)"
        "--threshold_max"; arg_type=Float64; default=6.0; help="Max threshold (MPa)"
        "--threshold_num"; arg_type=Int; default=5; help="Number of thresholds"
        "--threshold_list"; arg_type=String; default=""; help="Comma-separated threshold list"
        "--gamma_table_generate"; arg_type=String; default=""; help="Generate gamma table and exit"
        "--gamma_table_eps_list"; arg_type=String; default=""; help="Eps values for gamma table"
        "--gamma_table_path"; arg_type=String; default=""; help="Path to gamma lookup table"
        "--gamma_table_eps"; arg_type=Float64; default=NaN; help="Eps entry to use from table"
        "--gamma_table_strict"; action=:store_true; help="Error if threshold missing"
        "--split_threshold_jobs"; action=:store_true; help="Single threshold per invocation"
        "--split_job_index"; arg_type=Int; default=1; help="Threshold index (1-based)"
        "--split_job_total"; arg_type=Int; default=1; help="Total thresholds (for logging)"
        "--merge_results"; action=:store_true; help="Merge with existing summary"
        "--alpha"; arg_type=Float64; default=0.05; help="CVaR tail level"
        "--use_pof"; action=:store_true; help="Include POF penalty"
        "--lambda_pof"; arg_type=Float64; default=0.0; help="POF weight"
        "--eps_pof"; arg_type=Float64; default=0.01; help="Target POF"
        "--tau_pof"; arg_type=Float64; default=0.05; help="POF smoothing"
        "--use_cvar"; action=:store_true; help="Include CVaR penalty"
        "--lambda_cvar"; arg_type=Float64; default=0.0; help="CVaR weight"
        "--gamma_cvar"; arg_type=Float64; default=0.0; help="Allowable CVaR level"
        "--risk_mode"; arg_type=String; default="relative"; help="Risk mode: relative|window"
        "--weight_mode"; arg_type=String; default="voltime"; help="Weighting: voltime|uniform"
        "--cvar_soft"; action=:store_true; help="Use softplus-smoothed CVaR"
        "--pof_as_constraint"; action=:store_true; help="POF as hard constraint"
        "--cvar_as_constraint"; action=:store_true; help="CVaR as hard constraint"
        "--kappa_pof"; arg_type=Float64; default=50.0; help="POF softplus kappa"
        "--kappa_cvar"; arg_type=Float64; default=50.0; help="CVaR softplus kappa"
        "--niterations"; arg_type=Int; default=20; help="Max GD iterations"
        "--inj_start"; arg_type=Float64; default=0.0001; help="Starting injection rate"
        "--inj_guess"; arg_type=Float64; default=0.05; help="Initial guess injection rate"
        "--save_plots"; action=:store_true; help="Save plots during optimization"
        "--plot_stride"; arg_type=Int; default=5; help="Plot every k iterations"
        "--save_states"; action=:store_true; help="Persist state arrays"
        "--save_every"; arg_type=Int; default=1; help="Save JLD2 every k iterations"
        "--grad_forward"; action=:store_true; help="Use forward-diff FD gradient"
        "--calibrate_gamma"; action=:store_true; help="Auto-calibrate gamma_cvar"
        "--calibration_threshold"; arg_type=Float64; default=NaN; help="Threshold for calibration"
    end
    return parse_args(s)
end

# ─────────────────────────────────────────────────────────────────────────────
# Gamma Calibration
# ─────────────────────────────────────────────────────────────────────────────
function calibrate_gamma_for_eps(threshold::Float64, args::Dict{String,Any}, 
                                  eps_target::Float64, α::Float64=0.05;
                                  inj_rate_guess::Float64=0.05,
                                  BroadK=nothing, state_data=nothing)
    s = args["idx_num"]
    n, d, h, ϕ, ds, forward_step = (512, 1, 256), (6.25, 100.0, 6.25), 0.0, 0.25, 10, 2
    
    if BroadK === nothing
        perm_data = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"))
        BroadK = perm_data["BroadK"]
    end
    if state_data === nothing
        monitoring_step = 1
        state_data = JLD2.load(datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2"))
    end
    
    idices = state_data["idx_t1"]
    idx = idices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md
    p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ threshold * 10^6
    
    inj_y0 = 191 + argmax(K[250, 191:200]) - 1
    S0 = zeros(Float64, n[1], n[end])
    Random.seed!(2025 + s - 1 + Base.Threads.threadid() * 10000)
    value = 0.2 + rand(Float64) * 0.6
    for (dy, rows) in [(-4, 249:251), (-3, 248:252), (-2, 247:253), (-1, 246:254), (0, 246:254), (1, 246:254), (2, 247:253), (3, 248:252), (4, 249:251)]
        S0[rows, inj_y0+dy] .= value
    end
    sat_init = S0
    
    risk_mode = args["risk_mode"] == "window" ? :window : :relative
    risk_opts = (
        use_pof=false, λ_pof=0.0, ε=eps_target, τ=args["tau_pof"],
        use_cvar=false, λ_cvar=0.0, γ=0.0, α=α,
        mode=risk_mode, weight_mode=(args["weight_mode"] == "uniform" ? :uniform : :voltime),
        cvar_soft=Base.get(args, "cvar_soft", false),
        kappa_pof=args["kappa_pof"], kappa_cvar=args["kappa_cvar"],
        pof_as_constraint=false, cvar_as_constraint=false
    )
    
    time_step = 80 / ds * ones(6 * ds * forward_step)
    inj_loc_grid = (250, 1, inj_y0)
    inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])
    BHP_max = p_max[inj_y0, 250]
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)
    
    function evaluate_pof(inj_rate_val)
        _, _, _, _, _, _, _, _, _, _, _, _, pof_smooth, cvar, pof_hard, _, _ =
            objective([inj_rate_val], time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=false,
                      inj_start=args["inj_start"])
        return pof_hard, cvar, pof_smooth
    end
    
    tol = max(0.0001, eps_target * 0.05)
    max_iter = 30
    inj_low, inj_high = 0.0001, 2.0
    
    pof_init, cvar_init, pof_smooth_init = evaluate_pof(inj_rate_guess)
    if abs(pof_init - eps_target) <= tol
        return (pof_hard=pof_init, pof_smooth=pof_smooth_init, cvar=cvar_init, suggested_gamma=cvar_init)
    end
    
    # Find bounds
    if pof_init < eps_target
        test_inj = inj_rate_guess
        while test_inj < inj_high && pof_init < eps_target
            test_inj *= 2.0
            pof_init, cvar_init, pof_smooth_init = evaluate_pof(test_inj)
            if pof_init >= eps_target
                inj_high = test_inj
                break
            end
        end
        if pof_init < eps_target
            return (pof_hard=pof_init, pof_smooth=pof_smooth_init, cvar=cvar_init, suggested_gamma=cvar_init)
        end
        inj_low = inj_rate_guess
    else
        test_inj = inj_rate_guess
        while test_inj > inj_low && pof_init > eps_target
            test_inj /= 2.0
            test_inj = max(test_inj, inj_low)
            pof_init, cvar_init, pof_smooth_init = evaluate_pof(test_inj)
            if pof_init <= eps_target
                inj_low = test_inj
                break
            end
        end
        if pof_init > eps_target && test_inj <= inj_low
            return (pof_hard=pof_init, pof_smooth=pof_smooth_init, cvar=cvar_init, suggested_gamma=cvar_init)
        end
        inj_high = inj_rate_guess
    end
    
    # Binary search
    best_inj, best_pof, best_cvar, best_error = inj_rate_guess, pof_init, cvar_init, abs(pof_init - eps_target)
    for iter in 1:max_iter
        inj_mid = (inj_low + inj_high) / 2
        pof_mid, cvar_mid, pof_smooth_mid = evaluate_pof(inj_mid)
        error_mid = abs(pof_mid - eps_target)
        
        if error_mid < best_error
            best_inj, best_pof, best_cvar, best_error = inj_mid, pof_mid, cvar_mid, error_mid
        end
        
        if error_mid <= tol
            return (pof_hard=pof_mid, pof_smooth=pof_smooth_mid, cvar=cvar_mid, suggested_gamma=cvar_mid)
        elseif pof_mid > eps_target
            inj_high = inj_mid
        else
            inj_low = inj_mid
        end
        
        if (inj_high - inj_low) < 1e-6
            return (pof_hard=best_pof, pof_smooth=best_pof, cvar=best_cvar, suggested_gamma=best_cvar)
        end
    end
    return (pof_hard=best_pof, pof_smooth=best_pof, cvar=best_cvar, suggested_gamma=best_cvar)
end

function generate_gamma_table(threshold_values::Vector{Float64}, eps_values::Vector{Float64}, args::Dict{String,Any})
    alpha_tail = args["alpha"]
    println("=" ^ 80)
    println("Generating gamma lookup table (PARALLEL)")
    println("Thresholds: ", threshold_values, " | Eps: ", eps_values)
    println("Using $(nthreads()) threads")
    println()
    
    tasks = [(eps, thresh) for eps in eps_values for thresh in threshold_values]
    entries_lock = ReentrantLock()
    entries = Dict(eps => Dict{Float64,NamedTuple{(:gamma,:pof,:cvar),NTuple{3,Float64}}}() for eps in eps_values)
    print_lock = ReentrantLock()
    jutul_lock = ReentrantLock()
    
    println("Pre-loading data files...")
    perm_data = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"))
    BroadK_shared = perm_data["BroadK"]
    monitoring_step = 1
    state_data_shared = JLD2.load(datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2"))
    println("Data files loaded.")
    println()
    
    @threads for (eps, thresh) in tasks
        thread_id = threadid()
        lock(print_lock) do
            println("[Thread $(thread_id)] Processing: eps=$(eps), threshold=$(thresh) MPa")
        end
        
        result = lock(jutul_lock) do
            calibrate_gamma_for_eps(thresh, args, eps, alpha_tail;
                                   inj_rate_guess=args["inj_guess"],
                                   BroadK=BroadK_shared, state_data=state_data_shared)
        end
        
        lock(entries_lock) do
            entries[eps][thresh] = (gamma=result.suggested_gamma, pof=result.pof_hard, cvar=result.cvar)
        end
        
        lock(print_lock) do
            println("[Thread $(thread_id)] ✓ eps=$(eps), threshold=$(thresh) MPa, gamma ≈ $(result.suggested_gamma)")
        end
    end
    
    println("=" ^ 80)
    println("Gamma table generation completed")
    println("=" ^ 80)
    
    return Dict(
        "gamma_entries" => entries,
        "eps_values" => eps_values,
        "thresholds" => threshold_values,
        "meta" => (idx=args["idx_num"], alpha=alpha_tail, timestamp=now(),
                  inj_guess=args["inj_guess"], version="2.1", nthreads=nthreads())
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Optimization
# ─────────────────────────────────────────────────────────────────────────────
function run_optimization_for_threshold(threshold::Float64, args::Dict{String,Any};
                                        gamma_override::Union{Nothing,Float64}=nothing,
                                        eps_override::Union{Nothing,Float64}=nothing)
    s = args["idx_num"]
    α_tail = args["alpha"]
    n, d, h, ϕ, ds, forward_step = (512, 1, 256), (6.25, 100.0, 6.25), 0.0, 0.25, 10, 2
    
    perm_data = JLD2.load(datadir("geo/wise_perm_models_2000_new.jld2"))
    BroadK = perm_data["BroadK"]
    monitoring_step = 1
    state_data = JLD2.load(datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2"))
    
    risk_mode = args["risk_mode"] == "window" ? :window : :relative
    idices = state_data["idx_t" * string(monitoring_step)]
    idx = idices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md
    p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ threshold * 10^6
    
    inj_y0 = 191 + argmax(K[250, 191:200]) - 1
    S0 = zeros(Float64, n[1], n[end])
    Random.seed!(2025 + s - 1)
    value = 0.2 + rand(Float64) * 0.6
    for (dy, rows) in [(-4, 249:251), (-3, 248:252), (-2, 247:253), (-1, 246:254), (0, 246:254), (1, 246:254), (2, 247:253), (3, 248:252), (4, 249:251)]
        S0[rows, inj_y0+dy] .= value
    end
    sat_init = S0
    
    eps_value = isnothing(eps_override) ? args["eps_pof"] : eps_override
    gamma_value = isnothing(gamma_override) ? args["gamma_cvar"] : gamma_override
    risk_opts = (
        use_pof=Base.get(args, "use_pof", false), λ_pof=args["lambda_pof"], ε=eps_value, τ=args["tau_pof"],
        use_cvar=Base.get(args, "use_cvar", false), λ_cvar=args["lambda_cvar"], γ=gamma_value, α=α_tail,
        mode=risk_mode, weight_mode=(args["weight_mode"] == "uniform" ? :uniform : :voltime),
        cvar_soft=Base.get(args, "cvar_soft", false),
        kappa_pof=args["kappa_pof"], kappa_cvar=args["kappa_cvar"],
        pof_as_constraint=Base.get(args, "pof_as_constraint", false),
        cvar_as_constraint=Base.get(args, "cvar_as_constraint", false)
    )
    
    function scenariotag(risk; step::Int, idx::Int, thresh::Float64)
        parts = String[
            "step$(step)", "idx$(idx)", "thresh=$(thresh)",
            risk.use_pof ? "POF" : "", risk.use_cvar ? "CVaR" : "",
            ((risk.pof_as_constraint || risk.cvar_as_constraint) ? "HARD" : "SOFT"),
            risk.use_pof ? "eps=$(risk.ε)" : "", risk.use_pof ? "tau=$(risk.τ)" : "",
            risk.use_cvar ? "alpha=$(risk.α)" : "", risk.use_cvar ? "gamma=$(risk.γ)" : "",
            "w=$(String(risk.weight_mode))", "mode=$(String(risk.mode))",
            risk.cvar_soft ? "cvarsoft" : "cvarhinge",
            "kp=$(risk.kappa_pof)", "kc=$(risk.kappa_cvar)"
        ]
        join(filter(!isempty, parts), "__")
    end
    
    sim_name = "DT_control"
    run_tag = scenariotag(risk_opts; step=monitoring_step, idx=s, thresh=threshold)
    exp_layer = "exp_name=step$(monitoring_step)"
    data_root = datadir(sim_name, exp_layer, "threshold_sensitivity")
    sample_tag = savename(@strdict(sample=s, threshold=threshold); digits=6)
    out_root = joinpath(data_root, sample_tag)
    mkpath(out_root)
    
    time_step = 80 / ds * ones(6 * ds * forward_step)
    inj_rate = [args["inj_guess"]]
    δinj = 1e-8 * ones(size(inj_rate, 1))
    inj_start = args["inj_start"]
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc_grid = (250, 1, inj_y)
    inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])
    BHP_max = p_max[inj_y, 250]
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)
    
    niterations = args["niterations"]
    save_plots = Base.get(args, "save_plots", false)
    plot_stride = args["plot_stride"]
    save_every = args["save_every"]
    save_states = Base.get(args, "save_states", false)
    use_forward = Base.get(args, "grad_forward", false)
    
    inj_rate_arr = zeros(Float64, niterations+1, size(inj_rate, 1))
    inj_rate_arr[1, :] = inj_rate
    obj_arr_niter = zeros(Float64, niterations+1)
    obj_1_arr = zeros(Float64, niterations+1, forward_step * 6)
    obj_arr_arr = zeros(Float64, niterations+1, forward_step * 6)
    grad_arr = zeros(Float64, niterations+1, size(inj_rate, 1))
    pof_iter = fill(NaN, niterations+1)
    pof_hard_iter = fill(NaN, niterations+1)
    cvar_iter = fill(NaN, niterations+1)
    obj_base_arr = zeros(Float64, niterations+1)
    pen_total_arr = zeros(Float64, niterations+1)
    pen_pof_arr = zeros(Float64, niterations+1)
    pen_cvar_arr = zeros(Float64, niterations+1)
    
    function first_forward!(inj_rate)
        obj, obj_base, pen_total, pen_pof, pen_cvar, sat_arr, pres_arr, BHP_arr,
        pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_arr, pof_smooth0, cvar0,
        pof_hard0, r_vals0, w_vals0 =
            objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=(save_states || save_plots),
                      inj_start=inj_start)
        
        while obj == Inf
            inj_rate .*= 0.8
            inj_rate[1] = max(inj_rate[1], 0.0001)
            obj, obj_base, pen_total, pen_pof, pen_cvar, sat_arr, pres_arr, BHP_arr,
            pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_arr, pof_smooth0, cvar0,
            pof_hard0, r_vals0, w_vals0 =
                objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                          sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                          forward_step=forward_step, ds=ds, collect_states=(save_states || save_plots),
                          inj_start=inj_start)
        end
        return obj, obj_base, pen_total, pen_pof, pen_cvar, sat_arr, pres_arr, BHP_arr,
               pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_arr, pof_smooth0, cvar0,
               pof_hard0, r_vals0, w_vals0
    end
    
    start_time = time()
    obj, obj_base, pen_total, pen_pof, pen_cvar, sat_arr, pres_arr, BHP_arr,
    pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_arr, pof0_smooth, cvar0, pof0_hard, _, _ =
        first_forward!(inj_rate)
    
    println("\n[Threshold $(threshold) MPa] Iteration 0/$niterations")
    println("  Objective = $(obj) (base=$(obj_base), penalty=$(pen_total))")
    println("  POF: smooth=$(pof0_smooth), hard=$(pof0_hard) | CVaR=$(cvar0)")
    
    pof_iter[1] = pof0_smooth
    pof_hard_iter[1] = pof0_hard
    cvar_iter[1] = cvar0
    obj_arr_niter[1] = obj
    obj_1_arr[1, :] = obj_first
    obj_arr_arr[1, :] = obj_arr
    obj_base_arr[1] = obj_base
    pen_total_arr[1] = pen_total
    pen_pof_arr[1] = pen_pof
    pen_cvar_arr[1] = pen_cvar
    
    grad = grad_wrt_inj(inj_rate, δinj, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                        sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                        forward_step=forward_step, ds=ds, inj_start=inj_start, use_forward=use_forward)
    gnorm = norm(grad, Inf)
    if gnorm == 0.0
        return (threshold=threshold, final_inj_rate=inj_rate[1], final_obj=obj,
                final_obj_base=obj_base, final_penalty=pen_total,
                final_pof_smooth=pof0_smooth, final_pof_hard=pof0_hard, final_cvar=cvar0,
                gamma_used=risk_opts.γ, eps_used=risk_opts.ε, converged=false, niter=0)
    end
    p = -grad/gnorm
    grad_arr[1, :] = grad
    
    proj(x) = max.(x, 0)
    ls = BackTracking(order=3, iterations=10)
    step_arr = zeros(niterations)
    ex_step_size = 0.1
    
    for j=1:niterations
        function θ(α)
            objective(proj(inj_rate + α * p), time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=false, inj_start=inj_start)[1]
        end
        
        stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
        ex_step_size = stp
        step_arr[j] = stp
        inj_rate = proj(inj_rate + stp * p)
        inj_rate_arr[j+1, :] = inj_rate
        
        need_states = save_states || (save_plots && (j % plot_stride == 0 || j == niterations))
        obj, obj_base, pen_total, pen_pof, pen_cvar, sat_arr, pres_arr, BHP_arr,
        pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_arr, pofj_smooth, cvarj, pofj_hard, _, _ =
            objective(inj_rate, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=need_states, inj_start=inj_start)
        
        if j % 5 == 0 || j == niterations
            elapsed = time() - start_time
            println("\n[Threshold $(threshold) MPa] Iteration $j/$niterations")
            println("  Objective = $(obj) (base=$(obj_base), penalty=$(pen_total))")
            println("  POF: smooth=$(pofj_smooth), hard=$(pofj_hard) | CVaR=$(cvarj)")
            if j > 0
                est_remaining = (elapsed / j) * (niterations - j)
                println("  ⏱️  Elapsed: $(round(elapsed/60, digits=1)) min | Est. remaining: $(round(est_remaining/60, digits=1)) min")
            end
        end
        
        obj_arr_niter[j+1] = obj
        obj_1_arr[j+1, :] = obj_first
        obj_arr_arr[j+1, :] = obj_arr
        obj_base_arr[j+1] = obj_base
        pen_total_arr[j+1] = pen_total
        pen_pof_arr[j+1] = pen_pof
        pen_cvar_arr[j+1] = pen_cvar
        pof_iter[j+1] = pofj_smooth
        pof_hard_iter[j+1] = pofj_hard
        cvar_iter[j+1] = cvarj
        
        grad = grad_wrt_inj(inj_rate, δinj, time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                            sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                            forward_step=forward_step, ds=ds, inj_start=inj_start, use_forward=use_forward)
        gnorm = norm(grad, Inf)
        if gnorm == 0.0
            break
        end
        p = -grad/gnorm
        grad_arr[j+1, :] = grad
        
        if stp < (inj_rate + [inj_start])[1] / 2 * 0.05 / 0.95
            break
        end
        GC.gc()
    end
    
    @tagsave(joinpath(out_root, "final.jld2"),
    Dict(
        "threshold" => threshold,
        "inj_rate_arr" => inj_rate_arr, "step_arr" => step_arr, "obj_arr_niter" => obj_arr_niter,
        "obj_1_arr" => obj_1_arr, "obj_arr_arr" => obj_arr_arr, "grad_arr" => grad_arr,
        "pof_iter" => pof_iter, "pof_hard_iter" => pof_hard_iter, "cvar_iter" => cvar_iter,
        "obj_base_arr" => obj_base_arr, "pen_total_arr" => pen_total_arr,
        "pen_pof_arr" => pen_pof_arr, "pen_cvar_arr" => pen_cvar_arr,
        "risk_params" => Dict(
            "use_pof" => risk_opts.use_pof, "eps_pof" => risk_opts.use_pof ? risk_opts.ε : nothing,
            "tau_pof" => risk_opts.use_pof ? risk_opts.τ : nothing,
            "lambda_pof" => risk_opts.use_pof ? risk_opts.λ_pof : nothing,
            "pof_as_constraint" => risk_opts.pof_as_constraint,
            "use_cvar" => risk_opts.use_cvar, "gamma_cvar" => risk_opts.use_cvar ? risk_opts.γ : nothing,
            "alpha_cvar" => risk_opts.use_cvar ? risk_opts.α : nothing,
            "lambda_cvar" => risk_opts.use_cvar ? risk_opts.λ_cvar : nothing,
            "cvar_as_constraint" => risk_opts.cvar_as_constraint, "cvar_soft" => risk_opts.cvar_soft,
            "risk_mode" => String(risk_opts.mode), "weight_mode" => String(risk_opts.weight_mode)
        ),
        "meta" => (risk_opts=risk_opts, run_tag=run_tag, idx=s, step=monitoring_step, threshold=threshold)
    ); safe=true)
    
    final_iter = findlast(!isnan, pof_iter)
    final_iter = final_iter === nothing ? 1 : final_iter
    
    return (threshold=threshold, final_inj_rate=inj_rate[1], final_obj=obj_arr_niter[final_iter],
            final_obj_base=obj_base_arr[final_iter], final_penalty=pen_total_arr[final_iter],
            final_pof_smooth=pof_iter[final_iter], final_pof_hard=pof_hard_iter[final_iter],
            final_cvar=cvar_iter[final_iter], gamma_used=risk_opts.γ, eps_used=risk_opts.ε,
            converged=(gnorm > 0), niter=final_iter)
end

# ─────────────────────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────────────────────
function parse_threshold_list(raw::String)
    cleaned = strip(raw)
    isempty(cleaned) && return Float64[]
    return [parse(Float64, strip(val)) for val in split(cleaned, ",") if !isempty(strip(val))]
end

function parse_float_list(raw::AbstractString)
    cleaned = strip(raw)
    isempty(cleaned) && return Float64[]
    return [parse(Float64, strip(val)) for val in split(cleaned, ",") if !isempty(strip(val))]
end

const _GAMMA_MATCH_TOL = 1e-8

function match_float_key(keys_iter, target::Float64; atol::Float64=_GAMMA_MATCH_TOL)
    for key in keys_iter
        abs(key - target) <= atol && return key
    end
    return nothing
end

function gamma_lookup_entry(table_data::Dict, eps::Float64, threshold::Float64; strict::Bool=false)
    entries = get(table_data, "gamma_entries", nothing)
    entries === nothing && error("Gamma table missing 'gamma_entries' key")
    
    eps_key = match_float_key(keys(entries), eps)
    if eps_key === nothing
        msg = "Gamma table has no entry for eps=$(eps)"
        strict ? error(msg) : (@warn msg; return nothing)
    end
    
    per_eps = entries[eps_key]
    thresh_key = match_float_key(keys(per_eps), threshold)
    if thresh_key === nothing
        msg = "Gamma table missing threshold=$(threshold) MPa for eps=$(eps)"
        strict ? error(msg) : (@warn msg; return nothing)
    end
    
    entry = per_eps[thresh_key]
    return (gamma=entry.gamma, eps=eps_key, threshold=thresh_key, pof=entry.pof, cvar=entry.cvar)
end

function _safe_get(vec, idx, default)
    (vec === nothing || idx > length(vec)) ? default : vec[idx]
end

function merge_summary_data(existing_summary::Union{Nothing,Dict}, new_results::Vector)
    combined = Dict{Float64,NamedTuple}()
    
    if existing_summary !== nothing
        old_thresholds = get(existing_summary, "thresholds", Float64[])
        for idx in eachindex(old_thresholds)
            t = old_thresholds[idx]
            combined[t] = (
                final_inj_rate=_safe_get(get(existing_summary, "final_inj_rates", nothing), idx, NaN),
                final_obj=_safe_get(get(existing_summary, "final_objs", nothing), idx, NaN),
                final_obj_base=_safe_get(get(existing_summary, "final_obj_bases", nothing), idx, NaN),
                final_penalty=_safe_get(get(existing_summary, "final_penalties", nothing), idx, NaN),
                final_pof_smooth=_safe_get(get(existing_summary, "final_pof_smooth", nothing), idx, NaN),
                final_pof_hard=_safe_get(get(existing_summary, "final_pof_hard", nothing), idx, NaN),
                final_cvar=_safe_get(get(existing_summary, "final_cvar", nothing), idx, NaN),
                gamma_used=_safe_get(get(existing_summary, "gamma_used", nothing), idx, NaN),
                eps_used=_safe_get(get(existing_summary, "eps_used", nothing), idx, NaN),
                converged=_safe_get(get(existing_summary, "converged", nothing), idx, false),
                niter=_safe_get(get(existing_summary, "niters", nothing), idx, 0)
            )
        end
    end
    
    for r in new_results
        combined[r.threshold] = (
            final_inj_rate=r.final_inj_rate, final_obj=r.final_obj, final_obj_base=r.final_obj_base,
            final_penalty=r.final_penalty, final_pof_smooth=r.final_pof_smooth,
            final_pof_hard=r.final_pof_hard, final_cvar=r.final_cvar,
            gamma_used=r.gamma_used, eps_used=r.eps_used, converged=r.converged, niter=r.niter
        )
    end
    
    sorted_thresholds = sort(collect(keys(combined)))
    return (
        thresholds = sorted_thresholds,
        final_inj_rates = [combined[t].final_inj_rate for t in sorted_thresholds],
        final_objs = [combined[t].final_obj for t in sorted_thresholds],
        final_obj_bases = [combined[t].final_obj_base for t in sorted_thresholds],
        final_penalties = [combined[t].final_penalty for t in sorted_thresholds],
        final_pof_smooth = [combined[t].final_pof_smooth for t in sorted_thresholds],
        final_pof_hard = [combined[t].final_pof_hard for t in sorted_thresholds],
        final_cvar = [combined[t].final_cvar for t in sorted_thresholds],
        gamma_used = [combined[t].gamma_used for t in sorted_thresholds],
        eps_used = [combined[t].eps_used for t in sorted_thresholds],
        converged = [combined[t].converged for t in sorted_thresholds],
        niters = [combined[t].niter for t in sorted_thresholds]
    )
end

function with_summary_lock(f::Function, summary_path::String; retry_sleep::Float64=1.0, timeout::Float64=600.0)
    lock_dir = summary_path * ".lock"
    start_time = time()
    while true
        try
            mkdir(lock_dir)
            break
        catch e
            if isa(e, SystemError)
                if time() - start_time > timeout
                    error("Timed out waiting for lock: $(summary_path)")
                end
                sleep(retry_sleep)
            else
                rethrow(e)
            end
        end
    end
    try
        return f()
    finally
        isdir(lock_dir) && try rm(lock_dir; recursive=true, force=true) catch end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Main Function
# ─────────────────────────────────────────────────────────────────────────────
function main()
    args = parse_commandline()
    
    # Determine threshold values
    raw_threshold_list = args["threshold_list"]
    threshold_values = !isempty(strip(raw_threshold_list)) ? parse_threshold_list(raw_threshold_list) :
                       collect(range(args["threshold_min"], args["threshold_max"], length=args["threshold_num"]))
    isempty(threshold_values) && error("No valid thresholds provided")
    
    split_mode = Base.get(args, "split_threshold_jobs", false)
    split_idx = args["split_job_index"]
    split_total = max(args["split_job_total"], length(threshold_values))
    
    if split_mode
        length(threshold_values) != 1 && error("Split mode requires exactly 1 threshold")
        println("=" ^ 80)
        println("Split threshold job: $(split_idx)/$(split_total), threshold=$(threshold_values[1]) MPa")
        println("=" ^ 80)
    else
        println("=" ^ 80)
        println("Threshold Sensitivity Analysis")
        println("Testing thresholds: ", threshold_values)
        println("=" ^ 80)
    end
    
    total_threshold_count = split_mode ? split_total : length(threshold_values)
    eps_pof = args["eps_pof"]
    gamma_cvar = args["gamma_cvar"]
    alpha_tail = args["alpha"]
    use_cvar = Base.get(args, "use_cvar", false)
    use_pof = Base.get(args, "use_pof", false)
    
    # Generate gamma table if requested
    gamma_table_output = strip(args["gamma_table_generate"])
    if !isempty(gamma_table_output)
        eps_list_raw = strip(args["gamma_table_eps_list"])
        eps_values = isempty(eps_list_raw) ? [eps_pof] : parse_float_list(eps_list_raw)
        isempty(eps_values) && (eps_values = [eps_pof])
        table = generate_gamma_table(threshold_values, eps_values, args)
        output_path = gamma_table_output == "auto" ?
            datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                    "gamma_table__sample=$(args["idx_num"])__" * Dates.format(now(), "yyyymmdd_HHMMSS") * ".jld2") :
            (isabspath(gamma_table_output) ? gamma_table_output : joinpath(pwd(), gamma_table_output))
        mkpath(dirname(output_path))
        @tagsave(output_path, table; safe=true)
        println("✓ Gamma table saved: ", output_path)
        return
    end
    
    # Load gamma table if provided
    gamma_overrides = Dict{Float64,NamedTuple{(:gamma,:eps,:source),Tuple{Float64,Float64,String}}}()
    gamma_table_source = ""
    gamma_table_path = strip(args["gamma_table_path"])
    gamma_table_eps_target = isnan(args["gamma_table_eps"]) ? eps_pof : args["gamma_table_eps"]
    if !isempty(gamma_table_path)
        resolved_path = isabspath(gamma_table_path) ? gamma_table_path : joinpath(pwd(), gamma_table_path)
        isfile(resolved_path) || error("gamma_table_path=$(resolved_path) does not exist")
        gamma_table_source = resolved_path
        table_data = JLD2.load(resolved_path)
        println("Loaded gamma table: ", resolved_path, " (eps=$(gamma_table_eps_target))")
        for thresh in threshold_values
            entry = gamma_lookup_entry(table_data, gamma_table_eps_target, thresh;
                                      strict=Base.get(args, "gamma_table_strict", false))
            if entry !== nothing
                gamma_overrides[thresh] = (gamma=entry.gamma, eps=entry.eps, source=resolved_path)
                println("  threshold=$(thresh) MPa → gamma=$(entry.gamma)")
            end
        end
    end
    
    # Auto-calibrate gamma if requested
    gamma_override_active = !isempty(gamma_overrides)
    if gamma_override_active
        println("Using per-threshold gamma overrides")
    elseif Base.get(args, "calibrate_gamma", false) && use_pof && use_cvar
        println("─" ^ 80)
        println("CALIBRATION: Determining gamma_cvar for eps_pof = $(eps_pof)")
        println("─" ^ 80)
        calib_thresh = isnan(args["calibration_threshold"]) ? threshold_values[1] : args["calibration_threshold"]
        try
            calib_result = calibrate_gamma_for_eps(calib_thresh, args, eps_pof, alpha_tail;
                                                  inj_rate_guess=args["inj_guess"])
            if gamma_cvar == 0.0
                args["gamma_cvar"] = calib_result.suggested_gamma
                gamma_cvar = calib_result.suggested_gamma
                println("✓ Auto-updated gamma_cvar to $(gamma_cvar)")
            end
        catch e
            @warn "Calibration failed" exception=(e, catch_backtrace())
        end
    end
    
    # Print risk settings
    println("=" ^ 80)
    println("RISK PARAMETER SETTINGS:")
    use_pof && println("  POF: eps=$(eps_pof), tau=$(args["tau_pof"]), lambda=$(args["lambda_pof"])")
    use_cvar && println("  CVaR: gamma=$(gamma_cvar), alpha=$(alpha_tail), lambda=$(args["lambda_cvar"])")
    println("=" ^ 80)
    
    # Save risk parameters
    s = args["idx_num"]
    risk_label = (use_pof && use_cvar) ? "POF_CVaR" : (use_pof ? "POF" : (use_cvar ? "CVaR" : "NoRisk"))
    risk_params_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                               "risk_params__$(risk_label)__sample=$(s).jld2")
    mkpath(dirname(risk_params_path))
    @tagsave(risk_params_path, Dict(
        "use_pof" => use_pof, "eps_pof" => use_pof ? eps_pof : nothing,
        "tau_pof" => use_pof ? args["tau_pof"] : nothing, "lambda_pof" => use_pof ? args["lambda_pof"] : nothing,
        "pof_as_constraint" => use_pof ? Base.get(args, "pof_as_constraint", false) : false,
        "use_cvar" => use_cvar, "gamma_cvar" => use_cvar ? gamma_cvar : nothing,
        "alpha_cvar" => use_cvar ? alpha_tail : nothing, "lambda_cvar" => use_cvar ? args["lambda_cvar"] : nothing,
        "cvar_soft" => use_cvar ? Base.get(args, "cvar_soft", false) : false,
        "cvar_as_constraint" => use_cvar ? Base.get(args, "cvar_as_constraint", false) : false,
        "risk_mode" => args["risk_mode"], "weight_mode" => args["weight_mode"],
        "idx_num" => s, "timestamp" => now()
    ); safe=true)
    
    # Run optimization for each threshold
    results = []
    overall_start_time = time()
    checkpoint_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                             "progress_checkpoint__$(risk_label)__sample=$(s).jld2")
    mkpath(dirname(checkpoint_path))
    
    for (i, thresh) in enumerate(threshold_values)
        global_idx = split_mode ? split_idx : i
        println("\n" * "=" ^ 80)
        println("THRESHOLD $(global_idx)/$(total_threshold_count): $(thresh) MPa")
        println("=" ^ 80)
        overall_elapsed = time() - overall_start_time
        println("Elapsed: $(round(overall_elapsed/60, digits=1)) min")
        if i > 1
            avg_time = overall_elapsed / (i - 1)
            est_remaining = avg_time * (length(threshold_values) - i + 1)
            println("Est. remaining: $(round(est_remaining/60, digits=1)) min")
        end
        
        @tagsave(checkpoint_path, Dict(
            "completed_thresholds" => [r.threshold for r in results],
            "current_threshold" => thresh, "current_index" => global_idx,
            "total_thresholds" => total_threshold_count, "results_so_far" => results,
            "overall_elapsed" => overall_elapsed, "status" => "starting", "timestamp" => now()
        ); safe=true)
        
        override_entry = get(gamma_overrides, thresh, nothing)
        gamma_override_val = override_entry === nothing ? nothing : override_entry.gamma
        eps_override_val = override_entry === nothing ? nothing : override_entry.eps
        
        try
            result = run_optimization_for_threshold(thresh, args;
                                                   gamma_override=gamma_override_val,
                                                   eps_override=eps_override_val)
            push!(results, result)
            @tagsave(checkpoint_path, Dict(
                "completed_thresholds" => [r.threshold for r in results],
                "current_threshold" => thresh, "current_index" => global_idx,
                "total_thresholds" => total_threshold_count, "results_so_far" => results,
                "overall_elapsed" => time() - overall_start_time, "timestamp" => now()
            ); safe=true)
            println("\n✓ Completed: $(thresh) MPa | Inj=$(result.final_inj_rate) | POF=$(result.final_pof_smooth) | CVaR=$(result.final_cvar)")
        catch e
            @warn "Failed for threshold=$(thresh)" exception=(e, catch_backtrace())
            push!(results, (threshold=thresh, final_inj_rate=NaN, final_obj=NaN, final_obj_base=NaN,
                           final_penalty=NaN, final_pof_smooth=NaN, final_pof_hard=NaN, final_cvar=NaN,
                           gamma_used=NaN, eps_used=NaN, converged=false, niter=0))
        end
    end
    
    # Save summary
    merge_flag = split_mode || Base.get(args, "merge_results", false)
    summary_path = split_mode && split_idx > 0 ?
        datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
               "summary_$(risk_label)__sample=$(s)_#$(split_idx).jld2") :
        datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
               "summary_$(risk_label)__sample=$(s).jld2")
    mkpath(dirname(summary_path))
    
    summary_combined = with_summary_lock(summary_path) do
        existing_summary = (merge_flag && isfile(summary_path)) ? JLD2.load(summary_path) : nothing
        combined = merge_summary_data(existing_summary, results)
        per_thresholds = combined.thresholds
        @tagsave(summary_path, Dict(
            "thresholds" => combined.thresholds, "final_inj_rates" => combined.final_inj_rates,
            "final_objs" => combined.final_objs, "final_obj_bases" => combined.final_obj_bases,
            "final_penalties" => combined.final_penalties, "final_pof_smooth" => combined.final_pof_smooth,
            "final_pof_hard" => combined.final_pof_hard, "final_cvar" => combined.final_cvar,
            "gamma_used" => combined.gamma_used, "eps_used" => combined.eps_used,
            "converged" => combined.converged, "niters" => combined.niters, "args" => args,
            "risk_params" => Dict(
                "use_pof" => use_pof, "eps_pof" => use_pof ? eps_pof : nothing,
                "tau_pof" => use_pof ? args["tau_pof"] : nothing,
                "lambda_pof" => use_pof ? args["lambda_pof"] : nothing,
                "pof_as_constraint" => use_pof ? Base.get(args, "pof_as_constraint", false) : false,
                "use_cvar" => use_cvar, "gamma_cvar" => use_cvar ? gamma_cvar : nothing,
                "alpha_cvar" => use_cvar ? alpha_tail : nothing,
                "lambda_cvar" => use_cvar ? args["lambda_cvar"] : nothing,
                "cvar_as_constraint" => use_cvar ? Base.get(args, "cvar_as_constraint", false) : false,
                "cvar_soft" => use_cvar ? Base.get(args, "cvar_soft", false) : false,
                "risk_mode" => args["risk_mode"], "weight_mode" => args["weight_mode"],
                "gamma_lookup_source" => gamma_override_active ? gamma_table_source : "",
                "per_threshold_gamma" => Dict(zip(per_thresholds, combined.gamma_used)),
                "per_threshold_eps" => Dict(zip(per_thresholds, combined.eps_used))
            ),
            "meta" => (idx=s, timestamp=now(), split_mode=split_mode, total_thresholds=total_threshold_count)
        ); safe=true)
        combined
    end
    
    thresholds = summary_combined.thresholds
    final_inj_rates = summary_combined.final_inj_rates
    final_objs = summary_combined.final_objs
    final_obj_bases = summary_combined.final_obj_bases
    final_penalties = summary_combined.final_penalties
    final_pof_smooth = summary_combined.final_pof_smooth
    final_pof_hard = summary_combined.final_pof_hard
    final_cvar = summary_combined.final_cvar
    
    println("\n" * "=" ^ 80)
    println("Sensitivity Analysis Complete")
    println("Summary saved to: ", summary_path)
    println("=" ^ 80)
    println(@sprintf("%-12s %-15s %-15s %-12s %-12s %-12s",
                     "Threshold", "Inj Rate", "Objective", "POF (smooth)", "POF (hard)", "CVaR"))
    println("─" ^ 80)
    for i in eachindex(thresholds)
        println(@sprintf("%-12.2f %-15.6e %-15.6e %-12.6f %-12.6f %-12.6f",
                         thresholds[i], final_inj_rates[i], final_objs[i],
                         final_pof_smooth[i], final_pof_hard[i], final_cvar[i]))
    end
    println("─" ^ 80)
    
    # Create plots
    try
        plot_path = plotsdir("DT_control", "exp_name=step1", "threshold_sensitivity")
        mkpath(plot_path)
        
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_inj_rates, "o-", linewidth=2, markersize=8)
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("Optimal Injection Rate", fontsize=14)
        ax.set_title("Optimal Injection Rate vs Threshold", fontsize=16)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "inj_rate_vs_threshold__sample=$(s).png"), fig)
        close(fig)
        
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_objs, "o-", linewidth=2, markersize=8, label="Total")
        ax.plot(thresholds, final_obj_bases, "s--", linewidth=2, markersize=6, label="Base")
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("Objective Value", fontsize=14)
        ax.set_title("Objective vs Threshold", fontsize=16)
        ax.legend(fontsize=12)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "objective_vs_threshold__sample=$(s).png"), fig)
        close(fig)
        
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_pof_smooth, "o-", linewidth=2, markersize=8, label="Smooth")
        ax.plot(thresholds, final_pof_hard, "s--", linewidth=2, markersize=6, label="Hard")
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("Probability of Failure", fontsize=14)
        ax.set_title("PoF vs Threshold", fontsize=16)
        ax.legend(fontsize=12)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "pof_vs_threshold__sample=$(s).png"), fig)
        close(fig)
        
        fig, ax = subplots(figsize=(8, 6))
        ax.plot(thresholds, final_cvar, "o-", linewidth=2, markersize=8)
        ax.set_xlabel("Threshold t (MPa)", fontsize=14)
        ax.set_ylabel("CVaR", fontsize=14)
        ax.set_title("CVaR vs Threshold", fontsize=16)
        ax.grid(true, alpha=0.3)
        plt.tight_layout()
        safesave(joinpath(plot_path, "cvar_vs_threshold__sample=$(s).png"), fig)
        close(fig)
        
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
