"""
Previous-state and permeability-loading helpers for monitoring-step optimization.
This file owns how we map monitoring-step metadata into reservoir initial conditions.
"""
function align_state_grid(field::AbstractMatrix, target_size::Tuple{Int,Int})
    if size(field) == target_size
        return Float64.(field)
    elseif size(field) == reverse(target_size)
        return Float64.(permutedims(field, (2, 1)))
    end
    error("State field has incompatible size $(size(field)); expected $(target_size) or $(reverse(target_size)).")
end

"""
Extract one 2D sample field from a 3D array while tolerating different sample-axis layouts.
"""
function slice_sample_3d(samples::AbstractArray{<:Real,3}, sample_idx::Int, target_size::Tuple{Int,Int})
    sample_axis = findfirst(==(128), size(samples))
    sample_axis === nothing && error("Could not locate sample axis in array with size $(size(samples)).")
    field = if sample_axis == 1
        samples[sample_idx, :, :]
    elseif sample_axis == 2
        samples[:, sample_idx, :]
    else
        samples[:, :, sample_idx]
    end
    return align_state_grid(field, target_size)
end

"""
Collapse a 3D sample cube into its pointwise median field.
"""
function pointwise_median_3d(samples::AbstractArray{<:Real,3}, target_size::Tuple{Int,Int})
    sample_axis = findfirst(==(128), size(samples))
    sample_axis === nothing && error("Could not locate sample axis in array with size $(size(samples)).")
    sample_axis == 1 && return align_state_grid(dropdims(mapslices(median, samples; dims=(1,)); dims=1), target_size)
    sample_axis == 2 && return align_state_grid(dropdims(mapslices(median, samples; dims=(2,)); dims=2), target_size)
    return align_state_grid(dropdims(mapslices(median, samples; dims=(3,)); dims=3), target_size)
end

"""
Choose the injection-rate starting point for the current optimization run.

For monitoring step >= 2, `inj_start` is case-level and shared across all
samples within the same risk case. The value comes from the previous
monitoring step's selected optimal injection-rate array endpoint, as documented
in `docs/injection_rate_arrays.md`.
"""
function default_inj_start(case_key::String, prior_mode::String, monitoring_step::Int, sample_idx::Int, risk_opts, cli_inj_start::Float64)
    if monitoring_step > 1 && isapprox(cli_inj_start, DEFAULT_INJ_START; atol=1e-12)
        endpoint = documented_case_inj_start(case_key, monitoring_step)
        println("Using case-level inj_start from documented previous-step endpoint for case_key=$(case_key)")
        println("Recovered previous-step endpoint = ", endpoint)
        return endpoint
    end
    return cli_inj_start
end

"""
Locate the posterior export from the immediately previous monitoring step.
"""
function previous_step_posterior_path(monitoring_step::Int)
    previous_step = monitoring_step - 1
    previous_step >= 1 || error("Posterior prior requires monitoring_step >= 2, got $(monitoring_step)")

    filename = "three_set_posteriro_samples_t$(previous_step)_pof_cvar.jld2"
    candidates = [
        datadir("posterior", filename),
        datadir(filename),
    ]
    for path in candidates
        isfile(path) && return path
    end
    error("Posterior export not found for previous monitoring step $(previous_step). Tried: $(join(candidates, ", "))")
end

"""
Locate the permeability-index file for the requested monitoring step.

Indices are sourced from `data/state/new` and follow the `tN_rtmN` naming convention.
"""
function state_indices_path(monitoring_step::Int)
    monitoring_step >= 1 || error("monitoring_step must be >= 1, got $(monitoring_step)")
    path = datadir("state/new/Wise128_state_t$(monitoring_step)_rtm$(monitoring_step)_broad_NL_SNR28.jld2")
    isfile(path) || error("State indices file not found for monitoring_step=$(monitoring_step): $(path)")
    return path
end

"""
Load the monitoring-step-specific permeability index and permeability field for sample `s`.
"""
function load_step_context(monitoring_step::Int, s::Int, BroadK)
    state_path = state_indices_path(monitoring_step)
    state_data = JLD2.load(state_path)
    indices = state_data["idx_t" * string(monitoring_step)]
    idx = indices[s]
    K = BroadK[idx, :, :] * JutulDarcyRules.md
    return state_data, indices, idx, K
