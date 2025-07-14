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
using Random
using StatsBase
using Distributions

# specify which monitoring step to run
monitoring_step = 2

# Set parameters consistent with how it was saved
sim_name = "DT_control"
exp_name = "step" * string(monitoring_step)

# s = 2  # sample number

# filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s), "jld2"; digits=8))

# # Load all variables from file into a dictionary
# data = load(filepath)

# # Now access variables from the dictionary
# inj_rate_arr = data["inj_rate_arr"]
# step_arr = data["step_arr"]

# # This parameter is corrupted
# obj_arr = data["obj_arr"]

# obj_1_arr = data["obj_1_arr"]
# obj_2_arr = data["obj_2_arr"]
# obj_arr_arr = data["obj_arr_arr"]

# Now the variables inj_rate_arr, step_arr, etc. are available in your workspace

num_s = 128

injr_dist = zeros(num_s)

if monitoring_step == 1
    # step 1 initial injection rate
    init_inj_rate = [0.0001]

    valid_ids = 1:128
elseif monitoring_step == 2
    # step 2 initial injection rate
    init_inj_rate = [0.026245454545454544]
    
    # 存在文件的 sample ids（排除缺失）
    missing_ids = Set([40, 113])
    valid_ids = setdiff(1:num_s, missing_ids)

    num_s = 126
else
    error("Invalid monitoring step. Choose either 1 or 2.")
end

# Calculate the injection rate distribution

for s in valid_ids

    # s = 1
    # j = 3
    # inner_filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s); digits=6), savename(@strdict(j), "jld2"; digits=6))
    # inner_data = load(inner_filepath)

    # filepath = datadir("forward_1", sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s), "jld2"; digits=8))
    filepath = datadir(sim_name, savename(@strdict(exp_name); digits=6), savename(@strdict(s), "jld2"; digits=8))

    # Load all variables from file into a dictionary
    data = load(filepath)

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



## Only for step 1
if monitoring_step == 1
    # Load the injection rate distribution for step 1
    # injr_dist_1_to_32 = load("scripts/injr_dist_1_to_32.jld2", "injr_dist_1_to_32")
    # injr_dist_33_to_72 = load("scripts/injr_dist_33_to_72.jld2", "injr_dist_33_to_72")
    # injr_dist_73_to_128 = load("scripts/injr_dist_73_to_128.jld2", "injr_dist_73_to_128")

    injr_dist = load("scripts/injr_dist_step1.jld2", "injr_dist_step1")

elseif monitoring_step == 2
    # Load the injection rate distribution for step 2
    injr_dist = load("scripts/injr_dist_step2.jld2", "injr_dist_step2")
else
    error("Invalid monitoring step. Choose either 1 or 2.")
end

# Check the result
@show length(injr_dist)  # should be 128
@show sum(injr_dist .!= 0)  # should be 128 if all nonzeros were distinct

# # # Run optimization (you can adjust bounds)
# optimal_result = optimize(h -> loo_cv_loglik(h, injr_dist), 0.0001, 0.01)
# optimal_bandwidth = Optim.minimizer(optimal_result)

## Set bandwidth 
# optimal_bandwidth = 0.0008
optimal_bandwidth = 0.008617873204629483
## Set plot path
plot_path = plotsdir(sim_name, savename(@strdict(exp_name); digits=6), "decision")

## Plot the injection rate distribution 

# using PyPlot, KernelDensity

# Your injection rate data vector, example:
# injr_dist = [...]

# function find_local_maxima(density_array)
#     maxima = Int[]
#     for i in 2:length(density_array)-1
#         if density_array[i] > density_array[i-1] && density_array[i] > density_array[i+1]
#             push!(maxima, i)
#         end
#     end
#     return maxima
# end

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

# # Define red box regions including the new left region
# red_boxes = [
#     (0.015, 0.025),
#     (0.025, 0.05),
#     (0.055, 0.07),
#     (0.08, 0.095),
#     (0.11, 0.12),
#     (0.13, 0.145)
# ]

