#!/usr/bin/env julia
# Approved fixed-state/fixed-schedule experiment for slide p1-perm-movie.
# Only permeability varies. No optimization, BHP export, or threshold stopping.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"
using JutulDarcyRules, JLD2, SHA, Random, LinearAlgebra, Printf, Dates
import JutulDarcy, Jutul

const POSITIONS = [1,5,9,13,17,21,26,30,34,38,42,46,50,54,58,62,
                   67,71,75,79,83,87,91,95,99,103,108,112,116,120,124,128]
const RATES = [0.00010,0.00914,0.01818,0.02722,0.03626,0.04530]
const EXPECTED_P0 = "8e8b73991720afddc6c93f12f3cf95be35085d4275972b36917b0a4d26cb6ea7"
const EXPECTED_S0 = "693eedb0364b5dc535271a51d23118253615144bc41fa8bd0fcfb88131e1a8a4"
const EXPECTED_PHI = "7e1a48200e2c665bb3ecdf0b3bee7d982af79a751161a9a5986557cf2efc3ac9"
const EXPECTED_PMAX = "49f25b842c9694f74a1b4111075bccc7e8629b75347277f4abb7d003efed0661"
hash_array(a) = bytes2hex(sha256(reinterpret(UInt8, vec(a))))

function save_new(path; kwargs...)
    ispath(path) && error("Refusing to replace $path")
    pending = path * ".pending"
    ispath(pending) && error("Refusing to replace $pending")
    jldsave(pending; kwargs...)
    mv(pending, path; force=false)
end

