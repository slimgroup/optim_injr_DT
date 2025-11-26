# This script compares the injection rate distribution from a full dataset of 128 samples 
# against the average distribution from 10 trials of 64 samples each, 
# using histograms and kernel density estimates (KDEs).

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using StatsBase
using Interpolations

num_trials = 10
sample_size = 64
num_bins = 75

# Define global bin edges using full dataset
global_bin_edges = range(minimum(injr_dist), stop=maximum(injr_dist), length=num_bins+1)
bin_width = global_bin_edges[2] - global_bin_edges[1]
bin_centers = (global_bin_edges[1:end-1] .+ global_bin_edges[2:end]) ./ 2

# --- Collect 10 trials of 64-sample draws ---
samples_matrix = zeros(sample_size, num_trials)
for i in 1:num_trials
    samples_matrix[:, i] .= sample(injr_dist, sample_size; replace=true)
end

# --- Average histogram from trials ---
hist_accum = zeros(length(global_bin_edges) - 1)
for i in 1:num_trials
    counts, _ = hist(samples_matrix[:, i], global_bin_edges; density=false)
    hist_accum .+= counts
end
avg_hist = hist_accum ./ num_trials

# --- Averaged sample (mean at each position across 10 trials) ---
avg_sample = mean(samples_matrix, dims=2)[:, 1]

# --- Histogram and KDE from full 128 samples ---
full_counts, _ = hist(injr_dist, global_bin_edges; density=false)
kde_full = kde(injr_dist; bandwidth=optimal_bandwidth)

kde_x = range(minimum(injr_dist), stop=maximum(injr_dist), length=2048)
kde_accum = zeros(length(kde_x))

for i in 1:num_trials
    kde_i = kde(samples_matrix[:, i]; bandwidth=optimal_bandwidth)
    interp_i = LinearInterpolation(kde_i.x, kde_i.density, extrapolation_bc=Line())
    kde_accum .+= interp_i.(kde_x)
end

kde_avg = kde_accum ./ num_trials

# Scale both KDEs to match histogram frequency
scaled_kde_full = kde_full.density .* length(injr_dist) .* bin_width
scaled_kde_avg = kde_avg .* length(avg_sample)  .* bin_width 

# --- Plotting ---
fig = figure(figsize=(10, 6))

# Full 128-sample histogram
bar(bin_centers, full_counts; width=bin_width, alpha=0.5, color="#4A90E2",
    edgecolor="#1F497D", label="Full 128 Samples")

# Averaged histogram (from 10 trials)
bar(bin_centers, avg_hist; width=bin_width, alpha=0.5, color="#F5A623",
    edgecolor="#C87E00", label="Average Histogram (10 Trials of 64 Samples)")

# KDE: Full 128 samples
plot(kde_full.x, scaled_kde_full, color="#D9534F", linewidth=2.5, label="KDE (Full 128 Samples)")

plot(kde_x, scaled_kde_avg, linestyle="--", linewidth=2.5, color="#F39C12", label="Avg KDE (10x 64 Samples)")

# Final plot settings
title("Injection Rate Distribution: Full vs Averaged 64-Sample KDE", fontsize=18, fontweight="bold")
xlabel("Average Injection Rate (m³/s)", fontsize=16, fontweight="bold")
ylabel("Frequency", fontsize=16, fontweight="bold")
legend(fontsize=14, frameon=false)
xticks(fontsize=14, fontweight="bold")
yticks(fontsize=14, fontweight="bold")

ax = gca()
ax.spines["top"].set_visible(false)
ax.spines["right"].set_visible(false)
ax.tick_params(axis="y", colors="black")
ax.minorticks_on()

grid(color="#AAAAAA", linestyle="--", linewidth=0.5, alpha=0.7)
tight_layout()

filename = "injection_distribution_avg64_vs_full128.png"
safesave(joinpath(plot_path, filename), fig)
close(fig)



using Statistics, KernelDensity, Distributions

## Confidence interval settings
CI_type = "wald"
fracture_prob_threshold = 0.01  # 1%
conf_level = 0.99  # 99% confidence level
num_sample_kde = 16000
z = quantile(Normal(), 1 - (1 - conf_level) / 2)

## Average over 10 trials of 64 samples
sample_size = 64
# samples_matrix = ...  # your existing 64×10 matrix of injection rate samples

# Average KDE over trials (as before)
kde_x = range(minimum(injr_dist), stop=maximum(injr_dist), length=num_sample_kde)
stp = kde_x[2] - kde_x[1]
kde_accum = zeros(length(kde_x))

for i in 1:10
    kde_i = kde(samples_matrix[:, i]; bandwidth=optimal_bandwidth)
    interp_i = LinearInterpolation(kde_i.x, kde_i.density, extrapolation_bc=Line())
    kde_accum .+= interp_i.(kde_x)
end

kde_avg = kde_accum ./ 10

kde_cdf = cumsum(kde_avg) * stp

## Confidence Interval
ci_lower_arr = zeros(num_sample_kde)
ci_upper_arr = zeros(num_sample_kde)

n = 64  # n = 64 for each trial

for i in 1:num_sample_kde
    p_hat = kde_cdf[i]
    if CI_type == "wald"
        se = sqrt(p_hat * (1 - p_hat) / n)
        ci_lower_arr[i] = max(0.0, p_hat - z * se)
        ci_upper_arr[i] = min(1.0, p_hat + z * se)
    else
        z2 = z^2
        denom = 1 + z2 / n
        center = p_hat + z2 / (2n)
        radicand = p_hat * (1 - p_hat) / n + z2 / (4n^2)
        delta = z * sqrt(radicand)
        
        ci_lower_arr[i] = max(0, (center - delta) / denom)
        ci_upper_arr[i] = min(1, (center + delta) / denom)
    end
end

## Threshold crossing points
idx_at_ci_lower = findfirst(x -> x >= fracture_prob_threshold, ci_lower_arr)
inj_rate_at_ci_lower = kde_x[idx_at_ci_lower]

idx_at_ci_upper = findfirst(x -> x >= fracture_prob_threshold, ci_upper_arr)
inj_rate_at_ci_upper = kde_x[idx_at_ci_upper]

idx_at_ci_cdf = findfirst(x -> x >= fracture_prob_threshold, kde_cdf)
inj_rate_at_cdf = kde_x[idx_at_ci_cdf]

## Plot
fig = figure(figsize=(8, 6))
plot(kde_x, kde_cdf .* 100, label="CDF", linewidth=2)
fill_between(kde_x, ci_lower_arr * 100, ci_upper_arr * 100,
             color="gray", alpha=0.3, label="$(Int(conf_level * 100))% Confidence Interval")
axhline(y=fracture_prob_threshold * 100, color="red", linestyle="--", linewidth=1.5,
        label="$(Int(fracture_prob_threshold * 100))% Fracture Probability")

# Annotations
annotate("Injection Rate at 1% Probability: $(round(inj_rate_at_cdf, digits=5)) m³/s",
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

xlim(0.025, 0.045)
ylim(0, 5)
xlabel("Average Injection Rate (m³/s)", fontsize=13)
ylabel("Fracture Probability (%)", fontsize=13)
title("Zoomed-In: Fracture Probability vs Average Injection Rate (64-sample CDF)", fontsize=14)
legend(loc="upper left", fontsize=11)
grid(true)
tight_layout()

# Save
filename = "fracture_prob_zoomin_CI_$(CI_type)_average_samples64_bandwidth$(optimal_bandwidth).png"
safesave(joinpath(plot_path, filename), fig)
close(fig)

