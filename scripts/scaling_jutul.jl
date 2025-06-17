# This for scaling analysis of the Jutul, reservoir simulator

# Activate the project environment
using Pkg
Pkg.activate(".")

using DrWatson
# @quickactivate "optim_injr_DT" # <- project name

using Pkg
Pkg.instantiate()

using JutulDarcyRules
using LinearAlgebra
using PyPlot
using SlimOptim
using JLD2
using Random
using PyCall
using SlimPlotting
using ArgParse
# for saturation colorbar
@pyimport cmasher

# Physcial dimension
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0
ϕ = 0.25

# Load the geological properties and reservoir state variables
geo_path = datadir("perm/wise_perm_models_2000_new.jld2")
geo_data = JLD2.load(geo_path)
BroadK = geo_data["BroadK"]

state1_path = datadir("state/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2")
state1_data = JLD2.load(state1_path)

# for test, fix s to be 1
s = 1

# Permeability indices
idices = state1_data["idx_t1"]
idx = idices[s]

K = BroadK[idx, :, :]

# For step 1

# Find injection location to be in the high permeability channel
inj_t1 = 191 + argmax(K[250, 191:200]) - 1

# Generate prior saturation        
S = zeros(Float64, n[1],n[end]);
Random.seed!(2025+s-1)  # Set the seed
value = 0.2 + rand(Float64)*0.6;
S[249:251,inj_t1-4] .= value;
S[248:252,inj_t1-3] .= value;
S[247:253,inj_t1-2] .= value;
S[246:254,inj_t1-1] .= value;
S[246:254,inj_t1]   .= value;
S[246:254,inj_t1+1] .= value;
S[247:253,inj_t1+2] .= value;
S[248:252,inj_t1+3] .= value;
S[249:251,inj_t1+4] .= value;
prior_t1 = S;

# # initial saturation and pressure
sat_init = S
# pres_init = water pressure

# For other steps

# MPC forward steps
forward_step = 1

## The objective function of the optimization problem
function objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init=nothing, pres_init=nothing)
    # inj_rate, the injection rate vector

    # smooth and steadily increasing injection strategy
    # inj_rate = collect(range(init_inj_rate[1], inj_rate[1], 6))
    inj_rate = collect(range(init_inj_rate[1], inj_rate[1], forward_step * 6))


    # time discretization
    ds = 10
    
    # Length of the injection rate and time step
    inj_len = length(inj_rate)
    time_len = length(time_step)
 
    # Store the value of first and second term in the objetive function
    obj_first = zeros(Float64, inj_len)
    obj_second = zeros(Float64, inj_len)
    obj = 0
    obj_arr = zeros(Float64, inj_len)

    # The array store saturation, pressure, pressure difference along time
    sat_arr = [zeros(n[1], n[end]) for _ in 1:time_len]
    pres_arr = [zeros(n[1], n[end]) for _ in 1:time_len]
    pres_bound_diff_arr = [zeros(n[1], n[end]) for _ in 1:time_len]

    # BHP array length to be 8, 7 well perforations 
    BHP_arr = [zeros(8) for _ in 1:time_len]
    # Different between BHP and BHP bound
    BHP_bound_diff_arr = [zeros(8) for _ in 1:time_len]

    ## Previous state
    previous_state = nothing
    for i in 1:inj_len
        # first injection period
        if i == 1
            # set up the reservoir parameters
            model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
            f = jutulVWell(inj_rate[i], [(inj_loc[1], inj_loc[2])]; startz = [inj_loc[3]], endz = [inj_loc[3]+6*d[3]])
            S = jutulModeling(model, time_step[1:ds])
            Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))    
            state0 = jutulSimpleState(model)
            state0[1:n[1]*n[3]] = vec(sat_init)    
            @time states = S(log.(Trans), f; state0=state0)
            previous_state = states.states[end]
        else
            model = jutulModel(n, d, ϕ, K1to3(K; kvoverkh=0.36); h=h)
            f = jutulVWell(inj_rate[i], [(inj_loc[1],inj_loc[2])]; startz = [inj_loc[3]], endz = [inj_loc[3]+6*d[3]])
            S = jutulModeling(model, time_step[1:ds])
            Trans = KtoTrans(CartesianMesh(model), K1to3(K; kvoverkh=0.36))
            @time states = S(log.(Trans), f; state0=previous_state)
            previous_state = states.states[end]   
        end   
       
        # saturation, pressure, BHP varying along time,
        # temporary variables
        sat_tmp = [reshape(states.states[k][1:n[1]*n[3]], n[1], n[end]) for k in 1:ds]
        pres_tmp = [reshape(states.states[k][n[1]*n[3]+1:end], n[1], n[end]) for k in 1:ds]
        BHP_tmp = [states.states[k].state[:Injector][:Pressure] for k in 1:ds]

        sat_arr[(i-1)*ds+1:i*ds] = sat_tmp
        pres_arr[(i-1)*ds+1:i*ds] = pres_tmp
        BHP_arr[(i-1)*ds+1:i*ds] = BHP_tmp

        # regularization term for the log-barrier term
        mu = 1e4

        # maybe we can batch this part later 
        for j in 1:ds
            pres_bound_diff_arr[ds*(i-1)+j] = p_max - pres_arr[ds*(i-1)+j]
            BHP_bound_diff_arr[ds*(i-1)+j] = BHP_max .- BHP_arr[ds*(i-1)+j]

            # first term in the objective function
            obj_first[i] -= inj_rate[i] * time_step[ds*(i-1)+j] * JutulDarcyRules.day * JutulDarcyRules.ρCO2 

            # second term in the objective function
            if any(x->x<0, pres_bound_diff_arr[ds*(i-1)+j]) || any(x->x<0, BHP_bound_diff_arr[ds*(i-1)+j][1])
                # infeasible point
                obj_second[i] = Base.Inf
            else
                obj_second[i] -= (sum(log.(pres_bound_diff_arr[ds*(i-1)+j])) 
                + sum(log.(BHP_bound_diff_arr[ds*(i-1)+j][1]))) * time_step[ds*(i-1)+j] / mu
            end
        end
  
        obj_i = obj_first[i] + obj_second[i] 
        obj_arr[i] = obj_i
        obj += obj_i
    end

    # garbage collection for memory
    previous_state = nothing
    GC.gc()

    return obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_second, obj_arr
