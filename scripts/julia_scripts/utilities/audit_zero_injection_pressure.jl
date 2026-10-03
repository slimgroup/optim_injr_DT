#!/usr/bin/env julia
# Prospective all-brine consistency test. Never modifies production inputs.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"
using JutulDarcyRules, JutulDarcy, Jutul, JLD2, SHA, LinearAlgebra, Dates

filehash(p) = open(io -> bytes2hex(sha256(io)), p)
function exclusive_jld(p; kwargs...)
    ispath(p) && error("Refusing to replace $p")
    # An interrupted write remains visible as a pending file and cannot masquerade
    # as a complete checkpoint. Never remove failed/pending diagnostic artifacts.
    pending=p*".pending_$(getpid())_$(time_ns())"
    jldsave(pending; kwargs...)
    mv(pending,p;force=false)
end

function run_member(member, root)
    n = (512, 1, 256); d = (6.25, 100.0, 6.25); nc = prod(n)
    target_days=parse(Int,get(ENV,"ZERO_PRESSURE_DAYS","960"))
    target_days in (8,80,480,960) || error("Unsupported bounded diagnostic window")
    solver_profile=get(ENV,"ZERO_PRESSURE_SOLVER_PROFILE","production")
    solver_profile in ("production","tighter_linear") || error("Unknown solver profile")
    blocks=cld(target_days,80)
    out = joinpath(root, "members", lpad(member, 3, '0'))
    mkpath(out)
    isfile(joinpath(out, "complete.txt")) && (println("Already complete: $member"); return)
    # Frozen member inputs were exported from BroadK before outcomes were inspected.
    inputpath=joinpath(root,"inputs","member_$(lpad(member,3,'0')).bin")
    indexrow=split(readlines(joinpath(root,"members.csv"))[member+1],',')
    @assert parse(Int,indexrow[1]) == member
    idx=parse(Int,indexrow[2])
    @assert filehash(inputpath) == indexrow[5]
    Kmd=reshape(copy(reinterpret(Float32,read(inputpath))),512,256)
    size(Kmd) == (512,256) || error("Input orientation mismatch")
    K = Kmd .* JutulDarcyRules.md
    model = jutulModel(n, d, 0.25, K1to3(K; kvoverkh=0.36); h=0.0)
    trans = exp.(log.(KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))))
    iz = 190 + argmax(K[250,191:200])
    schedule = collect(range(0.0, 0.0, length=12))
    @assert all(iszero, schedule)
    well = jutulVWell(0.0, [(250*d[1],d[2])]; startz=[iz*d[3]], endz=[(iz+6)*d[3]])
    @assert iszero(well.irate)
    initial = jutulSimpleState(model)
    p0 = reshape(copy(JutulDarcyRules.Pressure(initial)), n[1],n[3])
    @assert all(iszero, JutulDarcyRules.Saturations(initial))
    p0_formula = repeat(reshape((1:n[3]).*d[3].*JutulDarcyRules.ρH2O.*10.0,1,:),n[1],1)
    @assert p0 == p0_formula
    initpath = joinpath(out,"initial.jld2")
    if !isfile(initpath)
        exclusive_jld(initpath; p0_pa=p0, initial_co2_saturation=zeros(n[1],n[3]),
            porosity=reshape(model.ϕ,n[1],n[3]), schedule_m3_s=schedule,
            member=member, realization_id=idx, initial_formula_error_pa=maximum(abs.(p0.-p0_formula)))
    else
        @assert JLD2.load(initpath,"p0_pa") == p0
    end
    prev = JutulDarcyRules.get_Reservoir_state(initial)
    for block in 1:blocks
        steps=min(10,div(target_days-(block-1)*80,8))
        dest=joinpath(out,"block_$(lpad(block,2,'0')).jld2")
        if isfile(dest)
            # Avoid JLD2 0.4.55's nested report-Dict reconstruction issue.
            saved=jldopen(dest,"r") do f
                values=Dict(k=>f[k] for k in ("member","realization_id","complete_block","control_mode",
                    "actual_mass_rate_kg_s","co2_saturation_max","co2_saturation_min","time_days",
                    "pressure_pa","restart_reservoir"))
                values["solver_profile"]=haskey(f,"solver_profile") ? f["solver_profile"] : "production"
                values
            end
            @assert saved["solver_profile"] == solver_profile
            @assert saved["member"] == member && saved["realization_id"] == idx
            @assert saved["complete_block"] && saved["control_mode"] == "disabled_zero"
            @assert all(iszero,saved["actual_mass_rate_kg_s"])
            @assert all(iszero,saved["co2_saturation_max"]) && all(iszero,saved["co2_saturation_min"])
            @assert saved["time_days"] == Float64.((block-1)*80 .+ (1:steps).*8)
            @assert size(saved["pressure_pa"]) == (512,256,steps) && all(isfinite,saved["pressure_pa"])
            prev=saved["restart_reservoir"]
            println("Resume: member $member block $block already complete")
            continue
        end
        # Same 80-day call boundaries, eight-day outputs and default solver as production.
        # Use its lower-level operations to preserve nonlinear reports, discarded by Sblk.
        jm, pars, state0, native_forces = JutulDarcyRules.setup_well_model(model, well, fill(8.0*JutulDarcyRules.day,steps))
        ctrl=native_forces[:Facility].control[:Injector]
        @assert ctrl.target.value == 0.0
        # An active InjectorControl clamps mass rate above zero. Explicitly shut the well.
        forces=JutulDarcy.setup_reservoir_forces(jm; control=Dict(:Injector=>DisabledControl()))
        jm.models.Reservoir.data_domain[:porosity]=model.ϕ
        pars[:Reservoir][:Transmissibilities]=trans
        pars[:Reservoir][:FluidVolume] .= prod(d).*model.ϕ
        state0[:Reservoir]=prev
        sim, config=solver_profile=="production" ?
            JutulDarcy.setup_reservoir_simulator(jm,state0,pars) :
            JutulDarcy.setup_reservoir_simulator(jm,state0,pars;rtol=1e-6)
        cfgpath=joinpath(out,"configuration.txt")
        if !isfile(cfgpath)
            open(cfgpath,"w") do io
                println(io,"member=$member\nrealization_id=$idx\ncontrol_mode=disabled_zero\ntarget_days=$target_days\nsolver_profile=$solver_profile\njulia=$(VERSION)\nrepo_commit=$(readchomp(`git rev-parse HEAD`))")
                println(io,"script_sha256=$(filehash(@__FILE__))\ninput_sha256=$(filehash(inputpath))")
                for m in (Jutul,JutulDarcy,JutulDarcyRules)
                    println(io,"$(nameof(m)): version=$(pkgversion(m)); path=$(pathof(m))")
                end
                println(io,"native_control=$ctrl\nnative_target=$(ctrl.target.value)\nnative_initial_mass_rate_from_zero=$(JutulDarcy.valid_surface_rate_for_control(0.0,ctrl))\nnative_min_active_mass_rate=$(JutulDarcy.MIN_ACTIVE_WELL_RATE)")
                println(io,"forces=$forces\nnative_forces=$native_forces\nconfig=$config")
                println(io,"initial_gravity=10.0\nsolver_gravity=$(Jutul.gravity_constant)\npressure_variable=$(jm.models.Reservoir.primary_variables[:Pressure])")
                println(io,"densities=$(jm.models.Reservoir.secondary_variables[:PhaseMassDensities])\nwell=$(Jutul.physical_representation(jm.models.Injector.domain))")
                println(io,"comparison_tolerance_pa=0; solver balance residuals do not define a justified pressure-error bound")
            end
        end
        elapsed=@elapsed states,reports=Jutul.simulate!(sim,fill(8.0*JutulDarcyRules.day,steps);
            forces=forces,config=config,max_timestep_cuts=1000,info_level=0)
        if length(states)!=steps
            exclusive_jld(joinpath(out,"failed_block_$(block)_$(Dates.format(now(),"yyyymmddTHHMMSS")).jld2"); reports=reports, states=states)
            error("Incomplete block $block: $(length(states))/$steps outputs")
        end
        P=cat([reshape(s[:Reservoir][:Pressure],n[1],n[3]) for s in states]...;dims=3)
        all(isfinite,P) || error("Nonfinite pressure")
        rates=Float64[s[:Facility][:TotalSurfaceMassRate][1] for s in states]
        satmax=Float64[maximum(s[:Reservoir][:Saturations][1,:]) for s in states]
        satmin=Float64[minimum(s[:Reservoir][:Saturations][1,:]) for s in states]
        rho_min=Float64[minimum(s[:Reservoir][:PhaseMassDensities][2,:]) for s in states]
        rho_max=Float64[maximum(s[:Reservoir][:PhaseMassDensities][2,:]) for s in states]
        # Keep raw reports and end-of-block reservoir state for exact production-style restart.
        prev=states[end][:Reservoir]
        exclusive_jld(dest; member=member,realization_id=idx,complete_block=true,control_mode="disabled_zero",
            solver_profile=solver_profile,
            pressure_pa=P,time_days=Float64.((block-1)*80 .+ (1:steps).*8),
            actual_mass_rate_kg_s=rates,co2_saturation_max=satmax,co2_saturation_min=satmin,
            brine_density_min_kg_m3=rho_min,brine_density_max_kg_m3=rho_max,
            reports=reports,restart_reservoir=prev,elapsed_seconds=elapsed)
        @assert all(iszero,rates) "Disabled well has residual surface mass rate; retain output and flag failure"
        @assert all(iszero,satmax) && all(iszero,satmin) "Nonzero CO2 in all-brine baseline"
        println("Member $member realization $idx: block $block/$blocks complete; seconds=$elapsed; max overpressure Pa=$(maximum(P.-p0))")
        flush(stdout); GC.gc()
    end
    open(joinpath(out,"complete.txt"),"w") do io
        println(io,"Completed $(div(target_days,8)) eight-day outputs, $target_days days; all-brine disabled-well consistency test, not historical replication.")
    end
end

function main()
    length(ARGS)==2 || error("Usage: audit_zero_injection_pressure.jl MEMBER AUDIT_ROOT")
    member=parse(Int,ARGS[1]); 1<=member<=128 || error("Invalid member")
    root=abspath(ARGS[2]); BLAS.set_num_threads(1)
    out=joinpath(root,"members",lpad(member,3,'0')); mkpath(out)
    try
        run_member(member,root)
    catch e
        open(joinpath(out,"failure_$(Dates.format(now(),"yyyymmddTHHMMSS")).txt"),"w") do io
            showerror(io,e,catch_backtrace())
        end
        rethrow()
    end
end
main()
