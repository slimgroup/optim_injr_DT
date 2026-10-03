#!/usr/bin/env julia
# Render the reviewed ECDFs or histogram grids, sharing one result per case.
# Existing final.jld2 inputs are read-only; no simulation or optimization runs.
ENV["BOOTSTRAP_DEFINE_ONLY"] = "1"
include(joinpath(@__DIR__, "plot_bootstrap_panels.jl"))
using TOML, SHA

function render_ecdf_figures(results, plotdir)
    pof = only(filter(cr -> cr.title == "PoF ε=0.01", results))
    plot_single_cdf(retitle_case(pof, "PoF (eps=0.01)"), joinpath(plotdir, "cdf_POF_eps0.01.png"))
    plot_grid_cdf(results, joinpath(plotdir, "grid_cdf_4x3.png"))
    plot_selected_cdf(select_cases(results, SELECTED_GRID), joinpath(plotdir, "grid_cdf_selected_1x3.png"))
    open(joinpath(plotdir, "render_provenance.toml"), "w") do io
        TOML.print(io, Dict("plot_source_sha256" => bytes2hex(open(sha256, joinpath(@__DIR__, "plot_bootstrap_panels.jl"))),
            "slurm_job_id" => get(ENV, "SLURM_JOB_ID", ""), "plotting_method" => "post steps"); sorted=true)
    end
end

function render_histogram_figures(results, plotdir, cachepath)
    selected = select_cases(results, SELECTED_GRID)
    plot_grid_histogram(results, joinpath(plotdir, "grid_histogram_4x3.png"))
    plot_selected_histogram(selected, joinpath(plotdir, "grid_histogram_selected_1x3.png"))
    panels = Dict{String,Any}[]
    for (group, cases) in (("4x3", results), ("1x3", selected))
        edges = collect(range(minimum(minimum(cr.data) for cr in cases),
                              maximum(maximum(cr.data) for cr in cases), length=NBINS+1))
        for cr in cases
            # NumPy/Matplotlib bins are left-closed; the final bin includes its right edge.
            counts = [count(x -> edges[i] <= x < edges[i+1] ||
                                (i == NBINS && x == edges[end]), cr.data) for i in 1:NBINS]
            @assert sum(counts) == cr.n
            push!(panels, Dict("grid" => group, "case" => cr.title,
                "n" => cr.n, "q_k_star" => cr.x_conservative, "quantile_1pct" => cr.q_val,
                "mean" => mean(cr.data), "std" => std(cr.data),
                "minimum" => minimum(cr.data), "maximum" => maximum(cr.data),
                "bin_edges" => edges, "counts" => counts))
        end
    end
    open(joinpath(plotdir, "histogram_verification.toml"), "w") do io
        TOML.print(io, Dict("panels" => panels, "bins" => NBINS,
            "cache_sha256" => bytes2hex(open(sha256, cachepath)),
            "plot_source_sha256" => bytes2hex(open(sha256, joinpath(@__DIR__, "plot_bootstrap_panels.jl"))),
            "slurm_job_id" => get(ENV, "SLURM_JOB_ID", ""),
            "statistics_recomputed" => false,
            "selection_method" => "same observed-jump upper-CDF-band crossing as ECDFs"); sorted=true)
    end
end