end

"""
Return the posterior cube for one risk case from the previous monitoring step.
"""
function load_posterior_case_cube(case_key::String, monitoring_step::Int)
    post_key = get(CASE_TO_POST_KEY, case_key, nothing)
    post_key === nothing && error("No posterior dataset configured for case_key=$(case_key)")
    posterior_path = previous_step_posterior_path(monitoring_step)
    posterior_data = JLD2.load(posterior_path)
    haskey(posterior_data, post_key) || error("Posterior dataset $(post_key) not found in $(posterior_path)")
    return posterior_data[post_key], post_key
end

"""
Legacy prior selection for step >= 2.

This path ignores case-specific posterior samples and instead chooses the
previous-step state sample with the smallest pressure gap to fracture pressure.
"""
function load_previous_step_prior(monitoring_step::Int, p_max::Array{Float64,2})
    prior_path = datadir("state/Wise_128SatPres_for_Optim_Inj_vec_ir_k" * string(monitoring_step - 1) * ".jld2")
    prior_data = JLD2.load(prior_path)
    pres_samples = prior_data["pres_samples"]
    sat_samples = prior_data["sat_samples"]
    nsamples = 128
    min_each_sample = map(i -> minimum(p_max - slice_sample_3d(pres_samples, i, size(p_max))), 1:nsamples)
    global_min_idx = argmin(min_each_sample)
    sat_init = slice_sample_3d(sat_samples, global_min_idx, size(p_max))
    pres_init = slice_sample_3d(pres_samples, global_min_idx, size(p_max))
    return sat_init, pres_init, Dict("source" => "legacy_previous_step", "posterior_key" => "legacy", "sample_idx" => global_min_idx)
end

"""
Posterior-driven prior-state initialization.

For `paired_posterior_sample`, permeability sample `s` is paired with posterior
sample `s` from the selected case cube. For `pointwise_median`, we collapse the
sample axis before assigning the previous saturation/pressure state.
"""
function load_posterior_prior(prior_mode::String, monitoring_step::Int, case_key::String, s::Int, p_max::Array{Float64,2})
    monitoring_step >= 2 || error("Posterior-based prior_mode=$(prior_mode) requires monitoring_step >= 2, got $(monitoring_step)")
    posterior_cube, post_key = load_posterior_case_cube(case_key, monitoring_step)
    size(posterior_cube, 4) >= s || error("Posterior cube $(post_key) has only $(size(posterior_cube, 4)) samples; requested sample $(s).")

    sat_init = if prior_mode == "pointwise_median"
        align_state_grid(dropdims(mapslices(median, posterior_cube[:, :, 1, :]; dims=(3,)); dims=3), size(p_max))
    else
        align_state_grid(posterior_cube[:, :, 1, s], size(p_max))
    end
    pres_init = if prior_mode == "pointwise_median"
        align_state_grid(dropdims(mapslices(median, posterior_cube[:, :, 2, :]; dims=(3,)); dims=3), size(p_max))
    else
        align_state_grid(posterior_cube[:, :, 2, s], size(p_max))
    end
    sample_idx = prior_mode == "paired_posterior_sample" ? s : 0
    return sat_init, pres_init, Dict("source" => prior_mode, "posterior_key" => post_key, "sample_idx" => sample_idx)
end

"""
Build the previous-state initialization used by the forward simulation.

- step 1: seeded synthetic saturation blob near the injector, no prior pressure
- legacy_previous_step: use the old heuristic previous-step state selection
- posterior modes: use case-specific posterior samples/summary states
"""
function load_prior_state(prior_mode::String, monitoring_step::Int, case_key::String, s::Int,
                          p_max::Array{Float64,2}, K, n)
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
        return S0, nothing, Dict("source" => "step1_randomized", "posterior_key" => "none", "sample_idx" => 0)
    end

    if prior_mode == "legacy_previous_step"
        return load_previous_step_prior(monitoring_step, p_max)
    end
    return load_posterior_prior(prior_mode, monitoring_step, case_key, s, p_max)
end

"""
Load the full permeability ensemble shared by all monitoring steps.
"""
function load_perm_ensemble()
    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    perm_data = JLD2.load(perm_path)
    return perm_data["BroadK"]
end
