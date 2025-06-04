# Tune the regularization term in the objective function and
# plot the objective function curve and also the gradient.

# Activate the project environment
# using Pkg
# Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT" # <- project name

using JutulDarcyRules
using LinearAlgebra
using PyPlot
using SlimOptim
using JLD2
using Random
using PyCall
using SlimPlotting
using Printf

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

# Use the groudtruth permeability slice
K = BroadK[end, :, :]

s = "GT"

# objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu)

## The objective function of the optimization problem
function objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu, sat_init=nothing, pres_init=nothing)
    # inj_rate, the injection rate vector

    # smooth and steadily increasing injection strategy
    inj_rate = collect(range(init_inj_rate[1], inj_rate[1], 6))

    # time discretization
    ds = 10
    
    # Length of the injection rate and time step
    inj_len = length(inj_rate)
    time_len = length(time_step)
 
    # Store the value of first and second term in the objetive function
    obj = 0
    obj_first = zeros(Float64, inj_len)
    obj_second = zeros(Float64, inj_len)
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
            @time states = S(log.(Trans), f)
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
        
        # maybe we can batch this part later 
        for j in 1:ds
            pres_bound_diff_arr[ds*(i-1)+j] = p_max - pres_arr[ds*(i-1)+j]
            BHP_bound_diff_arr[ds*(i-1)+j] = BHP_max .- BHP_arr[ds*(i-1)+j]

            # first term in the objective function
            obj_first[i] -= inj_rate[i] * time_step[ds*(i-1)+j] * JutulDarcyRules.day * JutulDarcyRules.ρCO2 
            
            # second term in the objective function
            if any(x -> x < 0, pres_bound_diff_arr[ds*(i-1)+j]) || any(x -> x < 0, BHP_bound_diff_arr[ds*(i-1)+j][1:8])
                # infeasible point
                obj_second[i] = Base.Inf
            else
                # println("j: ", j)
                obj_second[i] -= (sum(log.(pres_bound_diff_arr[ds*(i-1)+j])) + sum(log.(BHP_bound_diff_arr[ds*(i-1)+j][1:8]))) * time_step[ds*(i-1)+j] / mu
                # obj_second[i] -= (minimum(log.(pres_bound_diff_arr[ds*(i-1)+j])) + minimum(log.(BHP_bound_diff_arr[ds*(i-1)+j][1:8]))) * time_step[ds*(i-1)+j] / mu 
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
function grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu, sat_init=nothing, pres_init=nothing)
    grad = zeros(size(inj_rate, 1))
    
    for i in 1:size(inj_rate, 1)
        obj_forward, _, _, _, _, _, _, _, _ = 
        objective(inj_rate + delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu, sat_init, pres_init)
        obj_backward, _, _, _, _, _, _, _, _ = 
        objective(inj_rate - delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu, sat_init, pres_init)

        grad[i] = (obj_forward - obj_backward) / (2 * delta_inj_rate[i])
    end
    
    return grad
end

sim_name = "DT_control"
exp_name = "regu_tune" 

# The array to store different possible regularization weights
# Grid search or other search methods
mu_arr = [10^4]

plot_path = plotsdir(sim_name, savename(@strdict(exp_name); digits=6))

@pyimport cmasher
cmap_sat = cmasher.rainforest_r

