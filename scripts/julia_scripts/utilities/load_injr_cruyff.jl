# Activate the project environment
using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"
using JLD2
# using FilePathsBase  # Only needed if you're working with paths as objects
# using FileIO  # Needed for `@tagload`
using PyPlot
using KernelDensity
using Statistics
using Random
using StatsBase
using Distributions

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

num_s = 128

injr_dist = zeros(num_s)

# step 1 initial injection rate
init_inj_rate = [0.0001]

for s in 73:128
    
    # filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(sample), "jld2"; digits=8))

    # # Load all variables from file into a dictionary
    # data = load(filepath)

    # cruyff data path prefix 
    cruyff_data_path_prefix = "/slimdata/jason/optim_injr_DT/data"

    full_data_path = joinpath(
        cruyff_data_path_prefix,
        sim_name,
        savename(@strdict(exp_name); digits=6),
        savename(@strdict(s), "jld2"; digits=6)
    )

    data = load(full_data_path)

    # Now access variables from the dictionary
    inj_rate_arr = data["inj_rate_arr"][:, 1]

    # Find last nonzero element
    last_nonzero = findlast(x -> x != 0, inj_rate_arr)
    
    if last_nonzero === nothing
        # If all zeros, handle it as you want, e.g., assign 0 or NaN
        injr_dist[s] = (0.0 + init_inj_rate[1]) / 2
    else
        injr_dist[s] = (inj_rate_arr[last_nonzero] + init_inj_rate[1]) / 2
    end
end

# Plot directory on cruyff
cruyff_plot_path_prefix = "/slimdata/jason/optim_injr_DT/plots"

plot_path = joinpath(
    cruyff_plot_path_prefix,
    sim_name,
    savename(@strdict(exp_name); digits=6),
    "decision"
)

## Plot the injection rate distribution 

# using PyPlot, KernelDensity

# Your injection rate data vector, example:
# injr_dist = [...]

function find_local_maxima(density_array)
    maxima = Int[]
    for i in 2:length(density_array)-1
        if density_array[i] > density_array[i-1] && density_array[i] > density_array[i+1]
            push!(maxima, i)
        end
    end
    return maxima
end

kde_res = kde(injr_dist; bandwidth=optimal_bandwidth)

fig = figure(figsize=(10, 6))

# Histogram
hist_vals = hist(injr_dist;
    bins=75,
    alpha=0.5,
    color="#4A90E2",
    edgecolor="#1F497D",
    linewidth=0.8,
    density=false,
    label="Histogram"
)

bin_edges = hist_vals[2]
bin_width = bin_edges[2] - bin_edges[1]
scaled_kde_density = kde_res.density .* length(injr_dist) .* bin_width

# KDE fill and line
fill_between(kde_res.x, scaled_kde_density, color="#D9534F", alpha=0.3, label="KDE Density")
plot(kde_res.x, scaled_kde_density, color="#D9534F", linewidth=2.5, label="KDE")

# Rug plot for data points
for x in injr_dist
    plot([x, x], [0, maximum(scaled_kde_density)*0.04], color="#333333", alpha=0.7, linewidth=1.0)
end

# Define red box regions including the new left region
red_boxes = [
    (0.015, 0.025),
    (0.025, 0.05),
    (0.055, 0.07),
    (0.08, 0.095),
    (0.11, 0.12),
    (0.13, 0.145)
]

local_maxima_indices = find_local_maxima(kde_res.density)

selected_peak_indices = Int[]

max_labels_per_box = 1  # reduce to 1 peak per box for less clutter

for (xmin, xmax) in red_boxes
    region_peaks = filter(idx -> (kde_res.x[idx] >= xmin) && (kde_res.x[idx] <= xmax) && (idx in local_maxima_indices), 1:length(kde_res.x))
    if !isempty(region_peaks)
        sorted_peaks = sort(region_peaks, by=idx -> -kde_res.density[idx])
        top_peaks = sorted_peaks[1:min(max_labels_per_box, length(sorted_peaks))]
        append!(selected_peak_indices, top_peaks)
    end
end

selected_peak_indices = sort(unique(selected_peak_indices), by=idx -> kde_res.x[idx])

# Plot with staggered vertical offsets to avoid overlap
for (i, idx) in enumerate(selected_peak_indices)
    x_peak = kde_res.x[idx]
    y_peak = scaled_kde_density[idx]

    scatter([x_peak], [y_peak], color="#006400", s=90, marker="o", edgecolor="black", linewidth=1.5, zorder=6)

    # stagger y-offset by 15 points per label index
    y_offset = 20 + 15 * (i % 2)  # alternate between 20 and 35 points

    annotate(
        string(round(x_peak, digits=3)),
        xy=(x_peak, y_peak),
        xytext=(0, y_offset),
        textcoords="offset points",
        ha="center",
        fontsize=14,
        fontweight="bold",
        color="#006400",
        rotation=0
    )
end

title("Histogram of Injection Rates (n=$(length(injr_dist))) with KDE Overlay", fontsize=18, fontweight="bold")
xlabel("Average Injection Rate (m³/s)", fontsize=16, fontweight="bold")
ylabel("Frequency", fontsize=16, fontweight="bold")

legend(fontsize=14, frameon=false)

xticks(fontsize=14, fontweight="bold")
yticks(fontsize=14, fontweight="bold")