end

## The function to calculate the gradient of the objective function w.r.t the injection rate.
## It uses finite difference method with the h to be delta_inj_rate. 
function grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init=nothing, pres_init=nothing)
    grad = zeros(size(inj_rate, 1))
    
    for i in 1:size(inj_rate, 1)
        obj_forward, _, _, _, _, _, _, _, _ = 
        objective(inj_rate + delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init, pres_init)
        obj_backward, _, _, _, _, _, _, _, _ = 
        objective(inj_rate - delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init, pres_init)

        grad[i] = (obj_forward - obj_backward) / (2 * delta_inj_rate[i])
    end
    
    return grad
end

# The initial injection rate
init_inj_rate = [0.0001]

sim_name = "DT_control"
exp_name = "scaling"  

plot_path = plotsdir(sim_name, savename(@strdict(exp_name); digits=6), "states")

# Function to plot the states variables, including permeability, pressure, pressure with threshold, saturation and porosity
function plot_state(data, title_str, file_suffix, plot_path, sample, h, n, d, type, iter=-1, threshold=-1)
    rc("font", family="serif")
    rc("xtick", labelsize=15)
    rc("ytick", labelsize=15)
    
    fig, ax = subplots(figsize=(10, 5))
    im_ratio = n[3] * d[3]/(n[1] * d[1])

    if type == "perm"
        im_K = ax.imshow(data, vmin=0, vmax=4, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="cet_rainbow4")
        clb = fig.colorbar(im_K, fraction=0.046*im_ratio, pad=0.04)
        clb.ax.set_title("Md", fontsize=15) 
        clb.set_ticks(log10.([1, 10, 1000])) 
        clb.set_ticklabels(["1", "1e1", "1e3"])
     elseif type == "pres"
        im_pres = ax.imshow(data / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="cet_CET_L3_r")
        clb = fig.colorbar(im_pres, fraction=0.046 * im_ratio, pad=0.04)
        clb.ax.set_title("MPa", fontsize=15) 
    elseif type == "pres_thres"
        # Special case of plotting pressure with threshold

        data = data - p0

        # define a new cmap for the threshold
        lower_cmap_size = round(Int, 256 * threshold * 1e6 / maximum(data))
        upper_cmap_size = 256 - lower_cmap_size

        if lower_cmap_size > 256
            # if all the points in the figure smaller than the pressure threshold
            lower_cmap_size = 256
            upper_cmap_size = 0
            imshow(data / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="Blues", vmin=0, vmax=threshold)
            clb = colorbar(fraction=0.046*im_ratio, pad=0.04, extend="max")
            # Adjust the colorbar to reflect the threshold
            clb.set_ticks([0, threshold])
            clb.set_ticklabels(["0.0", string(threshold)])
        else
            # if there is one point in the figure larger than the pressure threshold (fractures),
            # highlight the fractures in red 
            np = pyimport("numpy")
            lower_cmap = PyPlot.cm.Blues(np.linspace(0, 1, lower_cmap_size))
            upper_cmap = transpose(repeat(collect(PyPlot.cm.colors.to_rgba("red")), outer=(1, upper_cmap_size)))

            new_cmap_array = vcat(lower_cmap, upper_cmap)
            new_cmap = PyPlot.cm.colors.ListedColormap(new_cmap_array)

            imshow(data / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap=new_cmap, vmin=0, vmax=maximum(data))
            clb = colorbar(fraction=0.046*im_ratio, pad=0.04, extend="max")
            # Adjust the colorbar to reflect the threshold
            clb.set_ticks([0, threshold, maximum(data)])
            clb.set_ticklabels(["0.0", string(threshold), ">" * string(threshold)])
        end
        clb[:ax][:set_title]("MPa", fontsize=15)
    elseif type == "sat"
        im_state = ax.imshow(data, vmin=0, vmax=1, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap=cmasher.rainforest_r)
        clb = fig.colorbar(im_state, fraction=0.046 * im_ratio, pad=0.04)
    else
        im_state = ax.imshow(data, vmin=0, vmax=1, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h))
        clb = fig.colorbar(im_state, fraction=0.046 * im_ratio, pad=0.04)
    end

    ax.set_title(title_str, fontsize=20)
    ax.set_xlabel("X[m]", fontsize=15)
    ax.set_ylabel("Depth[m]", fontsize=15)
    plt.tight_layout(pad=0.6, w_pad=0.5, h_pad=1.0)

    if iter < 0
        safesave(joinpath(plot_path, savename(@strdict(sample); digits=6) * file_suffix), fig)
    else
        safesave(joinpath(plot_path, savename(@strdict(sample, iter); digits=6) * file_suffix), fig)
    end

    close(fig)
