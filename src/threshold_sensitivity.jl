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
@quickactivate "optim_injr_DT"

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
using Base: time
using Base.Threads

# ─────────────────────────────────────────────────────────────────────────────
# PyCall setup (using shared utility)
include("utils.jl")
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

        "--gamma_table_generate"
            help = "If non-empty, generate (threshold, eps) → gamma table and save to this path (then exit)"
            arg_type = String
            default = ""

        "--gamma_table_eps_list"
            help = "Comma-separated eps values to include when generating a gamma table (defaults to --eps_pof)"
            arg_type = String
            default = ""

        "--gamma_table_path"
            help = "Path to previously generated gamma lookup table (per-threshold gamma overrides)"
            arg_type = String
            default = ""

        "--gamma_table_eps"
            help = "When using gamma table, which eps entry to use (defaults to --eps_pof)"
            arg_type = Float64
            default = NaN

        "--gamma_table_strict"
            help = "Raise error if gamma table lacks a requested threshold entry"
            action = :store_true

        "--split_threshold_jobs"
            help = "Run only a single threshold per invocation (for SLURM arrays); requires split_job_index"
            action = :store_true

        "--split_job_index"
            help = "1-based index of the threshold to run when --split_threshold_jobs is enabled"
            arg_type = Int
            default = 1

        "--split_job_total"
            help = "Total number of thresholds when --split_threshold_jobs is enabled (for logging only)"
            arg_type = Int
            default = 1

        "--merge_results"
            help = "Merge this run's results into any existing summary file (use with split jobs)"
            action = :store_true

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

        # Optimization/save/plotting
        "--niterations"
            help = "Max GD iterations"
            arg_type = Int
            default = 20

        "--inj_start"
            help = "Starting injection rate (replaces global init_inj_rate)"
            arg_type = Float64
            default = 0.0001

        "--inj_guess"
            help = "Initial guess injection rate (upper bound)"
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
# Gamma Calibration Functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_cvar_for_pof_level(r_vals, w_vals, target_pof, α=0.05)

Compute CVaR value corresponding to a given POF level.

This helps establish the relationship between eps (POF threshold) and gamma (CVaR threshold).

# Arguments
- `r_vals`: Vector of relative pressure margins
- `w_vals`: Vector of space-time weights
- `target_pof`: Target POF level
- `α`: Tail level for CVaR (default: 0.05)

# Returns
- CVaR value when POF ≈ target_pof

# Strategy
Find the quantile Q such that POF(Q) = target_pof, then compute CVaR at that level.
"""
function compute_cvar_for_pof_level(r_vals::Vector{Float64}, w_vals::Vector{Float64},
                                    target_pof::Float64, α::Float64=0.05)
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

"""
    calibrate_gamma_for_eps(threshold, args, eps_target, α=0.05; inj_rate_guess=0.05)

Run a single forward simulation to determine appropriate gamma (CVaR threshold) 
for a given eps (POF threshold) at a specific pressure threshold.

This helps establish consistent (eps, gamma) pairs before doing full optimization.

# Arguments
- `threshold`: Pressure threshold (MPa)
- `args`: Configuration dictionary
- `eps_target`: Target POF threshold (ε)
- `α`: Tail level for CVaR (default: 0.05)
- `inj_rate_guess`: Initial injection rate guess (default: 0.05)