function main()
    haskey(ENV, "SLURM_JOB_ID") || error("Run forwards on Slurm, not a login node")
    BLAS.set_num_threads(1)
    length(ARGS) == 2 || error("Usage: MEMBER RUN_DIRECTORY")
    member = parse(Int, ARGS[1]); member in POSITIONS || error("Member outside approved subset")
    root = abspath(ARGS[2]); isfile(joinpath(root,"approval.json")) || error("Missing approval record")
    out = joinpath(root, "members", @sprintf("%03d", member))
    mkpath(dirname(out)); mkdir(out) # Exclusive: no overwriting prior attempts.
    started = time()
    try
        n=(512,1,256); d=(6.25,100.0,6.25); nc=prod(n)
        index_path=datadir("state/new/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2")
        idx=Int(JLD2.load(index_path,"idx_t1")[member])
        row=split(readlines(joinpath(root,"permeability_cache_members.csv"))[member+1], ',')
        @assert parse(Int,row[1])==member && parse(Int,row[2])==idx
        println("member=$member realization_id=$idx; loading authoritative BroadK"); flush(stdout)
        perm_path=datadir("geo/wise_perm_models_2000_new.jld2")
        Kmd=jldopen(perm_path,"r") do f
            f["BroadK"][idx,:,:]
        end
        @assert size(Kmd)==(512,256) && eltype(Kmd)==Float32
        @assert all(isfinite,Kmd) && all(Kmd .> 0)
        perm_hash=hash_array(Kmd)
        @assert perm_hash==strip(row[5]) "Authoritative permeability differs from audited cache"
        GC.gc()
        K=Kmd .* JutulDarcyRules.md
        model=jutulModel(n,d,0.25,K1to3(K; kvoverkh=0.36); h=0.0)
        logtrans=log.(KtoTrans(CartesianMesh(model),K1to3(K;kvoverkh=0.36)))
        initial=jutulSimpleState(model)
        Random.seed!(2025)
        value=0.2+rand(Float64)*0.6
        s0=zeros(Float64,512,256)
        iz=191 # Frozen first member's completion; do not optimize location per K.
        for (rows,offset) in [(249:251,-4),(248:252,-3),(247:253,-2),
                              (246:254,-1),(246:254,0),(246:254,1),
                              (247:253,2),(248:252,3),(249:251,4)]
            s0[rows,iz+offset].=value
        end
        initial[1:nc]=vec(s0)
        p0=reshape(copy(JutulDarcyRules.Pressure(initial)),512,256)
        pmax=p0 .+ 4e6
        phi=reshape(copy(model.ϕ),512,256)
        @assert hash_array(p0)==EXPECTED_P0
        @assert hash_array(reshape(JutulDarcyRules.Saturations(initial),512,256))==EXPECTED_S0
        @assert hash_array(phi)==EXPECTED_PHI && hash_array(pmax)==EXPECTED_PMAX
        @assert RATES == JLD2.load(plotsdir("paper_figures/forward_sim_four_steps_base_data.jld2"),"POF_eps0p01_rates")[1:6]
        @assert all(initial.state[:Saturations][2,:] .== 1 .- vec(s0))
        save_new(joinpath(out,"inputs.jld2"); member,realization_id=idx,
                 permeability_md=Kmd,initial_pressure_pa=p0,initial_co2_saturation=s0,
                 porosity=phi,p_max_pa=pmax,rates_m3_s=RATES,period_days=80.0,
                 well_start_xyz_m=[1562.5,100.0,1193.75],well_end_z_m=1231.25,
                 grid=collect(n),cell_size_m=collect(d),initial_pressure_sha256=EXPECTED_P0,
                 initial_saturation_sha256=EXPECTED_S0,porosity_sha256=EXPECTED_PHI,
                 pressure_limit_sha256=EXPECTED_PMAX,permeability_sha256=perm_hash,
                 rate_sha256=hash_array(RATES),permeability_source=perm_path,
                 permeability_dataset="BroadK",indices_source=index_path,
                 state_source="fixed reconstructed step1 member1, seed 2025",initial_seed=2025,
                 mD_to_m2=JutulDarcyRules.md,vertical_horizontal_ratio=0.36)
        open(joinpath(out,"runtime.txt"),"w") do io
            println(io,"member=$member\nrealization_id=$idx\nstart_utc=$(now(UTC))")
            println(io,"slurm_job_id=$(ENV["SLURM_JOB_ID"])\nslurm_array_job_id=$(get(ENV,"SLURM_ARRAY_JOB_ID",""))")
            println(io,"julia_version=$VERSION\nblas_threads=$(BLAS.get_num_threads())\nsource_sha256=$(bytes2hex(sha256(read(@__FILE__))))")
            for mod in (Jutul,JutulDarcy,JutulDarcyRules)
                println(io,"$(nameof(mod))=$(pkgversion(mod)); source=$(pathof(mod))")
            end
        end
        previous=initial
        simulator=jutulModeling(model,fill(8.0,10))
        for (period,rate) in enumerate(RATES)
            println("Starting period $period/6, rate=$rate, day=$((period-1)*80)"); flush(stdout)
            well=jutulVWell(rate,[(1562.5,100.0)];startz=[1193.75],endz=[1231.25])
            states=simulator(logtrans,well;state0=previous)
            @assert length(states.states)==10 "Incomplete 80-day simulator output"
            previous=states.states[end]
            p=reshape(copy(JutulDarcyRules.Pressure(previous)),512,256)
            s=reshape(copy(JutulDarcyRules.Saturations(previous)),512,256)
            @assert all(isfinite,p) && all(isfinite,s)
            @assert minimum(s)>=-1e-8 && maximum(s)<=1+1e-8
            save_new(joinpath(out,@sprintf("period_%02d.jld2",period));
                     member,realization_id=idx,time_days=80.0*period,
                     pressure_pa=p,co2_saturation=s,rate_m3_s=rate,
                     pressure_limit_exceedance_cells=count(p .> pmax))
            println("Completed day $(80*period); dp_MPa=$(extrema((p.-p0)./1e6)); saturation=$(extrema(s)); elapsed=$(time()-started)"); flush(stdout)
            GC.gc()
        end
        p=reshape(copy(JutulDarcyRules.Pressure(previous)),512,256)
        s=reshape(copy(JutulDarcyRules.Saturations(previous)),512,256)
        save_new(joinpath(out,"day480.jld2"); member,realization_id=idx,
                 time_days=480.0,pressure_pa=p,co2_saturation=s,
                 pressure_difference_pa=p.-p0,pressure_limit_exceedance_mask=UInt8.(p.>pmax),
                 initial_pressure_sha256=EXPECTED_P0,initial_saturation_sha256=EXPECTED_S0,
                 porosity_sha256=EXPECTED_PHI,pressure_limit_sha256=EXPECTED_PMAX,
                 permeability_sha256=perm_hash,rate_sha256=hash_array(RATES),
                 pressure_sha256=hash_array(p),saturation_sha256=hash_array(s),
                 slurm_job_id=ENV["SLURM_JOB_ID"],slurm_array_job_id=get(ENV,"SLURM_ARRAY_JOB_ID",""),
                 source_sha256=bytes2hex(sha256(read(@__FILE__))),elapsed_seconds=time()-started,
                 complete=true)
        write(joinpath(out,"COMPLETE.txt"),"Day 480 complete; fixed state, well and schedule; permeability varies.\n")
    catch e
        open(joinpath(out,"FAILED.txt"),"w") do io
            showerror(io,e,catch_backtrace()); println(io)
        end
        rethrow()
    end
end
main()
