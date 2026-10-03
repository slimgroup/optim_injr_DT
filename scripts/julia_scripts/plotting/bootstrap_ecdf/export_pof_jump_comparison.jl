#!/usr/bin/env julia
# Evaluate one frozen single-case bootstrap on observed jumps only.
# Submit through submit_pof_jump_comparison.sh; no raw-run collection or simulation.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"

using JLD2, Random, Statistics, SHA, TOML, Printf

function main()
    length(ARGS) == 2 || error("Usage: export_pof_jump_comparison.jl CACHE_JLD2 NEW_OUTPUT_DIR")
    cachepath, outdir = abspath.(ARGS)
    ispath(outdir) && error("Refusing to replace existing output directory: $outdir")
    source_hash = bytes2hex(sha256(read(cachepath)))
    saved = JLD2.load(cachepath)
    cr = saved["case_result"]
    data = cr["data"]
    n = length(data)
    B = saved["bootstrap_resamples"]
    conf, target, seed = saved["confidence"], saved["threshold"], saved["seed"]
    @assert n == 128 && B == 10000 && conf == 0.95 && target == 0.01
    @assert saved["schedule_element"] == 6 && saved["schedule_length"] == 12
    points = sort(unique(data))
    sorted_data = sort(data)
    empirical = [searchsortedlast(sorted_data, q) / n for q in points]
    boot = zeros(B, length(points))
    rng = MersenneTwister(seed)
    # Identical draws and quantile arithmetic to boot_ecdf_ci_at in the source
    # generator; only the evaluation locations change from 1500 to 89 points.
    for b in 1:B
        resample = sort(data[rand(rng, 1:n, n)])
        boot[b, :] .= [searchsortedlast(resample, q) for q in points] ./ n
    end
    alpha = 1 - conf
    lower = [quantile(view(boot, :, i), alpha / 2) for i in eachindex(points)]
    upper = [quantile(view(boot, :, i), 1 - alpha / 2) for i in eachindex(points)]
    # Map the step functions back onto every old grid point. This verifies
    # the same bootstrap realization, including all cached confidence values.
    idx = searchsortedlast.(Ref(points), cr["xg"])
    on_grid(v) = [i == 0 ? 0.0 : v[i] for i in idx]
    @assert on_grid(empirical) == cr["ecdf_v"]
    @assert on_grid(lower) == cr["ci_lo"]
    @assert on_grid(upper) == cr["ci_hi"]
    crossing(v) = points[findfirst(>=(target), v)]
    @assert crossing(upper) == cr["x_conservative"]
    @assert crossing(empirical) == cr["x_ecdf"]
    @assert crossing(lower) == cr["x_optimistic"]
    source_hash == bytes2hex(sha256(read(cachepath))) || error("Source cache changed")

    mkpath(outdir)
    open(joinpath(outdir, "observed_jump_ecdf.csv"), "w") do io
        println(io, "rate,ecdf,ci_lower,ci_upper")
        for i in eachindex(points)
            @printf(io, "%.17g,%.17g,%.17g,%.17g\n", points[i], empirical[i], lower[i], upper[i])
        end
    end
    audit = Dict(
        "source_cache" => cachepath, "source_sha256" => source_hash,
        "ensemble_size" => n, "unique_jump_count" => length(points),
        "bootstrap_resamples" => B, "seed" => seed, "confidence" => conf,
        "target" => target, "schedule_element" => 6, "schedule_length" => 12,
        "old_grid_points" => length(cr["xg"]),
        "cached_ecdf_and_bands_identical_at_all_old_grid_points" => true,
        "all_three_crossings_identical" => true,
        "conservative" => crossing(upper), "ecdf" => crossing(empirical),
        "optimistic" => crossing(lower),
        "bootstrap_rerun" => "Same Julia MersenneTwister draws at observed jumps only",
        "simulations_or_optimization_rerun" => false,
    )
    open(joinpath(outdir, "verification.toml"), "w") do io
        TOML.print(io, audit; sorted=true)
    end
    TOML.print(stdout, audit; sorted=true)
end

main()
