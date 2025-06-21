# Activate the project environment
using Pkg
Pkg.activate(".")

using DrWatson
# @quickactivate "optim_injr_DT" # <- project name
using JLD2
# using FilePathsBase  # Only needed if you're working with paths as objects
# using FileIO  # Needed for `@tagload`
using PyPlot
using KernelDensity
using Statistics

# Set parameters consistent with how it was saved
sim_name = "DT_control"
exp_name = "step1" # which step to control in DT

# s = 1  # sample number

# filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s), "jld2"; digits=8))

# # Load all variables from file into a dictionary
# data = load(filepath)

# # Now access variables from the dictionary
# inj_rate_arr = data["inj_rate_arr"]
# step_arr = data["step_arr"]

# This parameter is corrupted
# obj_arr = data["obj_arr"]

# obj_1_arr = data["obj_1_arr"]
# obj_2_arr = data["obj_2_arr"]
# obj_arr_arr = data["obj_arr_arr"]

# Now the variables inj_rate_arr, step_arr, etc. are available in your workspace

num_sample = 128

injr_arr = zeros(num_sample)

for s in 1:num_s
    
    s = 1
    j = 3
    inner_filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s); digits=6), savename(@strdict(j), "jld2"; digits=6))
    inner_data = load(inner_filepath)

    # filepath = datadir("forward_1", sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s), "jld2"; digits=8))
    filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s), "jld2"; digits=8))


    # Load all variables from file into a dictionary
    data = load(filepath)

    # Now access variables from the dictionary
    inj_rate_arr = data["inj_rate_arr"]


    injr_arr[sample] = maximum(inj_rate_arr)
end

sim_name = "DT_control"
exp_name = "step1"
num_sample = length(injr_arr)  # or your number of samples
file_suffix = ".png"

# Set up the plot directory using DrWatson
plot_path = plotsdir(sim_name, savename(@strdict(exp_name); digits=6), "decision")
# mkpath(plot_path)  # ensure directory exists
using PyPlot
using KernelDensity

# Compute KDE for injection rates
kde_res = kde(injr_arr)

# Create figure with specified size
fig = figure(figsize=(8, 6))

# Plot histogram of injection rates, normalized so KDE and histogram align
hist_vals = hist(injr_arr;
    bins=30,
    alpha=0.5,
    color="blue",
    edgecolor="black",
    density=true,
    label="Histogram"
)

# Calculate bin width for scaling KDE density to histogram scale
bin_edges = hist_vals[2]
bin_width = bin_edges[2] - bin_edges[1]

# Scale KDE density to match histogram scale
scaled_kde_density = kde_res.density .* length(injr_arr) .* bin_width

# Overlay KDE curve with slight vertical scaling for visibility
plot(kde_res.x, scaled_kde_density .* 1.05;
    color="red",
    linewidth=2,
    label="KDE"
)

# Add title and axis labels with increased font size
title("Histogram of Injection Rates with KDE Overlay", fontsize=18)
xlabel("Injection Rate (m³/s)", fontsize=16)
ylabel("Frequency", fontsize=16)

# Add legend with readable font size
legend(fontsize=14)

# Customize tick label font size for both axes
xticks(fontsize=14)
yticks(fontsize=14)

# Add subtle grid lines for better readability
grid(color="grey", linestyle="--", linewidth=0.5, alpha=0.7)

# Remove top and right spines for a cleaner plot look
ax = gca()
ax.spines["top"].set_visible(false)
ax.spines["right"].set_visible(false)

# Adjust layout to prevent clipping of labels and titles
tight_layout()


# Construct the filename with sample count info
filename = "injection_distribution_$(num_sample)samples" * file_suffix

# Save figure using DrWatson safesave (pass the figure handle `fig`)
safesave(joinpath(plot_path, filename), fig)

close(fig)
