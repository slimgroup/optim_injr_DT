#!/usr/bin/env julia
# Fixed-state, fixed-control permeability comparison approved for 64 members.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"
using JutulDarcyRules, JLD2, SHA, Random, LinearAlgebra, Printf, Dates, TOML
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
function restore_state(model, p, s)
    @assert size(p) == size(s) == (512,256)
    state = jutulSimpleState(model)
    nc = 512*256
    state[1:nc] = vec(s)
    state[nc+1:2nc] = vec(p)
    @assert JutulDarcyRules.Pressure(state) == vec(p)
    @assert JutulDarcyRules.Saturations(state) == vec(s)
    @assert state.state[:Saturations][2,:] == 1 .- vec(s)
    return state
end
fields(state) = (reshape(copy(JutulDarcyRules.Pressure(state)),512,256),
                 reshape(copy(JutulDarcyRules.Saturations(state)),512,256))
well_at_rate(q) = jutulVWell(q, [(1562.5,100.0)]; startz=[1193.75], endz=[1231.25])

function main()
    haskey(ENV,"SLURM_JOB_ID") || error("Forward runs require Slurm")
    length(ARGS)==2 || error("Usage: MEMBER NEW_RUN_DIRECTORY")
    BLAS.set_num_threads(1)
    member=parse(Int,ARGS[1]); root=abspath(ARGS[2])
    cfg=TOML.parsefile(joinpath(root,"protocol.toml"))
    @assert cfg["approved"] && member in cfg["subset_positions"]
    @assert cfg["comparison_day"]==1920 && cfg["period_days"]==80
    rates=Float64.(cfg["rates_m3_s"])
    @assert length(rates)==24 && hash_array(rates)==cfg["schedule_sha256_f64"]
    @assert rates==JLD2.load(plotsdir("paper_figures/forward_sim_four_steps_base_data.jld2"),"POF_eps0p01_rates")
    @assert pkgversion(Jutul)==v"0.2.11" && pkgversion(JutulDarcy)==v"0.2.7" && pkgversion(JutulDarcyRules)==v"0.2.8"
    out=joinpath(root,"members",@sprintf("%03d",member))
    mkpath(dirname(out)); mkdir(out)
    started=time()
    try
        n=(512,1,256); d=(6.25,100.0,6.25); nc=prod(n)
        index_path=datadir("state/new/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2")
        idx=Int(JLD2.load(index_path,"idx_t1")[member])
        row=split(readlines(joinpath(root,"permeability_cache_members.csv"))[member+1], ',')
        @assert parse(Int,row[1])==member && parse(Int,row[2])==idx
        perm_path=datadir("geo/wise_perm_models_2000_new.jld2")
        Kmd=jldopen(perm_path,"r") do f
            f["BroadK"][idx,:,:]
        end
        @assert size(Kmd)==(512,256) && eltype(Kmd)==Float32 && all(Kmd .> 0) && all(isfinite,Kmd)
        perm_hash=hash_array(Kmd); @assert perm_hash==strip(row[5])
        GC.gc()
        K=Kmd .* JutulDarcyRules.md
        model=jutulModel(n,d,0.25,K1to3(K;kvoverkh=0.36);h=0.0)
        logtrans=log.(KtoTrans(CartesianMesh(model),K1to3(K;kvoverkh=0.36)))
        initial=jutulSimpleState(model)
        Random.seed!(2025); value=0.2+rand(Float64)*0.6
        s0=zeros(Float64,512,256)
        for (rows,offset) in [(249:251,-4),(248:252,-3),(247:253,-2),
                              (246:254,-1),(246:254,0),(246:254,1),
                              (247:253,2),(248:252,3),(249:251,4)]
            s0[rows,191+offset].=value
        end
        initial[1:nc]=vec(s0)
        p0=reshape(copy(JutulDarcyRules.Pressure(initial)),512,256)
        phi=reshape(copy(model.ϕ),512,256); pmax=p0.+4e6
        @assert hash_array(p0)==cfg["initial_pressure_sha256_f64"]
        @assert hash_array(s0)==cfg["initial_saturation_sha256_f64"]
        @assert hash_array(phi)==cfg["porosity_sha256_f64"]
        @assert hash_array(pmax)==cfg["p_max_sha256_f64"]
        previous=initial; start_period=1; restart_source=""; restart_sha=""
        simulator=jutulModeling(model,fill(8.0,10))
        if member in cfg["resume_from_day480_positions"]
            old=joinpath(cfg["existing_day480_run"],"members",@sprintf("%03d",member))
            hist=TOML.parsefile(joinpath(root,"restart_sources.toml"))[@sprintf("%03d",member)]
            restart_source=joinpath(old,"day480.jld2"); restart_sha=file_hash(restart_source)
            @assert restart_sha==hist["day480_sha256"]
            @assert file_hash(joinpath(old,"inputs.jld2"))==hist["inputs_sha256"]
            inp=JLD2.load(joinpath(old,"inputs.jld2")); saved=JLD2.load(restart_source)
            @assert inp["initial_pressure_pa"]==p0 && inp["initial_co2_saturation"]==s0
            @assert inp["permeability_md"]==Kmd && inp["porosity"]==phi && inp["p_max_pa"]==pmax
            @assert inp["rates_m3_s"]==rates[1:6] && inp["grid"]==collect(n) && inp["cell_size_m"]==collect(d)
            @assert inp["well_start_xyz_m"]==[1562.5,100.0,1193.75] && inp["well_end_z_m"]==1231.25
            @assert saved["complete"] && saved["time_days"]==480 && saved["realization_id"]==idx
            @assert saved["pressure_sha256"]==hash_array(saved["pressure_pa"])
            @assert saved["saturation_sha256"]==hash_array(saved["co2_saturation"])
            if member==1
                checkpoint=joinpath(old,"period_05.jld2")
                @assert file_hash(checkpoint)==hist["day400_sha256"]
                snap=JLD2.load(checkpoint)
                @assert snap["time_days"]==400 && snap["realization_id"]==idx
                replay=simulator(logtrans,well_at_rate(rates[6]);
                                 state0=restore_state(model,snap["pressure_pa"],snap["co2_saturation"]))
                @assert length(replay.states)==10
                rp,rs=fields(replay.states[end])
                pe=maximum(abs.(rp.-saved["pressure_pa"])); se=maximum(abs.(rs.-saved["co2_saturation"]))
                passed=pe<=0.1 && se<=1e-7
                save_new(joinpath(out,"restart_validation.jld2");
                    passed,max_pressure_error_pa=pe,max_saturation_error=se,
                    pressure_tolerance_pa=0.1,saturation_tolerance=1e-7,
                    checkpoint_source=checkpoint,reference_source=restart_source,
                    replay_pressure_pa=rp,replay_co2_saturation=rs)
                @assert passed "Restart replay differs from historical period6"
                println("Restart validation PASSED: max pressure error=$pe Pa; max saturation error=$se");flush(stdout)
            end
            previous=restore_state(model,saved["pressure_pa"],saved["co2_saturation"])
            start_period=7
        end
        save_new(joinpath(out,"inputs.jld2"); member,realization_id=idx,
                 permeability_md=Kmd,initial_pressure_pa=p0,initial_co2_saturation=s0,
                 porosity=phi,p_max_pa=pmax,rates_m3_s=rates,period_days=80.0,
                 well_start_xyz_m=[1562.5,100.0,1193.75],well_end_z_m=1231.25,
                 grid=collect(n),cell_size_m=collect(d),initial_pressure_sha256=hash_array(p0),
                 initial_saturation_sha256=hash_array(s0),porosity_sha256=hash_array(phi),
                 pressure_limit_sha256=hash_array(pmax),permeability_sha256=perm_hash,
                 rate_sha256=hash_array(rates),permeability_source=perm_path,
                 permeability_dataset="BroadK",indices_source=index_path,
                 state_source="fixed reconstructed step1 member1, seed 2025",initial_seed=2025,
                 mD_to_m2=JutulDarcyRules.md,vertical_horizontal_ratio=0.36,
                 start_day=(start_period-1)*80,restart_source,restart_sha256=restart_sha)
        open(joinpath(out,"runtime.txt"),"w") do io
            println(io,"member=$member\nrealization_id=$idx\nstart_day=$((start_period-1)*80)\nstart_utc=$(now(UTC))")
            println(io,"slurm_job_id=$(ENV["SLURM_JOB_ID"])\nsource_sha256=$(file_hash(@__FILE__))\njulia_version=$VERSION")
            for mod in (Jutul,JutulDarcy,JutulDarcyRules)
                println(io,"$(nameof(mod))=$(pkgversion(mod)); source=$(pathof(mod))")
            end
        end
        for period in start_period:24
            rate=rates[period]
            println("Starting period $period/24, rate=$rate, day=$((period-1)*80)");flush(stdout)
            states=simulator(logtrans,well_at_rate(rate);state0=previous)
            @assert length(states.states)==10 "Incomplete 80-day output"
            previous=states.states[end]; p,s=fields(previous)
            @assert all(isfinite,p) && all(isfinite,s) && minimum(s)>=-1e-8 && maximum(s)<=1+1e-8
            save_new(joinpath(out,@sprintf("period_%02d.jld2",period));
                     member,realization_id=idx,time_days=80.0*period,pressure_pa=p,
                     co2_saturation=s,rate_m3_s=rate,pressure_limit_exceedance_cells=count(p.>pmax))
            println("Completed day $(80*period); dp_MPa=$(extrema((p.-p0)./1e6)); saturation=$(extrema(s)); elapsed=$(time()-started)");flush(stdout)
            GC.gc()
        end
        p,s=fields(previous)
        save_new(joinpath(out,"day1920.jld2");member,realization_id=idx,time_days=1920.0,
                 pressure_pa=p,co2_saturation=s,pressure_difference_pa=p.-p0,
                 pressure_limit_exceedance_mask=UInt8.(p.>pmax),
                 initial_pressure_sha256=hash_array(p0),initial_saturation_sha256=hash_array(s0),
                 porosity_sha256=hash_array(phi),pressure_limit_sha256=hash_array(pmax),
                 permeability_sha256=perm_hash,rate_sha256=hash_array(rates),
                 pressure_sha256=hash_array(p),saturation_sha256=hash_array(s),
                 slurm_job_id=ENV["SLURM_JOB_ID"],slurm_array_job_id=get(ENV,"SLURM_ARRAY_JOB_ID",""),
                 source_sha256=file_hash(@__FILE__),elapsed_seconds=time()-started,
                 start_day=(start_period-1)*80,restart_source,restart_sha256=restart_sha,complete=true)
        isempty(restart_source) || @assert file_hash(restart_source)==restart_sha
        write(joinpath(out,"COMPLETE.txt"),"Day1920 complete; fixed state and full selected PoF schedule; only K varies.\n")
    catch e
        open(joinpath(out,"FAILED.txt"),"w") do io
            showerror(io,e,catch_backtrace());println(io)
        end
        rethrow()
    end
end
main()
