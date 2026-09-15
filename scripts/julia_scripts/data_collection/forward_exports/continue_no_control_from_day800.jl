#!/usr/bin/env julia
# Continue the saved no-control ramp at its planned rate through day 1920.
# The historical export contains days 8:8:800 even though its presentation
# threshold was first reached on day 728. Restart at the original 80-day call
# boundary, keep its first 100 states unchanged, and retain 80-day call boundaries.
# This is a new counterfactual continuation, not a recovered historical campaign.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"
using JutulDarcyRules, JutulDarcy, Jutul, JLD2, SHA, LinearAlgebra

const N_GRID = (512, 1, 256)
const D_CELL = (6.25, 100.0, 6.25)
const DT = 8.0
const DS = 10
const GT_IDX = 2000

file_sha(path) = bytes2hex(open(sha256, path))

function main()
    length(ARGS) == 1 || error("Usage: continue_no_control_from_day800.jl NEW_OUTDIR")
    out = abspath(ARGS[1])
    ispath(out) && error("Refusing to overwrite existing output: $out")
    mkpath(out)
    BLAS.set_num_threads(1)
    source_path = plotsdir("paper_figures", "no_control_delayed_ramp_10_periods.jld2")
    source_sha = file_sha(source_path)
    source = JLD2.load(source_path)
    rates = source["full_rates"]
    @assert length(rates) == 24 && all(rates[10:end] .== 0.2)
    @assert source["simulated_rates"] == rates[1:10]
    @assert source["dt_days"] == DT && source["ground_truth_idx"] == GT_IDX
    @assert source["severe_day"] == 728.0
    @assert size(source["pres_all"]) == size(source["sat_all"]) == (512, 256, 100)
    @assert all(isfinite, source["pres_all"]) && all(isfinite, source["sat_all"])
    p0 = source["p0"]
    pmax = source["p_max"]
    @assert pmax == p0' .+ 4e6

    truth_path = datadir("geo/wise_perm_models_2000_new.jld2")
    Kmd = jldopen(truth_path, "r") do f
        f["BroadK"][GT_IDX, :, :]
    end
    truth_sha = bytes2hex(sha256(reinterpret(UInt8, vec(Kmd))))
    K = Kmd .* JutulDarcyRules.md
    model = jutulModel(N_GRID, D_CELL, 0.25, K1to3(K; kvoverkh=0.36); h=0.0)
    log_trans = log.(KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36)))
    Sblk = jutulModeling(model, fill(DT, DS))
    inj_z = 190 + argmax(K[250, 191:200])
    loc = (250*D_CELL[1], D_CELL[2], inj_z*D_CELL[3])
    nc = prod(N_GRID)
    prev = jutulSimpleState(model)
    prev[1:nc] = vec(source["sat_all"][:, :, end])
    prev[nc+1:end] = vec(source["pres_all"][:, :, end])
    @assert prev[1:nc] == vec(source["sat_all"][:, :, end])
    @assert prev[nc+1:end] == vec(source["pres_all"][:, :, end])

    sat_all = Array{Float64}(undef, 512, 256, 240)
    pres_all = similar(sat_all)
    sat_all[:, :, 1:100] = source["sat_all"]
    pres_all[:, :, 1:100] = source["pres_all"]
    counts = zeros(Int, 240)
    min_margin = zeros(240)
    max_excess = zeros(240)
    actual_rates = fill(NaN, 240) # Historical well-state outputs were not exported.
    repo_commit = readchomp(`git rev-parse HEAD`)
    open(joinpath(out, "provenance.txt"), "w") do io
        println(io, "scenario=continued injection counterfactual\nrestart_day=800\nhistorical_threshold_day=728\nend_day=1920\nrate_after_restart_m3_s=0.2\ncall_length_days=80\noutput_interval_days=8")
        println(io, "source=$source_path\nsource_sha256=$source_sha\nground_truth=$truth_path\ntruth_index=$GT_IDX\nKmd_sha256_julia_column_major=$truth_sha\nrepo_commit=$repo_commit\nscript_sha256=$(file_sha(@__FILE__))\nmanifest_sha256=$(file_sha(projectdir("Manifest.toml")))\njulia=$VERSION\nslurm_job_id=$(get(ENV,"SLURM_JOB_ID","none"))")
        println(io, "grid=$N_GRID\ncell_m=$D_CELL\nporosity=0.25 with original default boundary padding\nkv_over_kh=0.36\nwell_location_m=$loc\npmax=historical p0 + 4e6 Pa\npressure=absolute Pa\nCO2_density_for_schedule_mass=700 kg/m3")
        for m in (Jutul, JutulDarcy, JutulDarcyRules)
            println(io, "$(nameof(m)): version=$(pkgversion(m)); source=$(pathof(m))")
        end
        println(io, "Interpretation=pressure-limit exceedance only; no fracture or leakage mechanics. No severity-triggered shutdown in continuation. No posterior-state updates.")
    end

    function record(io, k)
        p = @view pres_all[:, :, k]
        s = @view sat_all[:, :, k]
        @assert all(isfinite, p) && all(isfinite, s)
        @assert minimum(s) >= -1e-8 && maximum(s) <= 1+1e-8
        r = (pmax .- p) ./ pmax
        counts[k] = count(<(0), r)
        min_margin[k] = minimum(r)
        max_excess[k] = max(0.0, maximum(p .- pmax)/1e6)
        q = rates[cld(k, DS)]
        mass = sum(rates[i]*clamp(k*DT-(i-1)*80, 0, 80) for i in eachindex(rates))*86400*700/1e9
        println(io, join((k*DT, cld(k,60), q, actual_rates[k], mass, counts[k], min_margin[k], max_excess[k], maximum((p.-p0')./1e6), minimum(s), maximum(s), k<=100 ? "historical" : "continuation"), ','))
    end
    open(joinpath(out, "diagnostics.csv"), "w") do io
        println(io, "day,monitoring_step,rate_target_m3_s,rate_actual_m3_s,mass_Mt,exceeding_cells,min_r,max_pressure_excess_MPa,max_pressure_increase_MPa,saturation_min,saturation_max,source")
        for k in 1:100
            record(io, k)
        end
        @assert counts[91] == 6953
        flush(io)
        for period in 11:24
            q = rates[period]
            well = jutulVWell(q, [(loc[1], loc[2])]; startz=[loc[3]], endz=[loc[3]+6*D_CELL[3]])
            println("Starting period $period: days $((period-1)*80)–$(period*80), q=$q"); flush(stdout)
            states = Sblk(log_trans, well; state0=prev)
            @assert length(states.states) == DS
            prev = states.states[end]
            for j in 1:DS
                k = (period-1)*DS+j
                sat_all[:, :, k] = reshape(states.states[j][1:nc], 512, 256)
                pres_all[:, :, k] = reshape(states.states[j][nc+1:end], 512, 256)
            end
            # Read the achieved well rates from the simulator's own returned states.
            jm, _, _, forces = JutulDarcyRules.setup_well_model(model, well, fill(DT*JutulDarcyRules.day, DS))
            raw_states = [s.state for s in states.states]
            achieved = JutulDarcy.well_output(jm, raw_states, :Injector, forces, JutulDarcy.TotalRateTarget)
            @assert length(achieved) == DS && all(isfinite, achieved)
            actual_rates[(period-1)*DS+1:period*DS] = achieved
            for k in (period-1)*DS+1:period*DS
                record(io, k)
            end
            flush(io)
            # Keep each completed period even if a later solver call fails.
            JLD2.save(joinpath(out, "period_$(period)_day$(period*80).jld2"),
                      "time_days", collect(((period-1)*DS+1:period*DS).*DT),
                      "pres_all", pres_all[:, :, (period-1)*DS+1:period*DS],
                      "sat_all", sat_all[:, :, (period-1)*DS+1:period*DS],
                      "rate_m3_s", q, "rate_actual_m3_s", achieved)
            println("Completed day $(period*80): cells=$(counts[period*DS]), min_r=$(min_margin[period*DS]), max_excess_MPa=$(max_excess[period*DS])"); flush(stdout)
            GC.gc()
        end
    end
    @assert pres_all[:, :, 1:100] == source["pres_all"]
    @assert sat_all[:, :, 1:100] == source["sat_all"]
    @assert file_sha(source_path) == source_sha
    JLD2.save(joinpath(out, "no_control_continued.jld2"),
              "pres_all", pres_all, "sat_all", sat_all, "p0", p0, "p_max", pmax,
              "full_rates", rates, "simulated_rates", rates,
              "time_days", collect(DT:DT:1920.0), "dt_days", DT,
              "ground_truth_idx", GT_IDX, "ground_truth_sha256", truth_sha,
              "continued_injection", true, "restart_day", 800.0, "final_day", 1920.0,
              "historical_threshold_day", 728.0, "severe_day", source["severe_day"],
              "ramp_periods", source["ramp_periods"],
              "min_margin_by_substep", min_margin, "exceeding_cells_by_substep", counts,
              "max_pressure_excess_MPa_by_substep", max_excess,
              "rate_actual_by_substep", actual_rates,
              "source_file", source_path, "source_sha256", source_sha,
              "repo_commit", repo_commit, "slurm_job_id", get(ENV,"SLURM_JOB_ID","none"))
    open(joinpath(out, "complete.txt"), "w") do io
        println(io, "Completed all 240 saved times; first 100 pressure/saturation states equal historical source exactly.")
        println(io, "Peak exceeding cells=$(maximum(counts)) at day $(argmax(counts)*DT).")
        println(io, "Maximum pressure excess=$(maximum(max_excess)) MPa at day $(argmax(max_excess)*DT).")
        println(io, "Achieved continuation injection magnitude error=$(maximum(abs.(abs.(actual_rates[101:end]).-0.2))) m3/s.")
    end
    println("Saved continuation to $out")
end

main()
