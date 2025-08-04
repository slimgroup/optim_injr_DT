# Activate the project environment
using Pkg
Pkg.activate(".")
using DrWatson
# @quickactivate "optim_injr_DT" # <- project name
using JLD2
using JutulDarcyRules
using PyPlot
using Statistics
using PyCall
using SlimPlotting
# for saturation colorbar
@pyimport cmasher

# Physcial dimension
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0
ϕ = 0.25

# Water pressure 
# p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 9.807
p0 = (repeat(collect(1:256), 1, 512) * d[3] .+ h) * JutulDarcyRules.ρH2O * 10

## Set the fracture pressure 
threshold = 4.0
p_max = p0' .+ threshold * 10^6

# specify which monitoring step to run
monitoring_step = 2

# For other steps
prior_path = datadir("state/Wise_128SatPres_for_Optim_Inj_vec_ir_k" * string(monitoring_step-1) * ".jld2")
prior_data = JLD2.load(prior_path)

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

        data_diff = data - p0

        # define a new cmap for the threshold
        lower_cmap_size = round(Int, 256 * threshold * 1e6 / maximum(data_diff))
        upper_cmap_size = 256 - lower_cmap_size

        if lower_cmap_size > 256
            # if all the points in the figure smaller than the pressure threshold
            lower_cmap_size = 256
            upper_cmap_size = 0
            imshow(data_diff / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), cmap="Blues", vmin=0, vmax=threshold)
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
 
            colors = vcat(lower_cmap, upper_cmap)
            bounds = vcat(range(0, threshold; length=lower_cmap_size+1),
                        range(threshold, maximum(data)/1e6; length=upper_cmap_size+1)[2:end])
            norm = PyPlot.matplotlib.colors.BoundaryNorm(bounds, size(colors, 1))

            imshow(data_diff / 1e6, extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h),
                cmap=PyPlot.cm.colors.ListedColormap(colors), norm=norm)

            clb = colorbar(fraction=0.046*im_ratio, pad=0.04, extend="max")
            # Adjust the colorbar to reflect the threshold
            clb.set_ticks([0, threshold, maximum(data_diff/1e6)])
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


## Choose the worst posterior sample as the prior state 
pres_samples = prior_data["pres_samples"]
# min value in each 512x256 sample (i.e. along dimensions 2 & 3)
min_each_sample = map(i -> minimum(p_max - pres_samples[i, :, :]), 1:size(pres_samples, 1))
# get the global min across all samples
global_min_idx = argmin(min_each_sample)

function compute_superquantile(data::Array{Float32, 3}, α::Float64)
    nsamples, nx, ny = size(data)
    sorted_data = sort(data, dims=1)  # sort across samples (dim=1)
    VaR_idx = ceil(Int, α * nsamples)
    superquantile = mean(view(sorted_data, VaR_idx:nsamples, :, :), dims=1)
    return dropdims(superquantile, dims=1)  # shape: (512, 256)
end

pres_min = prior_data["pres_samples"][global_min_idx, :, :]

# Example usage
α = 0.95
pres_superquantile = compute_superquantile(pres_samples, α)


sim_name = "DT_control"
exp_name = "step" * string(monitoring_step)

plot_path = plotsdir(sim_name, savename(@strdict(exp_name); digits=6), "prior_select")

s = 1

plot_state(transpose(pres_min), "Initial Pressure (Min)", "_min_prior_pressure.png", plot_path, s, h, n, d, "pres")
plot_state(transpose(pres_min), "Initial Pressure Difference (Min)", "_min_prior_pressure_difference.png", plot_path, s, h, n, d, "pres_thres", -1, threshold)


plot_state(transpose(pres_superquantile), "Initial Pressure (Superquantile)", "superquantile_prior_pressure.png", plot_path, s, h, n, d, "pres")
plot_state(transpose(pres_superquantile), "Initial Pressure Difference (Superquantile)", "superquantile_prior_pressure_difference.png", plot_path, s, h, n, d, "pres_thres", -1, threshold)