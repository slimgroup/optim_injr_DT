"""
Case-name normalization and risk-option helpers shared by `optim_inject.jl`.
Keeping these utilities separate makes the main optimization driver easier to scan.
"""
const DEFAULT_INJ_START = 0.0001
const CASE_TO_POST_KEY = Dict(
    "pof_eps0.0" => "X_post1",
    "pof_eps0.01" => "X_post2",
    "cvar_g0.1_a0.01" => "X_post3",
)
const CASE_TO_INJ_START = Dict(
    "pof_eps0.0" => 0.02630,
    "pof_eps0.01" => 0.04530,
    "cvar_g0.1_a0.01" => 0.07470,
)

function last_nonzero_endpoint(inj_rate_arr)
    vals = vec(Float64.(inj_rate_arr))
    clean = filter(x -> isfinite(x) && !iszero(x), vals)
    isempty(clean) && return nothing
    return clean[end]
end

"""
Normalize user-facing case labels into the canonical keys used in filenames and metadata.
"""
function canonical_case_key(case_key::AbstractString)
    key = lowercase(strip(case_key))
    key = replace(key, " " => "", "ε" => "eps", "γ" => "g", "," => "", ";" => "")
    aliases = Dict(
        "auto" => "auto",
        "pof_eps=0.0" => "pof_eps0.0",
        "pof_eps=0" => "pof_eps0.0",
        "pof_eps0" => "pof_eps0.0",
        "pof_eps0.0" => "pof_eps0.0",
        "pof_eps=0.01" => "pof_eps0.01",
        "pof_eps0.01" => "pof_eps0.01",
        "cvar_g=0.1_a=0.01" => "cvar_g0.1_a0.01",
        "cvar_g0.1_a0.01" => "cvar_g0.1_a0.01",
        "cvar_gamma0.1_alpha0.01" => "cvar_g0.1_a0.01",
    )
    return get(aliases, key, key)
end

"""
Normalize prior-mode aliases while preserving the existing CLI interface.
"""
function canonical_prior_mode(prior_mode::AbstractString)
    mode = lowercase(strip(prior_mode))
    mode = replace(mode, "-" => "_", " " => "_")
    aliases = Dict(
        "legacy" => "legacy_previous_step",
        "legacy_previous_step" => "legacy_previous_step",
        "pointwise_median" => "pointwise_median",
        "median" => "pointwise_median",
        "paired_posterior_sample" => "paired_posterior_sample",
        "paired" => "paired_posterior_sample",
    )
    haskey(aliases, mode) || error("Unsupported prior_mode: $(prior_mode)")
    return aliases[mode]
end

"""
Infer the canonical case key from the active risk settings when `--case_key auto` is used.
"""
function infer_case_key(risk_opts; requested::AbstractString="auto")
    case_key = canonical_case_key(requested)
    case_key != "auto" && return case_key

    if risk_opts.use_cvar && isapprox(risk_opts.γ, 0.1; atol=1e-12) && isapprox(risk_opts.α, 0.01; atol=1e-12)
        return "cvar_g0.1_a0.01"
    elseif risk_opts.use_pof && isapprox(risk_opts.ε, 0.01; atol=1e-12)
        return "pof_eps0.01"
    elseif risk_opts.use_pof && isapprox(risk_opts.ε, 0.0; atol=1e-12)
        return "pof_eps0.0"
    end

    error("Could not infer case_key from risk settings. Please pass --case_key explicitly.")
end

"""
Normalize CLI risk arguments into one immutable tuple used everywhere else.
"""
function build_risk_options(args, α_tail::Float64)
    risk_mode = args["risk_mode"] == "window" ? :window : :relative
    return (
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
end