# Returns
Named tuple with:
- `pof_hard`: Hard POF value
- `pof_smooth`: Smooth POF value
- `cvar`: CVaR value
- `suggested_gamma`: Suggested gamma value (equals cvar)
"""
function calibrate_gamma_for_eps(threshold::Float64, args::Dict{String,Any}, 
                                  eps_target::Float64, α::Float64=0.05;
                                  inj_rate_guess::Float64=0.05,
                                  BroadK=nothing, state_data=nothing)
    # Setup (similar to run_optimization_for_threshold but minimal)
    s = args["idx_num"]
    n = (512, 1, 256)
    d = (6.25, 100.0, 6.25)
    h = 0.0
    ϕ = 0.25
    ds = 10
    forward_step = 2
    
    # Load files only if not provided (for thread safety, load before parallel section)
    monitoring_step = 1
    if BroadK === nothing
    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    perm_data = JLD2.load(perm_path)
    BroadK = perm_data["BroadK"]
    end
    
    if state_data === nothing
    state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2")
    state_data = JLD2.load(state_path)
    end
    
    idices = state_data["idx_t" * string(monitoring_step)]
    idx = idices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md
    
    p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ threshold * 10^6
    
    # Initial state
    inj_y0 = 191 + argmax(K[250, 191:200]) - 1
    S0 = zeros(Float64, n[1], n[end])
    # Use thread-safe random seed: combine sample index with thread ID for uniqueness
    thread_id = Base.Threads.threadid()
    Random.seed!(2025 + s - 1 + thread_id * 10000)
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
    
    # Find injection rate that makes POF ≈ eps_target using binary search
    # This ensures accurate (eps, gamma) correspondence
    function evaluate_pof(inj_rate_val)
        _, _, _, _, _, _, _, _, _, _, _, _, pof_smooth, cvar, pof_hard, r_vals, w_vals =
            objective([inj_rate_val], time_step, sim, inj_loc, p_max, BHP_max, p0, n, d, h, ϕ;
                      sat_init=sat_init, pres_init=nothing, risk=risk_opts,
                      forward_step=forward_step, ds=ds, collect_states=false,
                      inj_start=args["inj_start"])
        return pof_hard, cvar, pof_smooth
    end
    
    # Binary search to find injection rate where POF ≈ eps_target
    tol = max(0.0001, eps_target * 0.05)  # Tolerance: 5% of eps_target, but at least 0.0001
    max_iter = 30
    inj_low = 0.0001
    inj_high = 2.0  # Upper bound (adjust if needed)
    
    # First, check if initial guess is close enough
    pof_init, cvar_init, pof_smooth_init = evaluate_pof(inj_rate_guess)
    if abs(pof_init - eps_target) <= tol
        println("   Initial guess gives POF ≈ eps_target: POF=$(pof_init), CVaR=$(cvar_init)")
        return (pof_hard=pof_init, pof_smooth=pof_smooth_init, cvar=cvar_init, 
                suggested_gamma=cvar_init)
    end
    
    # Find initial bounds: need to find inj_low where POF < eps_target and inj_high where POF > eps_target
    # Start by checking if we need to expand the search range
    if pof_init < eps_target
        # POF too low, need to find upper bound
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
            # Even at high injection rate, POF is still below target
            # This means the threshold is too high - return the best we can get
            println("   ⚠️  Cannot reach POF=$(eps_target) even at high injection rate: POF=$(pof_init)")
            println("      This may indicate threshold=$(threshold) MPa is too high for this eps.")
            return (pof_hard=pof_init, pof_smooth=pof_smooth_init, cvar=cvar_init, 
                    suggested_gamma=cvar_init)
        end
        inj_low = inj_rate_guess
    else
        # POF too high, need to find lower bound
        test_inj = inj_rate_guess
        while test_inj > inj_low && pof_init > eps_target
            test_inj /= 2.0
            if test_inj < inj_low
                test_inj = inj_low
            end
            pof_init, cvar_init, pof_smooth_init = evaluate_pof(test_inj)
            if pof_init <= eps_target
                inj_low = test_inj
                break
            end
        end
        if pof_init > eps_target && test_inj <= inj_low
            # Even at very low injection rate, POF is still above target
            # This means the threshold is too low - return the best we can get
            println("   ⚠️  Cannot reach POF=$(eps_target) even at low injection rate: POF=$(pof_init)")
            println("      This may indicate threshold=$(threshold) MPa is too low for this eps.")
            return (pof_hard=pof_init, pof_smooth=pof_smooth_init, cvar=cvar_init, 
                    suggested_gamma=cvar_init)
        end
        inj_high = inj_rate_guess
    end
    
    # Binary search
    println("   Finding injection rate where POF ≈ $(eps_target) (tolerance=$(tol))...")
    println("   Search range: [$(inj_low), $(inj_high)]")
    best_inj = inj_rate_guess
    best_pof = pof_init
    best_cvar = cvar_init
    best_error = abs(pof_init - eps_target)
    
    for iter in 1:max_iter
        inj_mid = (inj_low + inj_high) / 2
        pof_mid, cvar_mid, pof_smooth_mid = evaluate_pof(inj_mid)
        error_mid = abs(pof_mid - eps_target)
        
        # Track best solution
        if error_mid < best_error
            best_inj = inj_mid
            best_pof = pof_mid
            best_cvar = cvar_mid
            best_error = error_mid
        end
        
        if error_mid <= tol
            println("   ✓ Found: inj_rate=$(inj_mid), POF=$(pof_mid), CVaR=$(cvar_mid)")
            return (pof_hard=pof_mid, pof_smooth=pof_smooth_mid, cvar=cvar_mid, 
                    suggested_gamma=cvar_mid)
        elseif pof_mid > eps_target
            # POF too high, need lower injection rate
            inj_high = inj_mid
        else
            # POF too low, need higher injection rate
            inj_low = inj_mid
        end
        
        if (inj_high - inj_low) < 1e-6
            # Search converged but didn't reach target
            println("   ⚠️  Search converged: inj_rate=$(best_inj), POF=$(best_pof) (target=$(eps_target), error=$(best_error))")
            return (pof_hard=best_pof, pof_smooth=best_pof, cvar=best_cvar, 
                    suggested_gamma=best_cvar)
        end
    end
    
    # If binary search didn't converge, use the best estimate
    println("   ⚠️  Max iterations reached: using best estimate: inj_rate=$(best_inj), POF=$(best_pof), CVaR=$(best_cvar)")
    return (pof_hard=best_pof, pof_smooth=best_pof, cvar=best_cvar, 
            suggested_gamma=best_cvar)
end

"""
    generate_gamma_table(threshold_values, eps_values, args)

Generate a lookup table mapping (threshold, eps) pairs to gamma values.