end

# Water pressure 
# p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 9.807
p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10

## Set the fracture pressure 
threshold = 4.0
p_max = p0' .+ threshold * 10^6

# Plot this part only s is 1, sample 1
if s == 1
    plot_state(transpose(p_max), "Fracture pressure", "_fracture_pressure.png", plot_path, s, h, n, d, "pres")

    plot_state(p0, "Water pressure", "_water_pressure.png", plot_path, s, h, n, d, "pres")

    fracture_pressure_diff = transpose(p_max) - p0

    plot_state(fracture_pressure_diff, "Fracture pressure difference", "_fracture_pressure_diff.png", plot_path, s, h, n, d, "pres")

    plot_ϕ = ϕ * ones(n)
    plot_ϕ = transpose(plot_ϕ[:, 1, :])
    plot_state(plot_ϕ, "Porosity", "_poro.png", plot_path, s, h, n, d, "poro")
end

# Finer discretization of time
ds = 10
time_step = 80 / ds * ones(6 * ds * forward_step)
# 0.05 is the initial guess
inj_rate = [0.05] 
# finite difference h
delta_inj_rate = 10^-8 * ones(size(inj_rate, 1))

# change unit
K = K * JutulDarcyRules.md

# Injector location
inj_y = 191 + argmax(K[250, 191:200]) - 1
inj_loc_grid = (250, 1, inj_y)
inj_loc = inj_loc_grid .* d

# BHP bound 
BHP_max = p_max[inj_y, 250]

# Do some plotting and saving for the parameters setting 
# before the optimization

# Plot the permeability
logK = log10.(transpose(K/JutulDarcyRules.md))
plot_state(logK, "Permeability", "_perm.png", plot_path, s, h, n, d, "perm")

# optimization setup
niterations = 20
# injection rate over optimization loop, scalar injection rate
inj_rate_arr = zeros(Float64, niterations+1, size(inj_rate, 1))
inj_rate_arr[1, :] = inj_rate
# objective function value over optimization loop
obj_arr_niter = zeros(Float64, niterations+1)
obj_1_arr = zeros(Float64, niterations+1, forward_step * 6)
obj_2_arr = zeros(Float64, niterations+1, forward_step * 6)
obj_arr_arr = zeros(Float64, niterations+1, forward_step * 6)
# grad_arr = zeros(Float64, niterations+1, 1)

obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_second, 
obj_arr = objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, sat_init)

println("Iteration no: ",0,"; Objective function value: ", obj)
