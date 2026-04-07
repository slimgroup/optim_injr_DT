"""
Directory naming and output-path helpers for optimization runs.
These keep path conventions in one place instead of mixing them into the solver logic.
"""
function case_dirname(risk; case_key::String, prior_mode::String)
    parts = String[
        "case=$(case_key)", "prior=$(prior_mode)",
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

"""
Fallback directory tag used by earlier runs that did not encode case/prior metadata.
"""
function legacy_case_dirname(risk)
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

"""
Return candidate directories from the immediately previous monitoring step.

The search prefers the new case-aware naming first, then legacy folders, and finally
other case-matching directories as a compatibility fallback.
"""
function previous_step_case_dir_candidates(monitoring_step::Int, case_key::String, prior_mode::String, risk)
    previous_step = monitoring_step - 1
    previous_step >= 1 || return String[]

    exp_root = datadir("DT_control", "exp_name=step$(previous_step)")
    isdir(exp_root) || return String[]

    candidates = String[]
    push!(candidates, joinpath(exp_root, case_dirname(risk; case_key=case_key, prior_mode=prior_mode)))
    push!(candidates, joinpath(exp_root, legacy_case_dirname(risk)))

    if previous_step >= 2
        for name in sort(readdir(exp_root))
            startswith(name, "case=$(case_key)__") || continue
            path = joinpath(exp_root, name)
            isdir(path) || continue
            path in candidates || push!(candidates, path)
        end
    end

    return unique(candidates)
end

"""
Human-readable tag for one optimization run.
"""
function scenariotag(risk; step::Int, idx::Int, case_key::String, prior_mode::String)
    parts = String[
        "step$(step)", "idx$(idx)", "case=$(case_key)", "prior=$(prior_mode)",
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
    return join(filter(!isempty, parts), "__")
end

"""
Create and return the data / scratch / plotting paths for one run.
"""
function build_output_paths(sim_name::String, monitoring_step::Int, case_tag::String, sample_idx::Int)
    exp_layer = "exp_name=step$(monitoring_step)"
    sample_tag = savename(@strdict(sample=sample_idx); digits=6)

    data_root  = datadir(sim_name, exp_layer, case_tag)
    out_root   = joinpath(data_root, sample_tag)
    mkpath(out_root)

    scratch_root = get(ENV, "SCRATCH") do
        joinpath(homedir(), "scratch")
    end
    mkpath(scratch_root)
    scratch_out_root = joinpath(scratch_root, "optim_injr_DT", sim_name, exp_layer, case_tag, sample_tag)
    mkpath(scratch_out_root)

    plot_path = plotsdir(sim_name, exp_layer, "states", case_tag)
    mkpath(plot_path)

    return (
        exp_layer = exp_layer,
        sample_tag = sample_tag,
        data_root = data_root,
        out_root = out_root,
        scratch_out_root = scratch_out_root,
        plot_path = plot_path,
    )
end