# local_maxima_indices = find_local_maxima(kde_res.density)

# selected_peak_indices = Int[]

# max_labels_per_box = 1  # reduce to 1 peak per box for less clutter

# for (xmin, xmax) in red_boxes
#     region_peaks = filter(idx -> (kde_res.x[idx] >= xmin) && (kde_res.x[idx] <= xmax) && (idx in local_maxima_indices), 1:length(kde_res.x))
#     if !isempty(region_peaks)
#         sorted_peaks = sort(region_peaks, by=idx -> -kde_res.density[idx])
#         top_peaks = sorted_peaks[1:min(max_labels_per_box, length(sorted_peaks))]
#         append!(selected_peak_indices, top_peaks)
#     end
# end

# selected_peak_indices = sort(unique(selected_peak_indices), by=idx -> kde_res.x[idx])

# # Plot with staggered vertical offsets to avoid overlap
# for (i, idx) in enumerate(selected_peak_indices)
#     x_peak = kde_res.x[idx]
#     y_peak = scaled_kde_density[idx]

#     scatter([x_peak], [y_peak], color="#006400", s=90, marker="o", edgecolor="black", linewidth=1.5, zorder=6)

#     # stagger y-offset by 15 points per label index
#     y_offset = 20 + 15 * (i % 2)  # alternate between 20 and 35 points

#     annotate(
#         string(round(x_peak, digits=3)),
#         xy=(x_peak, y_peak),
#         xytext=(0, y_offset),
#         textcoords="offset points",
#         ha="center",
#         fontsize=14,
#         fontweight="bold",
#         color="#006400",
#         rotation=0
#     )
# end

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
filename = "injection_distribution_samples$(num_s)_bandwidth$(optimal_bandwidth).png"

# Save figure using DrWatson safesave (pass the figure handle `fig`)
safesave(joinpath(plot_path, filename), fig)

close(fig)




## Confidence interval type
CI_type = "wald"
# CI_type = "wilson"
# CI_type = "jeffreys"
fracture_prob_threshold = 0.01  # 1%
conf_level = 0.99  # 99% confidence level
num_sample_kde = 16000
zoomed_in = true  # Set to true for zoomed-in plot

## Plot the CDF and confidence interval

# Parameters
z = quantile(Normal(), 1 - (1 - conf_level) / 2)
n = length(injr_dist)
fracture_prob_threshold = 0.01  # 1%

# KDE
kde_res = kde(injr_dist; bandwidth=optimal_bandwidth)
kde_x = range(minimum(injr_dist), stop=maximum(injr_dist), length=num_sample_kde)
stp = kde_x[2] - kde_x[1]
kde_pdf_vals = pdf(kde_res, kde_x)
kde_cdf = cumsum(kde_pdf_vals) * stp

# Wald Confidence Interval
ci_lower_arr = zeros(num_sample_kde)
ci_upper_arr = zeros(num_sample_kde)

# calculate the confidence interval
for i in 1:num_sample_kde
    if CI_type == "wald"
        p_hat = kde_cdf[i]
        se = sqrt(p_hat * (1 - p_hat) / n)
        ci_lower_arr[i] = max(0.0, p_hat - z * se)
        ci_upper_arr[i] = min(1.0, p_hat + z * se)
    elseif CI_type == "wilson"
        p_hat = kde_cdf[i]
        z2 = z^2
        denom = 1 + z2 / n
        center = p_hat + z2 / (2n)
        radicand = p_hat * (1 - p_hat) / n + z2 / (4n^2)
        delta = z * sqrt(radicand)
        
        ci_lower = max(0, (center - delta) / denom)
        ci_upper = min(1, (center + delta) / denom)

        ci_lower_arr[i] = ci_lower
        ci_upper_arr[i] = ci_upper
    elseif CI_type == "jeffreys"
        p_hat = kde_cdf[i]
        # Jeffreys Beta posterior parameters
        alpha_post = n * p_hat + 0.5
        beta_post = n * (1 - p_hat) + 0.5
        posterior = Beta(alpha_post, beta_post)

        ci_lower_arr[i] = quantile(posterior, (1 - conf_level) / 2)
        ci_upper_arr[i] = quantile(posterior, 1 - (1 - conf_level) / 2)
    end