# Function to plot the states variables, including permeability, pressure, pressure with threshold, saturation and porosity
function plot_state(data, title_str, file_suffix, plot_path, sample, h, n, d, type, mu, stp=-1, threshold=-1)
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
        data = data / 1e6
        im_pres = ax.imshow(data, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="cet_CET_L3_r")
        clb = fig.colorbar(im_pres, fraction=0.046 * im_ratio, pad=0.04)
        clb.ax.set_title("MPa", fontsize=15) 
    elseif type == "pres_thres"
        # Special case of plotting pressure with threshold

        data = (data - p0) / 1e6

        # define a new cmap for the threshold
        lower_cmap_size = round(Int, 256 * threshold / maximum(data))
        upper_cmap_size = 256 - lower_cmap_size

        if lower_cmap_size >= 256
            # if all the points in the figure smaller than the pressure threshold
            lower_cmap_size = 256
            upper_cmap_size = 0
            imshow(data, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="Blues", vmin=0, vmax=threshold)
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

            imshow(data, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), vmin=0, vmax=maximum(data), cmap=new_cmap)
            clb = colorbar(fraction=0.046*im_ratio, pad=0.04)
            # Adjust the colorbar to reflect the threshold
            clb.set_ticks([0, threshold, maximum(data)])
            clb.set_ticklabels(["0.0", string(threshold), ">" * string(threshold)])
        end
        clb[:ax][:set_title]("MPa", fontsize=15)
    else
        im_state = ax.imshow(data, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), vmin=0, vmax=1, cmap=cmap_sat)
        clb = fig.colorbar(im_state, fraction=0.046 * im_ratio, pad=0.04)
    end

    ax.set_title(title_str, fontsize=20)
    ax.set_xlabel("X[m]", fontsize=15)
    ax.set_ylabel("Depth[m]", fontsize=15)
    plt.tight_layout(pad=0.6, w_pad=0.5, h_pad=1.0)

    mu_fmt = @sprintf("%.0e", mu)

    if stp < 0
        safesave(joinpath(plot_path, savename(@strdict(mu_fmt, sample); digits=6) * file_suffix), fig)
    else
        safesave(joinpath(plot_path, savename(@strdict(mu_fmt, sample, stp); digits=6) * file_suffix), fig)
    end

    close(fig)
end

# Water pressure 
p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 9.807

## Set the fracture pressure 
threshold = 5.0
p_max = p0' .+ threshold * 10^6

# Finer discretization of time
ds = 10
time_step = 80 / ds * ones(6 * ds)

 # change unit
K = K * JutulDarcyRules.md

# Injector location
inj_y = 191 + argmax(K[250, 191:200]) - 1
inj_loc_grid = (250, 1, inj_y)
inj_loc = inj_loc_grid .* d

# BHP bound 
BHP_max = p_max[inj_y, 250]

# The initial injection rate
init_inj_rate = [0.0001]

