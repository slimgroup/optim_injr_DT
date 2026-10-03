#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using Statistics
using Random
using Printf

const ROOT = datadir("DT_control", "exp_name=step2")
const OUTDIR = plotsdir("step2_prior_comparison_32samples")
const SAMPLES = 1:32
const B_BOOT = 10000
const CONF_LEVEL = 0.95
const THRESHOLD = 0.01
const ECDF_PTS = nothing # compatibility alias; no uniform plotting grid
const NBINS = 12
const SEED = 42
const FORWARD_STEP = 2
const SCHEDULE_LEN = FORWARD_STEP * 6
const PLOT_STEP_INDEX = 6

const CASE_TO_INJ_START = Dict(
    "pof_eps0.0" => 0.02630,
    "pof_eps0.01" => 0.04530,
    "cvar_g0.1_a0.01" => 0.07470,
)

const CASE_SPECS = [
    (
        case_key = "pof_eps0.01",
        dir = "case=pof_eps0.01__prior=pointwise_median__POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        slug = "pof_eps0.01_pointwise_median",
        title = "Step 2 PoF (eps=0.01) | pointwise median",
    ),
    (
        case_key = "pof_eps0.01",
        dir = "case=pof_eps0.01__prior=paired_posterior_sample__POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        slug = "pof_eps0.01_paired_posterior",
        title = "Step 2 PoF (eps=0.01) | paired posterior",
    ),
    (
        case_key = "cvar_g0.1_a0.01",
        dir = "case=cvar_g0.1_a0.01__prior=pointwise_median__CVaR__HARD__alpha=0.01__gamma=0.1__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
        slug = "cvar_g0.1_a0.01_pointwise_median",
        title = "Step 2 CVaR (g=0.1, a=0.01) | pointwise median",
    ),
    (
        case_key = "cvar_g0.1_a0.01",
        dir = "case=cvar_g0.1_a0.01__prior=paired_posterior_sample__CVaR__HARD__alpha=0.01__gamma=0.1__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
        slug = "cvar_g0.1_a0.01_paired_posterior",
        title = "Step 2 CVaR (g=0.1, a=0.01) | paired posterior",
    ),
]

function plotted_injection_rate(data, case_key::AbstractString; init_rate::Float64=1e-4)
    raw = get(data, "inj_rate_arr", nothing)
    raw === nothing && return init_rate
    col = ndims(raw) == 1 ? collect(raw) : vec(view(raw, :, 1))
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col)
    idx = findlast(!iszero, clean)
    endpoint = idx === nothing ? init_rate : clean[idx]
    inj_start = get(CASE_TO_INJ_START, case_key, init_rate)
    schedule = collect(range(inj_start, endpoint, length=SCHEDULE_LEN))
    return schedule[PLOT_STEP_INDEX]
end

function load_case_data(spec)
    case_dir = joinpath(ROOT, spec.dir)
    isdir(case_dir) || error("Missing case directory: $case_dir")
    rates = Float64[]
    missing = Int[]
    bad = Int[]

    for s in SAMPLES
        final_path = joinpath(case_dir, "sample=$(s)", "final.jld2")
        if !isfile(final_path)
            push!(missing, s)
            continue
        end
        try
            data = load(final_path)
            push!(rates, plotted_injection_rate(data, spec.case_key))
        catch err
            @warn "Failed to load sample $s for $(spec.slug): $err"
            push!(bad, s)
        end
    end

    return (; rates, missing, bad, count=length(rates))
end

function bootstrap_quantile(data::Vector{Float64}, q::Float64, B::Int; seed::Int=SEED)
    rng = MersenneTwister(seed)
    n = length(data)
    out = zeros(B)
    for b in 1:B
        out[b] = quantile(data[rand(rng, 1:n, n)], q)
    end
    out
end

function ecdf_values(sorted::Vector{Float64}, x_grid::Vector{Float64})
    [searchsortedlast(sorted, x) for x in x_grid] ./ length(sorted)