# Arguments
- `threshold_values`: Vector of pressure thresholds (MPa)
- `eps_values`: Vector of POF threshold values (ε)
- `args`: Configuration dictionary

# Returns
Dictionary containing:
- `gamma_entries`: Nested dictionary mapping eps → threshold → (gamma, pof, cvar)
- `eps_values`: List of eps values
- `thresholds`: List of threshold values
- `meta`: Metadata (idx, alpha, timestamp, inj_guess)
"""
function generate_gamma_table(threshold_values::Vector{Float64}, eps_values::Vector{Float64},
                              args::Dict{String,Any})
    alpha_tail = args["alpha"]
    
    println("=" ^ 80)
    println("Generating gamma lookup table (PARALLEL)")
    println("=" ^ 80)
    println("Thresholds: ", threshold_values)
    println("Eps values: ", eps_values)
    println("Using $(nthreads()) threads for parallel generation")
    println()
    
    # Create all (eps, threshold) pairs for parallel processing
    tasks = Vector{Tuple{Float64, Float64}}()
    for eps in eps_values
        for thresh in threshold_values
            push!(tasks, (eps, thresh))
        end
    end
    
    # Thread-safe storage: use locks for dictionary updates
    entries_lock = ReentrantLock()
    entries = Dict{Float64,Dict{Float64,NamedTuple{(:gamma,:pof,:cvar),NTuple{3,Float64}}}}()
    
    # Initialize nested dictionaries
    for eps in eps_values
        entries[eps] = Dict{Float64,NamedTuple{(:gamma,:pof,:cvar),NTuple{3,Float64}}}()
    end
    
    # Print lock for thread-safe output
    print_lock = ReentrantLock()
    
    # Jutul execution lock - Jutul's internal parallelism conflicts with @threads
    # We need to serialize Jutul calls to avoid UndefRefError
    jutul_lock = ReentrantLock()
    
    # Pre-load files in main thread to avoid concurrent JLD2 access issues
    println("Pre-loading data files (thread-safe)...")
    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    perm_data = JLD2.load(perm_path)
    BroadK_shared = perm_data["BroadK"]
    
    monitoring_step = 1
    state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * "_rtm1_broad_NL_SNR28.jld2")
    state_data_shared = JLD2.load(state_path)
    println("Data files loaded successfully.")
    println()
    
    # Parallel processing
    @threads for (eps, thresh) in tasks
        thread_id = threadid()
        lock(print_lock) do
            println("[Thread $(thread_id)] Processing: eps=$(eps), threshold=$(thresh) MPa ...")
        end
        
        # Serialize Jutul calls to avoid internal parallelism conflicts
        result = lock(jutul_lock) do
            calibrate_gamma_for_eps(thresh, args, eps, alpha_tail;
                                   inj_rate_guess=args["inj_guess"],
                                   BroadK=BroadK_shared,
                                   state_data=state_data_shared)
        end
        
        lock(entries_lock) do
            entries[eps][thresh] = (gamma=result.suggested_gamma,
                                   pof=result.pof_hard,
                                   cvar=result.cvar)
        end
        
        lock(print_lock) do
            println("[Thread $(thread_id)] ✓ Completed: eps=$(eps), threshold=$(thresh) MPa, gamma ≈ $(result.suggested_gamma)")
        end
    end
    
    println()
    println("=" ^ 80)
    println("Gamma table generation completed")
    println("=" ^ 80)

    return Dict(
        "gamma_entries" => entries,
        "eps_values" => eps_values,
        "thresholds" => threshold_values,
        "meta" => (
            idx = args["idx_num"],
            alpha = alpha_tail,
            timestamp = now(),
            inj_guess = args["inj_guess"],
            calibration_method = "binary_search_parallel",  # Mark that this uses improved parallel method
            version = "2.1",  # Version marker for parallel calibration
            nthreads = nthreads()
        )
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Optimization Functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_optimization_for_threshold(threshold, args; gamma_override=nothing, eps_override=nothing)

Run optimization for a single pressure threshold value.

# Arguments
- `threshold`: Pressure threshold (MPa)
- `args`: Configuration dictionary
- `gamma_override`: Optional gamma value to override default (for per-threshold calibration)
- `eps_override`: Optional eps value to override default (for per-threshold calibration)

# Returns
Named tuple with optimization results:
- `threshold`: Pressure threshold used
- `final_inj_rate`: Final optimal injection rate
- `final_obj`: Final objective value
- `final_obj_base`: Final base objective (without penalties)
- `final_penalty`: Final penalty value
- `final_pof_smooth`: Final smooth POF
- `final_pof_hard`: Final hard POF
- `final_cvar`: Final CVaR
- `gamma_used`: Gamma value used
- `eps_used`: Eps value used
- `converged`: Whether optimization converged
- `niter`: Number of iterations completed
"""
function run_optimization_for_threshold(threshold::Float64, args::Dict{String,Any};
                                        gamma_override::Union{Nothing,Float64}=nothing,
                                        eps_override::Union{Nothing,Float64}=nothing)
    s = args["idx_num"]
    α_tail = args["alpha"]

    # Domain and data setup
    n = (512, 1, 256)
    d = (6.25, 100.0, 6.25)
    h = 0.0
    ϕ = 0.25
    ds = 10
    forward_step = 2

    # Load permeability data
    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    perm_data = JLD2.load(perm_path)
    BroadK = perm_data["BroadK"]

    # Load state data
    monitoring_step = 1
    state_path = datadir("state/Wise128_state_t" * string(monitoring_step) * 
                         "_rtm1_broad_NL_SNR28.jld2")
    state_data = JLD2.load(state_path)

    # Risk mode configuration
    risk_mode = args["risk_mode"] == "window" ? :window : :relative

    # Select permeability field
    idices = state_data["idx_t" * string(monitoring_step)]
    idx = idices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md

    # Pressure bounds: p_max = p0 + threshold * 10^6 (Pa)
    p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10
    p_max = p0' .+ threshold * 10^6

    # Initial state setup
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

    # Risk parameter configuration (with optional overrides)
    eps_value = isnothing(eps_override) ? args["eps_pof"] : eps_override
    gamma_value = isnothing(gamma_override) ? args["gamma_cvar"] : gamma_override
    risk_opts = (
        use_pof = Base.get(args, "use_pof", false),
        λ_pof   = args["lambda_pof"],
        ε       = eps_value,
        τ       = args["tau_pof"],

        use_cvar = Base.get(args, "use_cvar", false),
        λ_cvar   = args["lambda_cvar"],
        γ        = gamma_value,
        α        = α_tail,

        mode     = risk_mode,
        weight_mode = (args["weight_mode"] == "uniform" ? :uniform : :voltime),
        cvar_soft = Base.get(args, "cvar_soft", false),

        kappa_pof  = args["kappa_pof"],
        kappa_cvar = args["kappa_cvar"],

        pof_as_constraint  = Base.get(args, "pof_as_constraint", false),
        cvar_as_constraint = Base.get(args, "cvar_as_constraint", false)
    )

    # Generate output paths and tags
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

    # Time stepping and injection parameters
    time_step = 80 / ds * ones(6 * ds * forward_step)
    inj_rate  = [args["inj_guess"]]
    δinj      = 1e-8 * ones(size(inj_rate, 1))
    inj_start = args["inj_start"]

    # Injection well location
    inj_y = 191 + argmax(K[250, 191:200]) - 1
    inj_loc_grid = (250, 1, inj_y)
    inj_loc = (inj_loc_grid[1]*d[1], inj_loc_grid[2]*d[2], inj_loc_grid[3]*d[3])

    # BHP bound (for logging/plotting only)
    BHP_max = p_max[inj_y, 250]

    # Pre-build simulation object
    sim = build_sim(n, d, ϕ, K; h=h, ds=ds, dt_firstblock=80/ds)

    # Optimization and output settings
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

    # Initial forward pass with backtracking if hard constraints violated
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

    # Start timing for this threshold
    start_time = time()
    
    obj, obj_base, pen_total, pen_pof, pen_cvar,
    sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr,
    obj_first, obj_arr, pof0_smooth, cvar0, pof0_hard, r_vals0, w_vals0 =
        first_forward!(inj_rate)

    println("\n[Threshold $(threshold) MPa] Iteration 0/$niterations")
    println("  Objective = $(obj) (base=$(obj_base), penalty=$(pen_total))")
    println("  POF: smooth=$(pof0_smooth), hard=$(pof0_hard) | CVaR=$(cvar0)")
    println("  Starting optimization...")

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

    # Initial gradient (must compute)
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

    # Optimization setup
    proj(x) = max.(x, 0)  # Projection to non-negative injection rates
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
            elapsed = time() - start_time
            println("\n[Threshold $(threshold) MPa] Iteration $j/$niterations")
            println("  Objective = $(obj) (base=$(obj_base), penalty=$(pen_total))")
            println("  POF: smooth=$(pofj_smooth), hard=$(pofj_hard) | CVaR=$(cvarj)")
            if j > 0
                est_remaining = (elapsed / j) * (niterations - j)
                println("  ⏱️  Elapsed: $(round(elapsed/60, digits=1)) min | Est. remaining: $(round(est_remaining/60, digits=1)) min")
            else
                println("  ⏱️  Elapsed: $(round(elapsed, digits=1))s")
            end
        elseif j == 1
            # Always print first iteration for immediate feedback
            elapsed = time() - start_time
            println("[Threshold $(threshold) MPa] Iteration 1/$niterations | Elapsed: $(round(elapsed, digits=1))s")
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

        # Gradient (compute every iteration)
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
        # Save risk parameters explicitly for reproducibility
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
            gamma_used=risk_opts.γ,
            eps_used=risk_opts.ε,
            converged=(gnorm > 0),
            niter=final_iter)
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary and Merge Functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    _safe_get(vec, idx, default)