# Main loop to tune the mu
for mu in mu_arr
    
    # Better format for mu 
    mu_fmt = @sprintf("%.0e", mu)

    # Do some plotting and saving for the parameters setting 
    # before the optimization

    if mu == mu_arr[1]
        # Plot the permeability
        logK = log10.(transpose(K/JutulDarcyRules.md))
        plot_state(logK, "Permeability", "_perm.png", plot_path, s, h, n, d, "perm", mu)
    end

    # 0.1 is the initial guess
    inj_rate = [0.1] 
    # finite difference h
    delta_inj_rate = 10^-8 * ones(size(inj_rate, 1))
    
    # optimization setup
    niterations = 20
    # injection rate over optimization loop, scalar injection rate
    inj_rate_arr = zeros(Float64, niterations+1, 1)
    inj_rate_arr[1, :] = inj_rate 
    # objective function value over optimization loop
    obj_arr = zeros(Float64, niterations+1)
    obj_1_arr = zeros(Float64, niterations+1, 6)
    obj_2_arr = zeros(Float64, niterations+1, 6)
    obj_arr_arr = zeros(Float64, niterations+1, 6)
    grad_arr = zeros(Float64, niterations+1, 1)

    obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_second, 
    obj_arr = objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu)

    println("Iteration no: ",0,"; Objective function value: ", obj)

    # before we do the optimization, first we do a sanity check for the injection rate
    # and also the reservoir setting
    while obj == Inf

        inj_rate .-= 0.05

        if inj_rate[1] < 0
            throw(ErrorException("Injection rate must be positive."))
        end

        if inj_rate[1] == 0
            inj_rate[1] == 0.0001
        end

        obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_second, 
        obj_arr = objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu)

        println("Iteration no: ",0,"; Objective function value: ", inj_rate)
    end 

    obj_arr[1] = obj
    obj_1_arr[1, :] = obj_first
    obj_2_arr[1, :] = obj_second
    obj_arr_arr[1, :] = obj_arr

    grad = grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu)
    p = -grad/norm(grad, Inf)
    grad_arr[1, :] = grad

    ## Plot the CO2 saturation at step 0
    plot_state(transpose(sat_arr[15]), "CO2 Saturation", "_co2sat15.png", plot_path, s, h, n, d, "sat", mu, 0)
    plot_state(transpose(sat_arr[30]), "CO2 Saturation", "_co2sat30.png", plot_path, s, h, n, d, "sat", mu, 0)
    plot_state(transpose(sat_arr[45]), "CO2 Saturation", "_co2sat45.png", plot_path, s, h, n, d, "sat", mu, 0)
    plot_state(transpose(sat_arr[60]), "CO2 Saturation", "_co2sat60.png", plot_path, s, h, n, d, "sat", mu, 0)
    
    ## Plot the reservoir pressure at step 0
    plot_state(transpose(pres_arr[15]), "Pressure", "_pres15.png", plot_path, s, h, n, d, "pres", mu, 0)
    plot_state(transpose(pres_arr[30]), "Pressure", "_pres30.png", plot_path, s, h, n, d, "pres", mu, 0)
    plot_state(transpose(pres_arr[45]), "Pressure", "_pres45.png", plot_path, s, h, n, d, "pres", mu, 0)
    plot_state(transpose(pres_arr[60]), "Pressure", "_pres60.png", plot_path, s, h, n, d, "pres", mu, 0)
    
    ## Plot the reservoir pressure difference at step 0
    plot_state(transpose(pres_arr[15]), "Pressure Difference", "_presdiff15.png", plot_path, s, h, n, d, "pres_thres", mu, 0, threshold)
    plot_state(transpose(pres_arr[30]), "Pressure Difference", "_presdiff30.png", plot_path, s, h, n, d, "pres_thres", mu, 0, threshold)
    plot_state(transpose(pres_arr[45]), "Pressure Difference", "_presdiff45.png", plot_path, s, h, n, d, "pres_thres", mu, 0, threshold)
    plot_state(transpose(pres_arr[60]), "Pressure Difference", "_presdiff60.png", plot_path, s, h, n, d, "pres_thres", mu, 0, threshold)

    # Save states variable at step 0
    @tagsave(datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(mu_fmt); digits=6), savename(@strdict(s); digits=6), savename(@strdict(0), "jld2"; digits=8)),
    Dict(
        "sat_arr" => sat_arr,
        "pres_arr" => pres_arr, 
        "BHP_arr" => BHP_arr, 
        "pres_bound_diff_arr" => pres_bound_diff_arr, 
        "BHP_bound_diff_arr" => BHP_bound_diff_arr, 
        );
    safe=true)

    ## Projection operator for bound constraints
    proj(x) = max.(x, 0)
    ls = BackTracking(order=3, iterations=10)

    step_arr = zeros(niterations)
    ex_step_size = 0.1


    ## Main loop for the projected gradient descent
    for j=1:niterations

        ## Linesearch
        function θ(α)
            misfit, _, _, _, _, _, _, _, _ = 
            objective(proj(inj_rate + α * p), time_step, K, inj_loc, p_max, BHP_max, mu)
            @show α, misfit
            return misfit
        end

        # Armijo condition
        step, obj = ls(θ, ex_step_size, obj, dot(grad, p))

        # Apply previous step size to next iteration
        ex_step_size = step

        step_arr[j] = step
        inj_rate = proj(inj_rate + step * p)
        inj_rate_arr[j+1, :] = inj_rate

        obj, sat_arr, pres_arr, BHP_arr, pres_bound_diff_arr, BHP_bound_diff_arr, obj_first, obj_second, 
        obj_arr = objective(inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu)

        println("Iteration no: ",j,"; Objective function value: ",obj) 
        
        obj_arr[j+1] = obj
        obj_1_arr[j+1, :] = obj_first
        obj_2_arr[j+1, :] = obj_second
        obj_arr_arr[j+1, :] = obj_arr

        # Update the gradient
        grad = grad_wrt_inj(inj_rate, delta_inj_rate, time_step, K, inj_loc, p_max, BHP_max, mu)
        p = -grad/norm(grad, Inf)
        grad_arr[j+1, :] = grad

        # Save states variable via iteration
        @tagsave(datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(mu_fmt); digits=6), savename(@strdict(s); digits=8), savename(@strdict(j), "jld2"; digits=6)),
        Dict(
            "sat_arr" => sat_arr,
            "pres_arr" => pres_arr, 
            "BHP_arr" => BHP_arr, 
            "pres_bound_diff_arr" => pres_bound_diff_arr, 
            "BHP_bound_diff_arr" => BHP_bound_diff_arr, 
            );
        safe=true)

        ## Plot the CO2 saturation 
        plot_state(transpose(sat_arr[15]), "CO2 Saturation", "_co2sat15.png", plot_path, s, h, n, d, "sat", mu, j)
        plot_state(transpose(sat_arr[30]), "CO2 Saturation", "_co2sat30.png", plot_path, s, h, n, d, "sat", mu, j)
        plot_state(transpose(sat_arr[45]), "CO2 Saturation", "_co2sat45.png", plot_path, s, h, n, d, "sat", mu, j)
        plot_state(transpose(sat_arr[60]), "CO2 Saturation", "_co2sat60.png", plot_path, s, h, n, d, "sat", mu, j)
        
        ## Plot the reservoir pressure 
        plot_state(transpose(pres_arr[15]), "Pressure", "_pres15.png", plot_path, s, h, n, d, "pres", mu, j, threshold)
        plot_state(transpose(pres_arr[30]), "Pressure", "_pres30.png", plot_path, s, h, n, d, "pres", mu, j, threshold)
        plot_state(transpose(pres_arr[45]), "Pressure", "_pres45.png", plot_path, s, h, n, d, "pres", mu, j, threshold)
        plot_state(transpose(pres_arr[60]), "Pressure", "_pres60.png", plot_path, s, h, n, d, "pres", mu, j, threshold)

        ## Plot the reservoir pressure difference
        plot_state(transpose(pres_arr[15]), "Pressure Difference", "_presdiff15.png", plot_path, s, h, n, d, "pres_thres", mu, j)
        plot_state(transpose(pres_arr[30]), "Pressure Difference", "_presdiff30.png", plot_path, s, h, n, d, "pres_thres", mu, j)
        plot_state(transpose(pres_arr[45]), "Pressure Difference", "_presdiff45.png", plot_path, s, h, n, d, "pres_thres", mu, j)
        plot_state(transpose(pres_arr[60]), "Pressure Difference", "_presdiff60.png", plot_path, s, h, n, d, "pres_thres", mu, j)

        # Define stopping criteria, accuracy more than 95%
        if step < (inj_rate + init_inj_rate)[1] / 2 * 0.05
            break
        end
    end

    # Save states variable via samples
    @tagsave(datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(mu_fmt); digits=8), savename(@strdict(s), "jld2"; digits=8)),
    Dict(
        "inj_rate_arr" => inj_rate_arr,
        "step_arr" => step_arr,
        "obj_arr" => obj_arr,
        "obj_1_arr" => obj_1_arr, 
        "obj_2_arr" => obj_2_arr,     
        "obj_arr_arr" => obj_arr_arr,
        );
    safe=true)

end