end

function bootstrap_ecdf_ci_at(data::Vector{Float64}, B::Int, x_grid::Vector{Float64}; conf::Float64=CONF_LEVEL, seed::Int=SEED)
    rng = MersenneTwister(seed)
    n = length(data)

    sorted_data = sort(data)
    ecdf_orig = ecdf_values(sorted_data, x_grid)

    boot = zeros(B, length(x_grid))
    for b in 1:B
        boot[b, :] .= ecdf_values(sort(data[rand(rng, 1:n, n)]), x_grid)
    end

    alpha = 1 - conf
    ci_lo = [quantile(view(boot, :, i), alpha / 2) for i in eachindex(x_grid)]
    ci_hi = [quantile(view(boot, :, i), 1 - alpha / 2) for i in eachindex(x_grid)]
    return x_grid, ecdf_orig, ci_lo, ci_hi
end

function bootstrap_ecdf_ci(data::Vector{Float64}, B::Int; conf::Float64=CONF_LEVEL, npts=ECDF_PTS, seed::Int=SEED)
    xmin, xmax = extrema(data)
    span = xmax - xmin
    margin = span == 0 ? max(abs(xmin) * 0.05, 1e-6) : 0.05 * span
    x_grid = vcat(xmin - margin, sort(unique(data)), xmax + margin)
    bootstrap_ecdf_ci_at(data, B, x_grid; conf=conf, seed=seed)
end

function find_threshold_crossing(x_grid, cdf_vals, threshold)
    idx = findfirst(v -> v >= threshold, cdf_vals)
    return idx === nothing ? nothing : x_grid[idx]
end

function bootstrap_jump_crossings(data::Vector{Float64}, B::Int; conf::Float64=CONF_LEVEL, threshold::Float64=THRESHOLD, seed::Int=SEED)
    jump_points = sort(unique(data))
    _, ecdf_orig, ci_lo, ci_hi = bootstrap_ecdf_ci_at(data, B, jump_points; conf=conf, seed=seed)
    return (
        find_threshold_crossing(jump_points, ci_hi, threshold),
        find_threshold_crossing(jump_points, ecdf_orig, threshold),
        find_threshold_crossing(jump_points, ci_lo, threshold),
    )
end

function build_case_stats(data::Vector{Float64})
    boot_q = bootstrap_quantile(data, THRESHOLD, B_BOOT)
    q_val = quantile(data, THRESHOLD)
    q_lo = quantile(boot_q, (1 - CONF_LEVEL) / 2)
    q_hi = quantile(boot_q, 1 - (1 - CONF_LEVEL) / 2)
    x_grid, ecdf_orig, ci_lo, ci_hi = bootstrap_ecdf_ci(data, B_BOOT)
    x_cons, x_ecdf, x_opt = (find_threshold_crossing(x_grid, v, THRESHOLD) for v in (ci_hi, ecdf_orig, ci_lo))
    return (;
        boot_q, q_val, q_lo, q_hi,
        x_grid, ecdf_orig, ci_lo, ci_hi,
        x_cons, x_ecdf, x_opt,
    )
end

function annotate_summary(ax, data::Vector{Float64}, stats)
    summary = @sprintf(
        "n=%d\nmean=%.5f\nmedian=%.5f\nstd=%.5f\n1%% q=%.5f",
        length(data), mean(data), median(data), std(data), stats.q_val
    )
    ax.text(
        0.98, 0.96, summary;
        transform=ax.transAxes,
        fontsize=10,
        va="top",
        ha="right",
        bbox=Dict(
            "boxstyle" => "round,pad=0.35",
            "facecolor" => "white",
            "edgecolor" => "#9E9E9E",
            "alpha" => 0.95,
        ),
    )
end

