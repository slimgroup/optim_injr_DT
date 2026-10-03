#!/usr/bin/env julia
# Recompute only the existing step-1 PoF eps=0.01 figure statistics and export
# Figures 6--7 with four fixed decimal places. Run through the matching sbatch
# script; existing images and analysis artifacts are never replaced.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"

withenv("BOOTSTRAP_DEFINE_ONLY" => "1") do
    include(joinpath(@__DIR__, "plot_bootstrap_panels.jl"))
end
using TOML

function main_figures_6_7()
    length(ARGS) == 2 || error("Usage: reexport_figures_6_7.jl OUTPUT_DIR CACHE_DIR")
    outdir, cachedir = abspath.(ARGS)
    histpath = joinpath(outdir, "hist_POF_eps0.01.png")
    cdfpath = joinpath(outdir, "cdf_POF_eps0.01.png")
    cachepath = joinpath(cachedir, "case_result.jld2")
    summarypath = joinpath(cachedir, "summary.toml")
    for path in (histpath, cdfpath, cachepath, summarypath)
        ispath(path) && error("Refusing to replace existing output: $path")
    end
    mkpath(outdir)
    mkpath(cachedir)

    # Same directory matching, sample order and scalar extractor as the existing
    # plotting pipeline. Read just the injection array; fail on unreadable inputs.
    dirs = filter(d -> isdir(joinpath(ROOT, d)) &&
                      occursin("POF__HARD__eps=0.01__", d), readdir(ROOT))
    length(dirs) == 1 || error("Expected exactly one matching PoF eps=0.01 case")
    data = Float64[]
    sample_paths = String[]
    missing_samples = Int[]
    for sample in 1:128
        path = joinpath(ROOT, only(dirs), "sample=$(sample)", "final.jld2")
        if !isfile(path)
            push!(missing_samples, sample)
            continue
        end
        raw = JLD2.load(path, "inj_rate_arr")
        rate = last_nonzero_inj_rate(Dict("inj_rate_arr" => raw))
        isfinite(rate) || error("Non-finite rate: $path")
        push!(data, rate)
        push!(sample_paths, path)
    end
    isempty(missing_samples) || error("Original 128-sample set incomplete: $missing_samples")
    length(data) == 128 || error("Expected the original 128 completed samples")
    println("Loaded 128 completed samples; scalar is schedule element 6/12.")

    cr = compute_case(data, "PoF (eps=0.01)"; B=B_SINGLE)
    @assert cr.x_conservative <= cr.x_ecdf <= cr.x_optimistic
    @assert issorted(cr.ecdf_v) && all(0 .<= cr.ci_lo .<= cr.ci_hi .<= 1)
    # Check the plotted ECDF directly against the loaded sample values.
    @assert cr.ecdf_v == [count(v -> v <= x, data) / length(data) for x in cr.xg]

    result_fields = Dict(string(field) => getfield(cr, field) for field in fieldnames(CaseResult))
    JLD2.jldsave(cachepath; case_result=result_fields, sample_paths=sample_paths,
                 histogram_edges=collect(range(minimum(data), maximum(data), length=NBINS+1)),
                 bootstrap_resamples=B_SINGLE, confidence=CONF, threshold=THRESH, seed=SEED,
                 schedule_element=6, schedule_length=12, inj_start=INJ_START)

    summary = Dict(
        "n" => cr.n, "mean" => mean(data), "std" => std(data),
        "minimum" => minimum(data), "maximum" => maximum(data),
        "quantile_1pct" => cr.q_val, "quantile_ci_lower" => cr.ci_lo_q,
        "quantile_ci_upper" => cr.ci_hi_q, "selected_rate" => cr.x_conservative,
        "ecdf_crossing" => cr.x_ecdf, "optimistic_crossing" => cr.x_optimistic,
        "bootstrap_resamples" => B_SINGLE, "confidence" => CONF,
        "threshold" => THRESH, "seed" => SEED, "bins" => NBINS,
        "plot_grid_points" => length(cr.xg), "plotting_method" => "observed jumps, post steps", "schedule_element" => 6,
        "schedule_length" => 12, "inj_start" => INJ_START,
        "rate_decimals" => 4, "dpi" => 200,
        "matplotlib_version" => string(matplotlib.__version__),
        "crossing_method" => "Existing script: bootstrap band crossings at observed ECDF jumps",
        "missing_samples" => missing_samples,
    )
    open(summarypath, "w") do io
        TOML.print(io, summary; sorted=true)
    end
    TOML.print(stdout, summary; sorted=true)

    plot_single_hist(cr, histpath; four_decimal_rates=true)
    plot_single_cdf(cr, cdfpath; four_decimal_rates=true)
    println("Finished: exactly two new PNG figures; full-precision result cached at $cachepath")
end

main_figures_6_7()