Safely get element from vector with default fallback.

# Arguments
- `vec`: Vector (may be nothing)
- `idx`: Index
- `default`: Default value if index out of bounds or vec is nothing

# Returns
Element at index or default value.
"""
function _safe_get(vec, idx, default)
    if vec === nothing || idx > length(vec)
        return default
    end
    return vec[idx]
end

"""
    merge_summary_data(existing_summary, new_results)

Merge new optimization results with existing summary data.

# Arguments
- `existing_summary`: Existing summary dictionary (or nothing)
- `new_results`: Vector of new result named tuples

# Returns
Named tuple with merged data arrays (thresholds, final_inj_rates, etc.)
"""
function merge_summary_data(existing_summary::Union{Nothing,Dict}, new_results::Vector)
    combined = Dict{Float64,NamedTuple}()

    if existing_summary !== nothing
        old_thresholds = get(existing_summary, "thresholds", Float64[])
        old_inj = get(existing_summary, "final_inj_rates", nothing)
        old_obj = get(existing_summary, "final_objs", nothing)
        old_obj_base = get(existing_summary, "final_obj_bases", nothing)
        old_penalty = get(existing_summary, "final_penalties", nothing)
        old_pof_smooth = get(existing_summary, "final_pof_smooth", nothing)
        old_pof_hard = get(existing_summary, "final_pof_hard", nothing)
        old_cvar = get(existing_summary, "final_cvar", nothing)
        old_gamma_used = get(existing_summary, "gamma_used", nothing)
        old_eps_used = get(existing_summary, "eps_used", nothing)
        old_converged = get(existing_summary, "converged", nothing)
        old_niters = get(existing_summary, "niters", nothing)

        for idx in eachindex(old_thresholds)
            t = old_thresholds[idx]
            combined[t] = (
                final_inj_rate=_safe_get(old_inj, idx, NaN),
                final_obj=_safe_get(old_obj, idx, NaN),
                final_obj_base=_safe_get(old_obj_base, idx, NaN),
                final_penalty=_safe_get(old_penalty, idx, NaN),
                final_pof_smooth=_safe_get(old_pof_smooth, idx, NaN),
                final_pof_hard=_safe_get(old_pof_hard, idx, NaN),
                final_cvar=_safe_get(old_cvar, idx, NaN),
                gamma_used=_safe_get(old_gamma_used, idx, NaN),
                eps_used=_safe_get(old_eps_used, idx, NaN),
                converged=_safe_get(old_converged, idx, false),
                niter=_safe_get(old_niters, idx, 0)
            )
        end
    end

    for r in new_results
        combined[r.threshold] = (
            final_inj_rate=r.final_inj_rate,
            final_obj=r.final_obj,
            final_obj_base=r.final_obj_base,
            final_penalty=r.final_penalty,
            final_pof_smooth=r.final_pof_smooth,
            final_pof_hard=r.final_pof_hard,
            final_cvar=r.final_cvar,
            gamma_used=r.gamma_used,
            eps_used=r.eps_used,
            converged=r.converged,
            niter=r.niter
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

# ─────────────────────────────────────────────────────────────────────────────
# Parsing and Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

"""
    parse_threshold_list(raw)