function plot_histogram(data::Vector{Float64}, stats, title::AbstractString, outfile::AbstractString)
    fig = figure(figsize=(8.6, 5.8))
    ax = fig.add_subplot(111)

    xmin, xmax = extrema(data)
    span = xmax - xmin
    if span == 0
        edges = collect(range(xmin - 1e-6, xmax + 1e-6, length=NBINS + 1))
    else
        edges = collect(range(xmin, xmax, length=NBINS + 1))
    end

    ax.hist(data, bins=edges, color="#7FB3D5", edgecolor="#1F618D", alpha=0.8, linewidth=0.8)
    ax.axvline(stats.q_val, color="#1E8449", linewidth=2.2, linestyle="-", label=@sprintf("1%% quantile = %.5f", stats.q_val))
    ax.axvline(stats.q_lo, color="#CB4335", linewidth=1.6, linestyle="--", label=@sprintf("95%% CI lower = %.5f", stats.q_lo))
    ax.axvline(stats.q_hi, color="#7D3C98", linewidth=1.6, linestyle="--", label=@sprintf("95%% CI upper = %.5f", stats.q_hi))
    ax.axvspan(stats.q_lo, stats.q_hi, color="#D7BDE2", alpha=0.25)

    annotate_summary(ax, data, stats)
    ax.set_title("$(title)\nHistogram of optimized injection schedule element 6/12", fontsize=14, fontweight="bold")
    ax.set_xlabel("Injection rate (m^3/s)", fontsize=12)
    ax.set_ylabel("Count", fontsize=12)
    ax.grid(true, linestyle="--", linewidth=0.4, alpha=0.4)
    ax.legend(loc="upper left", fontsize=10, framealpha=0.95)
    tight_layout()
    savefig(outfile, dpi=220, bbox_inches="tight")
    close(fig)
end