function main_ecdf_jumps()
    length(ARGS) in (2, 3) || error("Usage: reexport_step1_ecdf_jumps.jl NEW_PLOT_DIR CACHE_DIR [--render-only|--histograms-only]")
    plotdir, cachedir = abspath.(ARGS[1:2])
    if length(ARGS) == 3
        ARGS[3] in ("--render-only", "--histograms-only") || error("Unknown option: $(ARGS[3])")
        ispath(plotdir) && error("Refusing to replace an existing plot directory: $plotdir")
        cachepath = joinpath(cachedir, "case_results.jld2")
        cases = JLD2.load(cachepath, "cases")
        results = [CaseResult((case[string(f)] for f in fieldnames(CaseResult))...) for case in cases]
        mkpath(plotdir)
        if ARGS[3] == "--histograms-only"
            render_histogram_figures(results, plotdir, cachepath)
        else
            render_ecdf_figures(results, plotdir)
        end
        return
    end
    for path in (plotdir, cachedir)
        ispath(path) && error("Refusing to replace an existing run directory: $path")
    end
    mkpath(plotdir); mkpath(cachedir)

    # Ties and constant data must retain the complete mass at the actual jump.
    for values in ([1.0, 1.0, 2.0, 3.0], fill(2.0, 4))
        xs, ev, lo, hi = boot_ecdf_ci(values, 100)
        @assert xs[2:end-1] == sort(unique(values))
        @assert ev == [count(v -> v <= x, values) / length(values) for x in xs]
        @assert (ev[1], lo[1], hi[1]) == (0.0, 0.0, 0.0)
        @assert (ev[end], lo[end], hi[end]) == (1.0, 1.0, 1.0)
    end

    results = CaseResult[]
    saved = Dict{String,Any}[]
    summaries = Dict{String,Any}[]
    for (pattern, title) in GRID
        dirs = filter(d -> isdir(joinpath(ROOT, d)) && occursin(pattern, d), readdir(ROOT))
        length(dirs) == 1 || error("Expected exactly one case matching $pattern: $dirs")
        paths = [joinpath(ROOT, only(dirs), "sample=$s", "final.jld2") for s in 1:128]
        missing = findall(p -> !isfile(p), paths)
        isempty(missing) || error("Missing final.jld2 for $title, samples $missing; report separately, never insert zeros")
        rates = Float64[]
        input_digests = String[]
        for path in paths
            raw = JLD2.load(path, "inj_rate_arr")
            col = ndims(raw) == 1 ? vec(raw) : vec(raw[:, 1])
            any(v -> isfinite(v) && !iszero(v), col) || error("No finite nonzero endpoint: $path")
            push!(input_digests, bytes2hex(sha256(reinterpret(UInt8, vec(Float64.(raw))))))
            push!(rates, last_nonzero_inj_rate(Dict("inj_rate_arr" => raw)))
        end
        all(isfinite, rates) || error("Invalid reconstructed rates: $title")
        cr = compute_case(rates, title; B=B_GRID)
        @assert cr.n == 128
        @assert cr.xg[2:end-1] == sort(unique(rates))
        @assert cr.ecdf_v == [count(v -> v <= x, rates) / cr.n for x in cr.xg]
        @assert all(0 .<= cr.ci_lo .<= cr.ci_hi .<= 1)
        @assert issorted(cr.ecdf_v) && issorted(cr.ci_lo) && issorted(cr.ci_hi)
        @assert cr.x_conservative <= cr.x_ecdf <= cr.x_optimistic
        for x in (cr.x_conservative, cr.x_ecdf, cr.x_optimistic)
            @assert x in rates
        end
        push!(results, cr)
        fields = Dict(string(f) => getfield(cr, f) for f in fieldnames(CaseResult))
        fields["sample_paths"] = paths
        fields["inj_rate_arr_sha256"] = input_digests
        push!(saved, fields)
        push!(summaries, Dict("case" => title, "n" => cr.n,
            "unique_jumps" => length(unique(rates)), "q_k_star" => cr.x_conservative,
            "ecdf_crossing" => cr.x_ecdf, "optimistic_crossing" => cr.x_optimistic,
            "missing_final_samples" => missing))
        println("$title: n=$(cr.n), jumps=$(length(unique(rates))), q*=$(cr.x_conservative)")
        flush(stdout)
    end

    pof = only(filter(cr -> cr.title == "PoF ε=0.01", results))
    old_cache = datadir("figure_exports", "figures6_7_decimal4_20260910_005149", "case_result.jld2")
    old = JLD2.load(old_cache, "case_result")
    @assert pof.data == old["data"]
    @assert pof.boot_q == old["boot_q"]
    for name in ("q_val", "ci_lo_q", "ci_hi_q", "x_conservative", "x_ecdf", "x_optimistic")
        @assert getfield(pof, Symbol(name)) == old[name]
    end
    # Exact post-step evaluation must reproduce all 1,500 old grid ordinates.
    mapped = [searchsortedlast(pof.xg, x) for x in old["xg"]]
    for name in ("ecdf_v", "ci_lo", "ci_hi")
        @assert getfield(pof, Symbol(name))[mapped] == old[name]
    end
    JLD2.jldsave(joinpath(cachedir, "case_results.jld2"); cases=saved,
        bootstrap_resamples=B_GRID, confidence=CONF, threshold=THRESH, seed=SEED,
        schedule_element=6, schedule_length=12, inj_start=INJ_START,
        crossing_method="first observed jump with CDF >= threshold", plotting_method="post steps")

    summary = Dict("cases" => summaries, "monitoring_step" => 1,
        "prior_mode" => "initial ensemble", "bootstrap_resamples" => B_GRID,
        "confidence" => CONF, "threshold" => THRESH, "seed" => SEED,
        "schedule_element" => 6, "schedule_length" => 12, "inj_start" => INJ_START,
        "plotting_method" => "right-continuous observed jumps; no uniform 1500 grid",
        "simulation_or_optimization_rerun" => false,
        "pof_frozen_cache_values_identical" => true,
        "pof_all_old_grid_ecdf_and_band_ordinates_identical" => true,
        "frozen_cache_sha256" => bytes2hex(open(sha256, old_cache)),
        "plot_source_sha256" => bytes2hex(open(sha256, joinpath(@__DIR__, "plot_bootstrap_panels.jl"))),
        "slurm_job_id" => get(ENV, "SLURM_JOB_ID", ""))
    open(joinpath(cachedir, "verification.toml"), "w") do io
        TOML.print(io, summary; sorted=true)
    end
    render_ecdf_figures(results, plotdir)
    println("Verified and rendered all three ECDF PNGs. Histograms untouched.")
end

main_ecdf_jumps()
