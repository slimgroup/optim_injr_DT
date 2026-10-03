#!/usr/bin/env julia
# Reference response for the controlled permeability ensemble: geological ID 2000.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"
using JutulDarcyRules, JLD2, SHA, LinearAlgebra, Printf, Dates, TOML
import JutulDarcy, Jutul

hash_array(a) = bytes2hex(sha256(reinterpret(UInt8, vec(a))))
file_hash(p) = bytes2hex(open(sha256, p))
function save_new(path; kwargs...)
    ispath(path) && error("Refusing to replace $path")
    pending = path * ".pending"
    ispath(pending) && error("Refusing to replace $pending")
    jldsave(pending; kwargs...)
    mv(pending, path; force=false)
end

function main()
    haskey(ENV, "SLURM_JOB_ID") || error("Forward runs require Slurm")
    length(ARGS) == 2 || error("Usage: ENSEMBLE_RUN NEW_REFERENCE_DIRECTORY")
    BLAS.set_num_threads(1)
    ensemble, out = abspath.(ARGS)
    cfg = TOML.parsefile(joinpath(ensemble, "protocol.toml"))
    @assert cfg["comparison_day"] == 1920 && cfg["period_days"] == 80
    @assert pkgversion(Jutul) == v"0.2.11"
    @assert pkgversion(JutulDarcy) == v"0.2.7" && pkgversion(JutulDarcyRules) == v"0.2.8"
    common_path = joinpath(ensemble, "members", "001", "inputs.jld2")
    common = JLD2.load(common_path)
    rates = common["rates_m3_s"]
    @assert length(rates) == 24 && rates == cfg["rates_m3_s"]
    @assert hash_array(rates) == cfg["schedule_sha256_f64"]
    @assert rates == JLD2.load(plotsdir("paper_figures/forward_sim_four_steps_base_data.jld2"), "POF_eps0p01_rates")
    mkpath(dirname(out)); mkdir(out)
    started = time()
    try
        n = (512, 1, 256); d = (6.25, 100.0, 6.25); nc = prod(n)
        realization_id = 2000
        perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
        Kmd = jldopen(perm_path, "r") do f
            f["BroadK"][realization_id, :, :]
        end
        @assert size(Kmd) == (512, 256) && eltype(Kmd) == Float32
        @assert all(isfinite, Kmd) && all(Kmd .> 0)
        GC.gc()
        K = Kmd .* JutulDarcyRules.md
        model = jutulModel(n, d, 0.25, K1to3(K; kvoverkh=0.36); h=0.0)
        logtrans = log.(KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36)))
        p0, s0 = common["initial_pressure_pa"], common["initial_co2_saturation"]
        @assert size(p0) == size(s0) == (512, 256)
        initial = jutulSimpleState(model)
        @assert reshape(JutulDarcyRules.Pressure(initial), 512, 256) == p0
        initial[1:nc] = vec(s0)
        initial[nc+1:2nc] = vec(p0)
        @assert JutulDarcyRules.Pressure(initial) == vec(p0)
        @assert JutulDarcyRules.Saturations(initial) == vec(s0)
        @assert initial.state[:Saturations][2, :] == 1 .- vec(s0)
        phi = reshape(copy(model.ϕ), 512, 256); pmax = p0 .+ 4e6
        for (a, key) in [(p0, "initial_pressure_sha256_f64"),
                         (s0, "initial_saturation_sha256_f64"),
                         (phi, "porosity_sha256_f64"), (pmax, "p_max_sha256_f64")]
            @assert hash_array(a) == cfg[key]
        end
        @assert phi == common["porosity"] && pmax == common["p_max_pa"]
        @assert common["grid"] == collect(n) && common["cell_size_m"] == collect(d)
        @assert common["well_start_xyz_m"] == [1562.5, 100.0, 1193.75]
        @assert common["well_end_z_m"] == 1231.25
        perm_hash = hash_array(Kmd)
        save_new(joinpath(out, "inputs.jld2"); realization_id,
                 permeability_md=Kmd, initial_pressure_pa=p0, initial_co2_saturation=s0,
                 porosity=phi, p_max_pa=pmax, rates_m3_s=rates, period_days=80.0,
                 well_start_xyz_m=common["well_start_xyz_m"], well_end_z_m=common["well_end_z_m"],
                 grid=collect(n), cell_size_m=collect(d), permeability_sha256=perm_hash,
                 initial_pressure_sha256=hash_array(p0), initial_saturation_sha256=hash_array(s0),
                 porosity_sha256=hash_array(phi), pressure_limit_sha256=hash_array(pmax),
                 rate_sha256=hash_array(rates), permeability_source=perm_path,
                 permeability_dataset="BroadK", common_input_source=common_path,
                 common_input_sha256=file_hash(common_path), ensemble_run=ensemble,
                 mD_to_m2=JutulDarcyRules.md, vertical_horizontal_ratio=0.36)
        open(joinpath(out, "runtime.txt"), "w") do io
            println(io, "realization_id=2000\nstart_utc=$(now(UTC))\nslurm_job_id=$(ENV["SLURM_JOB_ID"])")
            println(io, "source_sha256=$(file_hash(@__FILE__))\njulia_version=$VERSION")
            for mod in (Jutul, JutulDarcy, JutulDarcyRules)
                println(io, "$(nameof(mod))=$(pkgversion(mod)); source=$(pathof(mod))")
            end
        end
        previous = initial
        simulator = jutulModeling(model, fill(8.0, 10))
        for (period, rate) in enumerate(rates)
            println("Starting period $period/24, rate=$rate, day=$((period-1)*80)"); flush(stdout)
            well = jutulVWell(rate, [(1562.5, 100.0)]; startz=[1193.75], endz=[1231.25])
            states = simulator(logtrans, well; state0=previous)
            @assert length(states.states) == 10 "Incomplete 80-day output"
            previous = states.states[end]
            p = reshape(copy(JutulDarcyRules.Pressure(previous)), 512, 256)
            s = reshape(copy(JutulDarcyRules.Saturations(previous)), 512, 256)
            @assert all(isfinite, p) && all(isfinite, s)
            @assert minimum(s) >= -1e-8 && maximum(s) <= 1+1e-8
            save_new(joinpath(out, @sprintf("period_%02d.jld2", period)); realization_id,
                     time_days=80.0*period, pressure_pa=p, co2_saturation=s, rate_m3_s=rate)
            println("Completed day $(80*period); dp_MPa=$(extrema((p.-p0)./1e6)); elapsed=$(time()-started)")
            flush(stdout); GC.gc()
        end
        p = reshape(copy(JutulDarcyRules.Pressure(previous)), 512, 256)
        s = reshape(copy(JutulDarcyRules.Saturations(previous)), 512, 256)
        save_new(joinpath(out, "day1920.jld2"); realization_id, time_days=1920.0,
                 pressure_pa=p, co2_saturation=s, pressure_difference_pa=p.-p0,
                 pressure_limit_exceedance_mask=UInt8.(p.>pmax),
                 initial_pressure_sha256=hash_array(p0), initial_saturation_sha256=hash_array(s0),
                 porosity_sha256=hash_array(phi), pressure_limit_sha256=hash_array(pmax),
                 permeability_sha256=perm_hash, rate_sha256=hash_array(rates),
                 pressure_sha256=hash_array(p), saturation_sha256=hash_array(s),
                 slurm_job_id=ENV["SLURM_JOB_ID"], source_sha256=file_hash(@__FILE__),
                 elapsed_seconds=time()-started, complete=true)
        write(joinpath(out, "COMPLETE.txt"), "Day 1920, geological ID 2000; common ensemble initial state, wells and schedule.\n")
    catch e
        open(joinpath(out, "FAILED.txt"), "w") do io
            showerror(io, e, catch_backtrace()); println(io)
        end
        rethrow()
    end
end
main()