Parse comma-separated threshold values from string.

# Arguments
- `raw`: Comma-separated string of threshold values

# Returns
Vector of Float64 threshold values.
"""
function parse_threshold_list(raw::String)
    cleaned = strip(raw)
    if isempty(cleaned)
        return Float64[]
    end
    parts = split(cleaned, ",")
    return [parse(Float64, strip(val)) for val in parts if !isempty(strip(val))]
end

"""
    parse_float_list(raw)

Parse comma-separated float values from string.

# Arguments
- `raw`: Comma-separated string of float values

# Returns
Vector of Float64 values.
"""
function parse_float_list(raw::AbstractString)
    cleaned = strip(raw)
    if isempty(cleaned)
        return Float64[]
    end
    parts = split(cleaned, ",")
    return [parse(Float64, strip(val)) for val in parts if !isempty(strip(val))]
end

const _GAMMA_MATCH_TOL = 1e-8

"""
    match_float_key(keys_iter, target; atol=_GAMMA_MATCH_TOL)

Find matching float key in iterator using approximate equality.

# Arguments
- `keys_iter`: Iterator of float keys
- `target`: Target float value
- `atol`: Absolute tolerance for matching (default: 1e-8)

# Returns
Matching key or nothing if no match found.
"""
function match_float_key(keys_iter, target::Float64; atol::Float64=_GAMMA_MATCH_TOL)
    for key in keys_iter
        if abs(key - target) <= atol
            return key
        end
    end
    return nothing
end

"""
    gamma_lookup_entry(table_data, eps, threshold; strict=false)

Look up gamma value from gamma table for given (eps, threshold) pair.

# Arguments
- `table_data`: Gamma table dictionary
- `eps`: POF threshold (ε)
- `threshold`: Pressure threshold (MPa)
- `strict`: If true, raise error on missing entry; if false, warn and return nothing

# Returns
Named tuple with (gamma, eps, threshold, pof, cvar) or nothing if not found.
"""
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

"""
    with_summary_lock(f, summary_path; retry_sleep=1.0, timeout=600.0)