function plot_cdf(data::Vector{Float64}, stats, title::AbstractString, outfile::AbstractString)
    fig = figure(figsize=(8.6, 5.8))
    ax = fig.add_subplot(111)

    ax.fill_between(stats.x_grid, stats.ci_lo .* 100, stats.ci_hi .* 100, step="post", color="#AED6F1", alpha=0.55, label="95% bootstrap CI")
    ax.step(stats.x_grid, stats.ecdf_orig .* 100, where="post", color="#1F618D", linewidth=2.2, label="Empirical CDF")
    ax.axhline(THRESHOLD * 100, color="#C0392B", linewidth=1.5, linestyle="--", label="1% threshold")

    marker_specs = [
        (stats.x_cons, "#D35400", "CI upper crossing"),
        (stats.x_ecdf, "#117A65", "ECDF crossing"),
        (stats.x_opt, "#5B2C6F", "CI lower crossing"),
    ]
    for (xv, color, label) in marker_specs
        if xv !== nothing
            ax.plot(xv, THRESHOLD * 100, marker="*", color=color, markersize=11, label=label)
        end
    end

    annotate_summary(ax, data, stats)
    ax.set_title("$(title)\nCDF of optimized injection schedule element 6/12 with 95% bootstrap CI", fontsize=14, fontweight="bold")
    ax.set_xlabel("Injection rate (m^3/s)", fontsize=12)
    ax.set_ylabel("Probability (%)", fontsize=12)
    ax.set_ylim(0, 100)
    ax.grid(true, linestyle="--", linewidth=0.4, alpha=0.4)
    ax.legend(loc="upper left", fontsize=9.5, framealpha=0.95)

    inset = ax.inset_axes([0.43, 0.10, 0.52, 0.45])
    inset.fill_between(stats.x_grid, stats.ci_lo .* 100, stats.ci_hi .* 100, step="post", color="#AED6F1", alpha=0.55)
    inset.step(stats.x_grid, stats.ecdf_orig .* 100, where="post", color="#1F618D", linewidth=1.5)
    inset.axhline(THRESHOLD * 100, color="#C0392B", linewidth=1.0, linestyle="--")
    zoom_points = Float64[x for x in (stats.x_cons, stats.x_ecdf, stats.x_opt) if x !== nothing]
    if !isempty(zoom_points)
        zmin = minimum(zoom_points) * 0.90
        zmax = maximum(zoom_points) * 1.10
    else
        zmin = minimum(data)
        zmax = maximum(data)
    end
    inset.set_xlim(zmin, zmax)
    inset.set_ylim(0, 8)
    inset.set_title("Left-tail zoom", fontsize=9)
    inset.tick_params(labelsize=8)
    inset.grid(true, linestyle="--", linewidth=0.3, alpha=0.35)

    if stats.x_cons !== nothing
        inset.plot(stats.x_cons, THRESHOLD * 100, marker="*", color="#D35400", markersize=12, zorder=5)
        inset.annotate(
            @sprintf("q_k*\n%.4f", stats.x_cons),
            xy=(stats.x_cons, THRESHOLD * 100),
            xytext=(-26, 20),
            textcoords="offset points",
            fontsize=8.5,
            color="#D35400",
            fontweight="bold",
            ha="center",
            bbox=Dict("boxstyle" => "round,pad=0.18", "facecolor" => "#FEF5E7", "alpha" => 0.92, "edgecolor" => "#D35400"),
            arrowprops=Dict("arrowstyle" => "->", "color" => "#D35400"),
        )
    end
    if stats.x_ecdf !== nothing
        inset.plot(stats.x_ecdf, THRESHOLD * 100, marker="*", color="#117A65", markersize=12, zorder=5)
        inset.annotate(
            @sprintf("ECDF\n%.4f", stats.x_ecdf),
            xy=(stats.x_ecdf, THRESHOLD * 100),
            xytext=(0, 38),
            textcoords="offset points",
            fontsize=8.5,
            color="#196F3D",
            fontweight="bold",
            ha="center",
            bbox=Dict("boxstyle" => "round,pad=0.18", "facecolor" => "#EAFAF1", "alpha" => 0.92, "edgecolor" => "#196F3D"),
            arrowprops=Dict("arrowstyle" => "->", "color" => "#196F3D"),
        )
    end
    if stats.x_opt !== nothing
        inset.plot(stats.x_opt, THRESHOLD * 100, marker="*", color="#2E86C1", markersize=12, zorder=5)
        inset.annotate(
            @sprintf("Opt.\n%.4f", stats.x_opt),
            xy=(stats.x_opt, THRESHOLD * 100),
            xytext=(26, 20),
            textcoords="offset points",
            fontsize=8.5,
            color="#1F4E79",
            fontweight="bold",
            ha="center",
            bbox=Dict("boxstyle" => "round,pad=0.18", "facecolor" => "#EBF5FB", "alpha" => 0.92, "edgecolor" => "#2E86C1"),
            arrowprops=Dict("arrowstyle" => "->", "color" => "#2E86C1"),
        )
    end
    ax.indicate_inset_zoom(inset, edgecolor="gray", alpha=0.5)

    tight_layout()
    savefig(outfile, dpi=220, bbox_inches="tight")
    close(fig)
end

function main()
    mkpath(OUTDIR)
    println("Output directory: $OUTDIR")
    println("Using samples: $(first(SAMPLES))-$(last(SAMPLES))")

    for spec in CASE_SPECS
        println("\n=== $(spec.slug) ===")
        result = load_case_data(spec)
        println("count=$(result.count) missing=$(result.missing) bad=$(result.bad)")
        result.count == length(SAMPLES) || error("Expected $(length(SAMPLES)) samples for $(spec.slug), got $(result.count)")

        stats = build_case_stats(result.rates)
        hist_out = joinpath(OUTDIR, "hist_" * spec.slug * ".png")
        cdf_out = joinpath(OUTDIR, "cdf_" * spec.slug * ".png")
        plot_histogram(result.rates, stats, spec.title, hist_out)
        plot_cdf(result.rates, stats, spec.title, cdf_out)
        println(@sprintf("1%% quantile=%.5f, CI=[%.5f, %.5f]", stats.q_val, stats.q_lo, stats.q_hi))
    end

    println("\nDone.")
end

main()