end

# function interpolate_threshold_crossing(x, y, threshold)
#     for i in 2:length(x)
#         if y[i-1] < threshold && y[i] >= threshold
#             x1, x2 = x[i-1], x[i]
#             y1, y2 = y[i-1], y[i]
#             return x1 + (threshold - y1) * (x2 - x1) / (y2 - y1)
#         end
#     end
#     return NaN  # no crossing found
# end

# inj_rate_at_ci_upper = interpolate_threshold_crossing(kde_x, ci_upper_arr, fracture_prob_threshold)
# inj_rate_at_ci_lower = interpolate_threshold_crossing(kde_x, ci_lower_arr, fracture_prob_threshold)
# inj_rate_at_cdf      = interpolate_threshold_crossing(kde_x, kde_cdf, fracture_prob_threshold)

# Threshold crossing index
idx_at_ci_lower = findfirst(x -> x >= fracture_prob_threshold, ci_lower_arr)
inj_rate_at_ci_lower = kde_x[idx_at_ci_lower]

idx_at_ci_upper = findfirst(x -> x >= fracture_prob_threshold, ci_upper_arr)
inj_rate_at_ci_upper = kde_x[idx_at_ci_upper]

idx_at_ci_cdf = findfirst(x -> x >= fracture_prob_threshold, kde_cdf)
inj_rate_at_cdf = kde_x[idx_at_ci_cdf]

# Plot 
fig = figure(figsize=(8, 6))
plot(kde_x, kde_cdf .* 100, label="CDF", linewidth=2)
fill_between(kde_x, ci_lower_arr * 100, ci_upper_arr * 100, color="gray", alpha=0.3, label=string(Int(conf_level*100)) * "% Confidence Interval")
axhline(y=fracture_prob_threshold * 100, color="red", linestyle="--", linewidth=1.5, label=string(Int(fracture_prob_threshold*100)) * "% Fracture Probability")

# Annotations
annotate("Injection Rate at " * string(Int(fracture_prob_threshold*100)) * "% Probability: $(round(inj_rate_at_cdf, digits=5)) m³/s",
    xy=(inj_rate_at_cdf, fracture_prob_threshold * 100),
    xytext=(inj_rate_at_cdf + 0.002, 2.5),
    arrowprops=Dict("arrowstyle" => "->"),
    fontsize=11)

annotate("Left CI: $(round(inj_rate_at_ci_lower, digits=5)) m³/s",
    xy=(inj_rate_at_ci_lower, fracture_prob_threshold * 100),
    xytext=(inj_rate_at_ci_lower + 0.002, 3.5),
    arrowprops=Dict("arrowstyle" => "->"),
    fontsize=11)

annotate("Right CI: $(round(inj_rate_at_ci_upper, digits=5)) m³/s",
    xy=(inj_rate_at_ci_upper, fracture_prob_threshold * 100),
    xytext=(inj_rate_at_ci_upper + 0.002, 1.5),
    arrowprops=Dict("arrowstyle" => "->"),
    fontsize=11)

# Zoom limits
if zoomed_in
    xlim(0.025, 0.045)
    ylim(0, 5)
end

xlabel("Average Injection Rate (m³/s)", fontsize=13)
ylabel("Fracture Probability (%)", fontsize=13)
title("Zoomed-In: Fracture Probability vs Average Injection Rate", fontsize=14)
legend(loc="upper left", fontsize=11)
grid(true)
tight_layout()

# Save figure
suffix = zoomed_in ? "_zoomin" : ""
filename = "fracture_prob$(suffix)_CI_$(CI_type)_CIlevel_$(conf_level)_samples$(num_s)_bandwidth$(optimal_bandwidth).png"

safesave(joinpath(plot_path, filename), fig)
close(fig)
