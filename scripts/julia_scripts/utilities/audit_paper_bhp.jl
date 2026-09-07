#!/usr/bin/env julia
# Read-only replay of saved paper schedules. New diagnostics only; never reoptimize.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"
using JutulDarcyRules, JutulDarcy, Jutul, JLD2, SHA, LinearAlgebra

function main()
    BLAS.set_num_threads(1)
    case = ARGS[1]
    out = ARGS[2]
    mkpath(out)
    prefix = joinpath(out, case)
    any(isfile(prefix*s) for s in ("_pressures.csv", "_validation.csv", "_runtime.txt")) && error("Audit output already exists: $prefix")
    basepath = plotsdir("paper_figures", "forward_sim_four_steps_base_data.jld2")
    savedpath = basepath
    sourcekey = case
    if case == "CVaR_g01_a001_1p22x_Figure1"
        savedpath = plotsdir("paper_figures", "cvar_day728_sensitivity_1p22x.jld2")
        rates = JLD2.load(savedpath, "rates")
    elseif case == "POF_eps0p01_1p65x"
        savedpath = plotsdir("paper_figures", "pof_eps001_full_campaign_sensitivity_1p65x.jld2")
        rates = JLD2.load(savedpath, "rates")
    elseif case == "CVaR_g01_a001_1p22x"
        savedpath = plotsdir("paper_figures", "full_campaign_video_CVaR_g01_a001_sensitivity.jld2")
        rates = JLD2.load(savedpath, "rate_by_substep")[1:10:end]
    elseif case == "No_Control_shutdown"
        savedpath = plotsdir("paper_figures", "no_control_delayed_ramp_10_periods.jld2")
        rates = JLD2.load(savedpath, "simulated_rates")
    else
        rates = JLD2.load(basepath, case*"_rates")
    end
    n = (512, 1, 256); d = (6.25, 100.0, 6.25); nc = prod(n)
    # Slice in JLD2 avoids materializing both permeability ensembles.
    Kmd = jldopen(datadir("geo/wise_perm_models_2000_new.jld2"), "r") do f
        f["BroadK"][2000, :, :]
    end
    K = Kmd .* JutulDarcyRules.md
    model = jutulModel(n, d, 0.25, K1to3(K; kvoverkh=0.36); h=0.0)
    logTrans = log.(KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36)))
    iz = 190 + argmax(K[250, 191:200])
    loc = (250*d[1], d[2], iz*d[3])
    s0 = jutulSimpleState(model)
    S0 = zeros(n[1], n[3])
    for (rows, offset) in [(249:251,-4),(248:252,-3),(247:253,-2),(246:254,-1),(246:254,0),(246:254,1),(247:253,2),(248:252,3),(249:251,4)]
        S0[rows, iz+offset] .= 0.5
    end
    s0[1:nc] = vec(S0)
    pmax = JLD2.load(basepath, "p_max")
    nt = case == "No_Control_shutdown" ? Int(JLD2.load(savedpath,"severe_substep")) : case == "CVaR_g01_a001_1p22x_Figure1" ? 91 : 240
    # Match original simulation call boundaries (video CVaR merges equal rates).
    segments = [(10*(i-1)+1, min(10*i,nt), r) for (i,r) in enumerate(rates) if 10*(i-1)<nt]
    if case == "CVaR_g01_a001_1p22x"
        merged = Tuple{Int,Int,Float64}[]
        for (a,b,r) in segments
            if !isempty(merged) && merged[end][3] == r
                aa,_,rr = pop!(merged); push!(merged,(aa,b,rr))
            else
                push!(merged,(a,b,r))
            end
        end
        segments = merged
    end
    open(prefix*"_runtime.txt", "w") do io
        println(io,"case=$case\nsource=$savedpath\nrepo_commit=$(readchomp(`git rev-parse HEAD`))\njulia=$(VERSION)\ninj_grid_z=$iz\nKmd_sha256_julia_column_major=$(bytes2hex(sha256(reinterpret(UInt8,vec(Kmd)))))")
        for m in (Jutul,JutulDarcy,JutulDarcyRules)
            println(io,"$(nameof(m)): version=$(pkgversion(m)); source=$(pathof(m))")
        end
        println(io,"segments=$segments\nphysical_BHP_limit=unresolved")
    end
    prev = s0
    open(prefix*"_pressures.csv", "w") do pressure_io
      println(pressure_io,"case,monitoring_step,substep,time_days,rate_target_m3_s,rate_actual_m3_s,bhp_reference_pa,reference_depth_m,node,node_depth_m,node_pressure_pa,perforation,reservoir_cell,x_index,z_index,reservoir_depth_m,reservoir_pressure_pa,configured_control_target")
      open(prefix*"_validation.csv", "w") do check_io
        println(check_io,"case,substep,time_days,max_reservoir_error_pa,max_saturation_error,max_load,fractured_cells,saved_max_load,saved_fractured_cells,canonical_bhp_minus_node1_pa")
        jldopen(savedpath,"r") do saved
          saved_pr = savedpath == basepath ? saved[sourcekey*"_pres_snaps"] : haskey(saved,"pres_all") ? saved["pres_all"] : nothing
          saved_sat = savedpath == basepath ? saved[sourcekey*"_sat_snaps"] : haskey(saved,"sat_all") ? saved["sat_all"] : nothing
          for (a,b,rate) in segments
            well = jutulVWell(rate, [(loc[1],loc[2])]; startz=[loc[3]],endz=[loc[3]+6*d[3]])
            states = jutulModeling(model, fill(8.0,b-a+1))(logTrans, well; state0=prev)
            length(states.states) == b-a+1 || error("Incomplete simulator output")
            prev = states.states[end]
            # Canonical output evaluated by the installed simulator, not inferred from array extrema.
            jm,_,_,forces = JutulDarcyRules.setup_well_model(model,well,fill(8.0*JutulDarcyRules.day,b-a+1))
            wd = Jutul.physical_representation(jm.models.Injector.domain)
            rawstates = [s.state for s in states.states]
            bhps = JutulDarcy.well_output(jm,rawstates,:Injector,forces)
            actual_rates = JutulDarcy.well_output(jm,rawstates,:Injector,forces,JutulDarcy.TotalRateTarget)
            open(prefix*"_runtime.txt","a") do io
                println(io,"segment=$a:$b forces=$(forces)\nwell_geometry=$(wd)\npressure_variable=$(jm.models.Injector.primary_variables[:Pressure])")
                if a == 1
                    println(io,"state_keys=$(keys(rawstates[1]))\nfacility_state=$(rawstates[1][:Facility])\nwell_state_keys=$(keys(rawstates[1][:Injector]))")
                end
            end
            for (j,st) in enumerate(rawstates)
                k=a+j-1; pr=reshape(st[:Reservoir][:Pressure],n[1],n[3]); sat=reshape(st[:Reservoir][:Saturations][1,:],n[1],n[3])
                wp=st[:Injector][:Pressure]
                # JutulDarcyRules discards WellGroupConfiguration from returned states.
                # Record configured control explicitly; actual achieved rate is independent evidence.
                target=string(typeof(forces[:Facility].control[:Injector].target))
                for node in eachindex(wp)
                    perf=findfirst(==(node),wd.perforations.self)
                    cell=isnothing(perf) ? 0 : wd.perforations.reservoir[perf]
                    ci=cell==0 ? (0,0,0) : Tuple(CartesianIndices(n)[cell])
                    rp=cell==0 ? NaN : pr[cell]
                    depth=cell==0 ? NaN : (ci[3]-0.5)*d[3]
                    vals=(case,cld(k,60),k,k*8.0,rate,actual_rates[j],bhps[j],wd.top.reference_depth,node,wd.centers[3,node],wp[node],something(perf,0),cell,ci[1],ci[3],depth,rp,target)
                    println(pressure_io,join(vals,','))
                end
                pe=NaN; se=NaN; sl=NaN; sf=NaN
                if savedpath==basepath && k%10==0
                    sp=saved_pr[:,:,div(k,10)]; ss=saved_sat[:,:,div(k,10)]
                    pe=maximum(abs.(pr.-sp)); se=maximum(abs.(sat.-ss)); sl=maximum(sp./pmax); sf=count(sp.>pmax)
                elseif haskey(saved,"pres_all")
                    sp=saved_pr[:,:,k]; ss=saved_sat[:,:,k]
                    pe=maximum(abs.(pr.-sp)); se=maximum(abs.(sat.-ss)); sl=maximum(sp./pmax); sf=count(sp.>pmax)
                elseif haskey(saved,"max_pressure_load_by_substep")
                    sl=saved["max_pressure_load_by_substep"][k]; sf=saved["fractured_cells_by_substep"][k]
                elseif haskey(saved,"pres") && k==91
                    sp=saved["pres"]; ss=saved["sat"]
                    pe=maximum(abs.(pr.-sp)); se=maximum(abs.(sat.-ss)); sl=maximum(sp./pmax); sf=count(sp.>pmax)
                end
                println(check_io,join((case,k,k*8.0,pe,se,maximum(pr./pmax),count(pr.>pmax),sl,sf,bhps[j]-wp[1]),','))
                if k == 91 && case in ("POF_eps0", "CVaR_g01_a001_1p22x", "CVaR_g01_a001_1p22x_Figure1")
                    figfile = plotsdir("paper_figures",case=="POF_eps0" ? "controlled_day728_POF_eps0.jld2" : "cvar_day728_sensitivity_1p22x.jld2")
                    fp = JLD2.load(figfile,"pres"); fs = JLD2.load(figfile,"sat")
                    open(prefix*"_figure1_validation.csv","w") do io
                        println(io,"case,time_days,max_reservoir_error_pa,max_saturation_error,rerun_fractured_cells,saved_fractured_cells")
                        println(io,join((case,728,maximum(abs.(pr.-fp)),maximum(abs.(sat.-fs)),count(pr.>pmax),count(fp.>pmax)),','))
                    end
                end
            end
            flush(pressure_io); flush(check_io)
            println("$case completed $a:$b / $nt"); flush(stdout)
            GC.gc()
          end
        end
      end
    end
    open(prefix*"_complete.txt","w") do io; println(io,"Completed $nt saved 8-day outputs; no physical BHP limit claimed."); end
end
main()