# Make y-axis tick labels darker for clarity
ax = gca()
ax.spines["top"].set_visible(false)
ax.spines["right"].set_visible(false)
ax.tick_params(axis="y", colors="black")  # Darker y-tick labels

ax.minorticks_on()

grid(color="#AAAAAA", linestyle="--", linewidth=0.5, alpha=0.7)

tight_layout()
# show()

# Construct the filename with sample count info
filename = "injection_distribution_$(num_s)samples.png"

# Save figure using DrWatson safesave (pass the figure handle `fig`)
safesave(joinpath(plot_path, filename), fig)

close(fig)




## Plot CDF and confidence interval

num_sample_kde = 1000
optimal_bandwidth = 0.0006

# Compute KDE with specified bandwidth
kde_res = kde(injr_dist; bandwidth=optimal_bandwidth)

# Sort injection rates
sorted_injr = sort(injr_dist)

# Create kde_x range for evaluation
kde_x = range(minimum(injr_dist), stop=maximum(injr_dist), length=num_sample_kde)
step = kde_x[2] - kde_x[1]

# Compute KDE PDF values at kde_x
kde_pdf_vals = pdf(kde_res, kde_x)

# Compute smooth KDE-based CDF by cumulative sum * step
kde_cdf = cumsum(kde_pdf_vals) * step

# Prepare arrays for confidence intervals
ci_lower_arr = zeros(num_sample_kde)
ci_upper_arr = zeros(num_sample_kde)
p_hat_arr = zeros(num_sample_kde)

n = length(injr_dist)  # sample size

conf_level = 0.95
z = quantile(Normal(), 1 - (1 - conf_level) / 2)  # z-score for CI

for i in 1:num_sample_kde
    p_hat = kde_cdf[i]
    se = sqrt(p_hat * (1 - p_hat) / n)
    ci_lower = max(0, p_hat - z * se)
    ci_upper = min(1, p_hat + z * se)
    ci_lower_arr[i] = ci_lower
    ci_upper_arr[i] = ci_upper
    p_hat_arr[i] = p_hat
end

# fracture_prob_threshold = 0.10  # 10%
# fracture_prob_threshold = 0.05  # 5%
# fracture_prob_threshold = 0.01  # 1%
# fracture_prob_threshold = 0.025  # 2.5%


# Find the index and injection rate for fracture probability threshold
idx_at_threshold = findfirst(x -> x >= fracture_prob_threshold, kde_cdf)
inj_rate_at_threshold = kde_x[idx_at_threshold]
ci_lower_at_threshold = ci_lower_arr[idx_at_threshold]
ci_upper_at_threshold = ci_upper_arr[idx_at_threshold]

# Find injection rates corresponding to the CI fracture probability bounds
idx_at_ci_lower = findfirst(x -> x >= ci_lower_at_threshold, kde_cdf)
inj_rate_at_ci_lower = kde_x[idx_at_ci_lower]

idx_at_ci_upper = findfirst(x -> x >= ci_upper_at_threshold, kde_cdf)
inj_rate_at_ci_upper = kde_x[idx_at_ci_upper]

# Plotting
fig = figure(figsize=(8, 8))

plot(kde_x, kde_cdf * 100, label="CDF", linewidth=2)
fill_between(kde_x, ci_lower_arr * 100, ci_upper_arr * 100, color="gray", alpha=0.3, label="95% Confidence Interval")
axhline(y=fracture_prob_threshold * 100, color="red", linestyle="--", linewidth=1.5, label="2.5% Fracture Probability")

annotate(
    "Injection Rate at 2.5% Probability: $(round(inj_rate_at_threshold, digits=4)) m³/s",
    xy=(inj_rate_at_threshold, fracture_prob_threshold * 100),
    xytext=(inj_rate_at_threshold + 0.07, fracture_prob_threshold * 100 + 25),
    arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"),
    fontsize=14,
    ha="center"
)

annotate(
    "Left CI: $(round(inj_rate_at_ci_lower, digits=4)) m³/s",
    xy=(inj_rate_at_ci_lower, fracture_prob_threshold * 100),
    xytext=(inj_rate_at_ci_lower + 0.08, fracture_prob_threshold * 100 + 40),
    arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"),
    fontsize=14,
    ha="right"
)

annotate(
    "Right CI: $(round(inj_rate_at_ci_upper, digits=4)) m³/s",
    xy=(inj_rate_at_ci_upper, fracture_prob_threshold * 100),
    xytext=(inj_rate_at_ci_upper + 0.04, fracture_prob_threshold * 100 + 10),
    arrowprops=Dict("arrowstyle" => "->", "connectionstyle" => "arc3,rad=0"),
    fontsize=14,
    ha="left"
)

grid(color="lightgray", linestyle="--", linewidth=0.5)
xlabel("Average Injection Rate (m³/s)", fontsize=16)
ylabel("Fracture Probability (%)", fontsize=16)
title("Fracture Probability vs Average Injection Rate", fontsize=18)
legend(loc="upper left", fontsize=14)
xticks(fontsize=14)
yticks(fontsize=14)
tight_layout()

# Save figure
filename = "fracture_prob_CI_$(num_s)samples.png"
safesave(joinpath(plot_path, filename), fig)
close(fig)