Execute function with file lock to prevent race conditions in parallel jobs.

# Arguments
- `f`: Function to execute
- `summary_path`: Path to summary file (lock file will be summary_path.lock)
- `retry_sleep`: Sleep time between retries (seconds, default: 1.0)
- `timeout`: Maximum time to wait for lock (seconds, default: 600.0)

# Returns
Return value of function `f`.
"""
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
                    error("Timed out while waiting for lock on summary file: $(summary_path)")
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
        if isdir(lock_dir)
            try
                rm(lock_dir; recursive=true, force=true)
            catch
                # Ignore cleanup failures
            end
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Main Function
# ─────────────────────────────────────────────────────────────────────────────

"""
    main()

Main entry point for threshold sensitivity analysis.

Orchestrates:
1. Command-line argument parsing
2. Gamma table generation (if requested)
3. Gamma table loading (if provided)
4. Risk parameter calibration
5. Optimization runs for each threshold
6. Result merging and summary generation
7. Plotting
"""
function main()
    args = parse_commandline()
    
    # Determine threshold values
    raw_threshold_list = args["threshold_list"]
    if !isempty(strip(raw_threshold_list))
        threshold_values = parse_threshold_list(raw_threshold_list)
    else
        # Generate range
        threshold_min = args["threshold_min"]
        threshold_max = args["threshold_max"]
        threshold_num = args["threshold_num"]
        threshold_values = collect(range(threshold_min, threshold_max, length=threshold_num))
    end
    if isempty(threshold_values)
        error("No valid thresholds provided. Check --threshold_list or min/max/num inputs.")
    end

    split_mode = Base.get(args, "split_threshold_jobs", false)
    split_idx = args["split_job_index"]
    split_total = max(args["split_job_total"], length(threshold_values))
    if split_mode
        # In split mode, shell script already selected a single threshold
        # So threshold_values should have exactly 1 element
        if length(threshold_values) != 1
            error("In split mode, threshold_list should contain exactly 1 value, got $(length(threshold_values))")
        end
        selected = threshold_values[1]
        println("=" ^ 80)
        println("Split threshold job mode enabled")
        println("  Running threshold index $(split_idx)/$(split_total)")
        println("  Threshold value for this run: $(selected) MPa")
        println("=" ^ 80)
        println()
    else
        println("=" ^ 80)
        println("Threshold Sensitivity Analysis")
        println("=" ^ 80)
        println("Testing thresholds: ", threshold_values)
        println("Number of thresholds: ", length(threshold_values))
        println()
    end

    total_threshold_count = split_mode ? split_total : length(threshold_values)

    eps_pof = args["eps_pof"]
    gamma_cvar = args["gamma_cvar"]
    alpha_tail = args["alpha"]
    use_cvar = Base.get(args, "use_cvar", false)
    use_pof = Base.get(args, "use_pof", false)

    gamma_table_output = strip(args["gamma_table_generate"])
    if !isempty(gamma_table_output)
        eps_list_raw = strip(args["gamma_table_eps_list"])
        eps_values = isempty(eps_list_raw) ? [eps_pof] : parse_float_list(eps_list_raw)
        if isempty(eps_values)
            eps_values = [eps_pof]
        end
        table = generate_gamma_table(threshold_values, eps_values, args)
        output_path = gamma_table_output == "auto" ?
            datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                    "gamma_table__sample=$(args["idx_num"])__" *
                    Dates.format(now(), "yyyymmdd_HHMMSS") * ".jld2") :
            (isabspath(gamma_table_output) ?
                gamma_table_output :
                joinpath(pwd(), gamma_table_output))
        mkpath(dirname(output_path))
        @tagsave(output_path, table; safe=true)
        println("✓ Gamma lookup table saved to: ", output_path)
        println("   Entries: thresholds=$(threshold_values), eps=$(eps_values)")
        println("   Re-run this script with --gamma_table_path=$(output_path) to reuse the mapping.")
        return
    end

    # Load gamma table (if provided)
    gamma_overrides = Dict{Float64,NamedTuple{(:gamma,:eps,:source),Tuple{Float64,Float64,String}}}()
    gamma_table_source = ""
    gamma_table_path = strip(args["gamma_table_path"])
    gamma_table_eps_target = isnan(args["gamma_table_eps"]) ? eps_pof : args["gamma_table_eps"]
    if !isempty(gamma_table_path)
        resolved_path = isabspath(gamma_table_path) ? gamma_table_path : joinpath(pwd(), gamma_table_path)
        if !isfile(resolved_path)
            error("gamma_table_path=$(resolved_path) does not exist")
        end
        gamma_table_source = resolved_path
        table_data = JLD2.load(resolved_path)
        println("=" ^ 80)
        println("Loaded gamma lookup table: ", resolved_path)
        println("Using eps entry = $(gamma_table_eps_target)")
        println("=" ^ 80)
        for thresh in threshold_values
            entry = gamma_lookup_entry(table_data, gamma_table_eps_target, thresh;
                                       strict=Base.get(args, "gamma_table_strict", false))
            if entry !== nothing
                gamma_overrides[thresh] = (gamma=entry.gamma, eps=entry.eps, source=resolved_path)
                println("  ✓ threshold=$(thresh) MPa → gamma=$(entry.gamma)")
            else
                println("  ⚠️ Missing gamma entry for threshold=$(thresh) MPa")
            end
        end
        println()
    end
    
    # CALIBRATION: Auto-calibrate gamma for eps if requested
    gamma_override_active = !isempty(gamma_overrides)
    if gamma_override_active
        println("Per-threshold gamma overrides detected; skipping global auto-calibration.")
        println("  Thresholds with overrides: ", collect(keys(gamma_overrides)))
        println("  Remaining thresholds (if any) will use gamma = $(gamma_cvar).")
        println()
    elseif Base.get(args, "calibrate_gamma", false) && use_pof && use_cvar
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
    elseif use_pof && use_cvar && gamma_cvar == 0.0 && !gamma_override_active
        println("⚠️  WARNING: POF and CVaR both enabled, but gamma_cvar = 0.0")
        println("   Consider using --calibrate_gamma to auto-determine gamma for eps_pof = $(eps_pof)")
        println("   Or set --gamma_cvar manually based on your risk tolerance.")
        println()
    elseif use_pof && eps_pof > 0 && use_cvar && gamma_cvar > 0.0
        println("ℹ️  Using (eps, gamma) = ($(eps_pof), $(gamma_cvar))")
        println("   Make sure these values are consistent for your risk tolerance.")
        println()
    end
    
    # Print and save risk parameter settings
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
        if gamma_override_active
            println("     gamma (γ) = per-threshold lookup (table source: $(gamma_table_source))")
        else
            println("     gamma (γ) = $(gamma_cvar)  (allowable CVaR level)")
        end
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
        if gamma_override_active
            println("     ✓ Using gamma lookup table entries (source=$(gamma_table_source))")
        end
        # Warning if gamma seems misaligned with eps
        if use_pof && gamma_cvar == 0.0 && eps_pof > 0 && !gamma_override_active
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
        println("ℹ️  ALIGNMENT CHECK (informational, not an error):")
        println("   Current (eps, gamma) = ($(eps_pof), $(gamma_cvar))")
        if gamma_cvar == 0.0 && eps_pof > 0 && !gamma_override_active
            println("   ⚠️  WARNING: gamma = 0.0 is likely too strict for eps = $(eps_pof)")
            println("   → These values may NOT be aligned!")
            println("   → Recommendation: Use --calibrate_gamma or set gamma manually")
            println("   → Optimization will proceed, but may have issues")
        else
            println("   ✓ Values are set (eps=$(eps_pof), gamma=$(gamma_cvar))")
            println("   → Alignment should be verified by checking if POF≈eps implies CVaR≈gamma")
            println("   → Optimization will proceed normally")
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
    
    # Save risk parameters to a separate file for easy reference (use risk_label)
    s = args["idx_num"]
    risk_label_params = if use_pof && use_cvar
        "POF_CVaR"
    elseif use_pof
        "POF"
    elseif use_cvar
        "CVaR"
    else
        "NoRisk"
    end
    risk_params_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                               "risk_params__$(risk_label_params)__sample=$(s).jld2")
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
    overall_start_time = time()
    
    # Progress checkpoint file (also use risk_label to avoid conflicts)
    s = args["idx_num"]
    risk_label_checkpoint = if use_pof && use_cvar
        "POF_CVaR"
    elseif use_pof
        "POF"
    elseif use_cvar
        "CVaR"
    else
        "NoRisk"
    end
    checkpoint_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                              "progress_checkpoint__$(risk_label_checkpoint)__sample=$(s).jld2")
    mkpath(dirname(checkpoint_path))
    
    for (i, thresh) in enumerate(threshold_values)
        global_idx = split_mode ? split_idx : i
        println("\n" * "=" ^ 80)
        println("THRESHOLD $(global_idx)/$(total_threshold_count): $(thresh) MPa")
        println("=" ^ 80)
        overall_elapsed = time() - overall_start_time
        println("Overall elapsed time: $(round(overall_elapsed/60, digits=1)) minutes")
        if i > 1
            avg_time_per_thresh = overall_elapsed / (i - 1)
            remaining_thresh = length(threshold_values) - i + 1
            est_total_remaining = avg_time_per_thresh * remaining_thresh
            println("Estimated remaining time: $(round(est_total_remaining/60, digits=1)) minutes")
        end
        println("─" ^ 80)
        
        # Save checkpoint BEFORE starting (so we know which threshold is running)
        @tagsave(checkpoint_path,
        Dict(
            "completed_thresholds" => [r.threshold for r in results],
            "current_threshold" => thresh,
            "current_index" => global_idx,
            "total_thresholds" => total_threshold_count,
            "results_so_far" => results,
            "overall_elapsed" => time() - overall_start_time,
            "status" => "starting",
            "timestamp" => now()
        );
        safe=true)
        
        override_entry = get(gamma_overrides, thresh, nothing)
        gamma_override_val = override_entry === nothing ? nothing : override_entry.gamma
        eps_override_val = override_entry === nothing ? nothing : override_entry.eps

        try
            result = run_optimization_for_threshold(thresh, args;
                                                    gamma_override=gamma_override_val,
                                                    eps_override=eps_override_val)
            push!(results, result)
            
            # Save progress checkpoint
            @tagsave(checkpoint_path,
            Dict(
                "completed_thresholds" => [r.threshold for r in results],
                "current_threshold" => thresh,
                "current_index" => global_idx,
                "total_thresholds" => total_threshold_count,
                "results_so_far" => results,
                "overall_elapsed" => time() - overall_start_time,
                "timestamp" => now()
            );
            safe=true)
            
            println("\n✓ Completed threshold $(i)/$(length(threshold_values)): $(thresh) MPa")
            println("  Final injection rate: $(result.final_inj_rate)")
            println("  Final objective: $(result.final_obj)")
            println("  Final POF (smooth): $(result.final_pof_smooth), POF (hard): $(result.final_pof_hard)")
            println("  Final CVaR: $(result.final_cvar)")
            println("  Converged: $(result.converged), Iterations: $(result.niter)")
        catch e
            println("❌ ERROR: Failed for threshold=$(thresh)")
            println("   Exception: ", typeof(e))
            println("   Message: ", e)
            if isa(e, ErrorException)
                println("   Full error: ", e.msg)
            end
            println("   Stack trace:")
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
                println()
            end
            @warn "Failed for threshold=$(thresh)" exception=(e, catch_backtrace())
            push!(results, (threshold=thresh, final_inj_rate=NaN, final_obj=NaN,
                           final_obj_base=NaN, final_penalty=NaN,
                           final_pof_smooth=NaN, final_pof_hard=NaN, final_cvar=NaN,
                           gamma_used=NaN, eps_used=NaN,
                           converged=false, niter=0))
            println("   → Continuing with next threshold...")
        end
    end

    merge_flag = split_mode || Base.get(args, "merge_results", false)

    # Save summary results (with optional merging + file lock for split jobs)
    s = args["idx_num"]
    
    # Simple risk label for file naming: avoids POF-only and CVaR-only runs overwriting each other
    risk_label = if use_pof && use_cvar
        "POF_CVaR"
    elseif use_pof
        "POF"
    elseif use_cvar
        "CVaR"
    else
        "NoRisk"
    end
    
    # In split mode, include job index in filename to avoid conflicts
    if split_mode && split_idx > 0
        summary_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                              "summary_$(risk_label)__sample=$(s)_#$(split_idx).jld2")
    else
        summary_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                              "summary_$(risk_label)__sample=$(s).jld2")
    end
    mkpath(dirname(summary_path))

    summary_combined = with_summary_lock(summary_path) do
        existing_summary = (merge_flag && isfile(summary_path)) ? JLD2.load(summary_path) : nothing
        combined = merge_summary_data(existing_summary, results)
        per_thresholds = combined.thresholds
        summary_payload = Dict(
            "thresholds" => combined.thresholds,
            "final_inj_rates" => combined.final_inj_rates,
            "final_objs" => combined.final_objs,
            "final_obj_bases" => combined.final_obj_bases,
            "final_penalties" => combined.final_penalties,
            "final_pof_smooth" => combined.final_pof_smooth,
            "final_pof_hard" => combined.final_pof_hard,
            "final_cvar" => combined.final_cvar,
            "gamma_used" => combined.gamma_used,
            "eps_used" => combined.eps_used,
            "converged" => combined.converged,
            "niters" => combined.niters,
            "args" => args,
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
                "weight_mode" => args["weight_mode"],
                "gamma_lookup_source" => gamma_override_active ? gamma_table_source : "",
                "per_threshold_gamma" => Dict(zip(per_thresholds, combined.gamma_used)),
                "per_threshold_eps" => Dict(zip(per_thresholds, combined.eps_used))
            ),
            "meta" => (idx=s, timestamp=now(), split_mode=split_mode, total_thresholds=total_threshold_count)
        )
        @tagsave(summary_path, summary_payload; safe=true)
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
    converged = summary_combined.converged
    niters = summary_combined.niters
    gamma_used = summary_combined.gamma_used
    eps_used = summary_combined.eps_used

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
    println(@sprintf("%-12s %-15s %-15s %-12s %-12s %-12s %-10s %-10s",
                     "Threshold", "Inj Rate", "Objective", "POF (smooth)", "POF (hard)", "CVaR", "eps", "gamma"))
    println("─" ^ 80)
    for i in eachindex(thresholds)
        println(@sprintf("%-12.2f %-15.6e %-15.6e %-12.6f %-12.6f %-12.6f %-10.4f %-10.4f",
                         thresholds[i], final_inj_rates[i], final_objs[i],
                         final_pof_smooth[i], final_pof_hard[i], final_cvar[i],
                         eps_used[i], gamma_used[i]))
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

