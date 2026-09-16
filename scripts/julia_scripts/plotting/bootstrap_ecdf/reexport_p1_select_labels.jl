#!/usr/bin/env julia
# Label-only export from a saved CaseResult. Never collect samples or calculate
# bootstrap results/crossings here. OUTPUT_DIR must not already exist.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"

withenv("BOOTSTRAP_DEFINE_ONLY" => "1") do
    include(joinpath(@__DIR__, "plot_bootstrap_panels.jl"))
end
using SHA, TOML

function main_label_export()
    length(ARGS) == 2 || error("Usage: reexport_p1_select_labels.jl CACHE_JLD2 NEW_OUTPUT_DIR")
    cachepath, outdir = abspath.(ARGS)
    ispath(outdir) && error("Refusing to replace existing output directory: $outdir")
    cachehash = bytes2hex(sha256(read(cachepath)))
    saved = JLD2.load(cachepath)
    saved["confidence"] == CONF || error("Cached confidence differs from plotting configuration")
    saved["threshold"] == THRESH || error("Cached target differs from plotting configuration")
    fields = saved["case_result"]
    cr = CaseResult((fields[string(field)] for field in fieldnames(CaseResult))...)
    mkpath(outdir)
    # Match the explicitly requested canonical PNG, which uses the legacy tick
    # formatting; the separate decimal4 export is a different historical asset.
    plot_single_cdf(cr, joinpath(outdir, "cdf_POF_eps0.01.png"))
    cachehash == bytes2hex(sha256(read(cachepath))) || error("Input cache changed")
    open(joinpath(outdir, "cache_provenance.toml"), "w") do io
        TOML.print(io, Dict(
            "slide_id" => "p1-select",
            "cache_path" => cachepath,
            "cache_sha256" => cachehash,
            "confidence" => saved["confidence"],
            "threshold" => saved["threshold"],
            "statistics_recomputed" => false,
            "rate_formatting" => "four decimal places in annotations; canonical axis ticks unchanged",
            "export_dpi" => 200,
        ); sorted=true)
    end
end

main_label_export()
