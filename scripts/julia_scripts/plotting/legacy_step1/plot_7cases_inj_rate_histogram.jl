#!/usr/bin/env julia
# Plot injection-rate histograms for the seven recovery cases.
# Follow the logic in plot_injr_distributions.jl.

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using Printf
using Dates

# ===================== Config =====================
const INJ_START = 0.0001  # Injection rate at the first schedule step
const NBINS = 30
const USE_LOGX = false

# Paths for the seven cases
cases = [
    ("gamma=0.01, alpha=0.02, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("gamma=0.01, alpha=0.05, sample=17", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.01__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=17/final.jld2"),
    ("gamma=0.02, alpha=0.01, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.01__gamma=0.02__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
    ("gamma=0.05, alpha=0.02, sample=42", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.02__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=42/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=1",  "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=1/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=21", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=21/final.jld2"),
    ("gamma=0.05, alpha=0.05, sample=64", "data/DT_control/exp_name=step1/CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=64/final.jld2"),
]

# Read the last nonzero injection rate
function last_nonzero_inj_rate(inj_rate_arr)
    col1 = vec(inj_rate_arr[:, 1])
    clean = filter(x -> isfinite(x) && !isnan(x), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? INJ_START : clean[idx]
end

println("=" ^ 80)
println("Reading injection-rate data for seven cases")
println("=" ^ 80)

# Collect data
last_nonzero_rates = Float64[]
averaged_rates = Float64[]
case_labels = String[]

for (desc, path) in cases
    if isfile(path)
        data = JLD2.load(path)
        inj_rate_arr = data["inj_rate_arr"]
        
        last_nonzero = last_nonzero_inj_rate(inj_rate_arr)
        avg_rate = (last_nonzero + INJ_START) / 2.0
        
        push!(last_nonzero_rates, last_nonzero)
        push!(averaged_rates, avg_rate)
        push!(case_labels, desc)
        
        println(@sprintf("%-50s: last=%.6f, avg=%.6f", desc, last_nonzero, avg_rate))
    else
        println(@sprintf("%-50s: FILE NOT FOUND", desc))
    end
end

if isempty(averaged_rates)
    error("No data files found")
end

# ===================== Plotting =====================
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
out_dir = "plots/DT_control/exp_name=step1/7cases_fix"
mkpath(out_dir)

# Plot 1: Histogram of last nonzero rates
fig, ax = subplots(figsize=(8, 6))
ax.hist(last_nonzero_rates, bins=NBINS, density=true, alpha=0.7, edgecolor="black")
ax.set_xlabel("Last Nonzero Injection Rate (m³/s)", fontsize=12)
ax.set_ylabel("Density", fontsize=12)
ax.set_title("Distribution of Last Nonzero Injection Rates\n(7 fixed cases)", fontsize=14)
ax.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
ax.axvline(mean(last_nonzero_rates), color="red", linestyle="--", linewidth=2, label=@sprintf("Mean: %.4f", mean(last_nonzero_rates)))
ax.legend()
tight_layout()
out_file1 = joinpath(out_dir, "histogram_last_nonzero_7cases_$ts.png")
savefig(out_file1, dpi=200)
close(fig)
println("Saved: $out_file1")

# Plot 2: Histogram of averaged rates (with inj_start)
fig, ax = subplots(figsize=(8, 6))
ax.hist(averaged_rates, bins=NBINS, density=true, alpha=0.7, edgecolor="black", color="green")
ax.set_xlabel("Averaged Injection Rate (m³/s)\n(last_nonzero + inj_start)/2", fontsize=12)
ax.set_ylabel("Density", fontsize=12)
ax.set_title("Distribution of Averaged Injection Rates\n(7 fixed cases, inj_start=0.0001)", fontsize=14)
ax.grid(true, linestyle="--", linewidth=0.5, alpha=0.5)
ax.axvline(mean(averaged_rates), color="red", linestyle="--", linewidth=2, label=@sprintf("Mean: %.4f", mean(averaged_rates)))
ax.legend()
tight_layout()
out_file2 = joinpath(out_dir, "histogram_averaged_7cases_$ts.png")
savefig(out_file2, dpi=200)
close(fig)
println("Saved: $out_file2")

# Plot 3: Bar plot comparing all 7 cases
fig, ax = subplots(figsize=(12, 6))
x_pos = 1:length(case_labels)
width = 0.35

bars1 = ax.bar(x_pos .- width/2, last_nonzero_rates, width, label="Last Nonzero", alpha=0.7)
bars2 = ax.bar(x_pos .+ width/2, averaged_rates, width, label="Averaged (with inj_start)", alpha=0.7, color="green")

ax.set_xlabel("Case", fontsize=12)
ax.set_ylabel("Injection Rate (m³/s)", fontsize=12)
ax.set_title("Injection Rates Comparison: 7 Fixed Cases", fontsize=14)
ax.set_xticks(x_pos)
ax.set_xticklabels(case_labels, rotation=45, ha="right", fontsize=9)
ax.legend()
ax.grid(true, linestyle="--", linewidth=0.5, alpha=0.5, axis="y")
tight_layout()
out_file3 = joinpath(out_dir, "barplot_comparison_7cases_$ts.png")
savefig(out_file3, dpi=200)
close(fig)
println("Saved: $out_file3")

println("\nDone. Generated 3 plots:")
println("  1. Histogram of last nonzero rates")
println("  2. Histogram of averaged rates")
println("  3. Bar plot comparison")

