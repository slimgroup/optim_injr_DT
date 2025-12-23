# Advanced POF vs CVaR comparison plots
# Addresses the issue that POF and CVaR have different units/scales

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using Printf

# Configuration
sample_num = 128
data_root = datadir("DT_control", "exp_name=step1", "threshold_sensitivity")
plot_root = plotsdir("DT_control", "exp_name=step1", "threshold_sensitivity")

# Expected thresholds
thresholds = [2.0, 3.0, 4.0, 5.0, 6.0]

println("=" ^ 80)
println("Advanced POF vs CVaR Comparison")
println("=" ^ 80)
println()

# Load data (same as before)
pof_results = Dict{Float64, Dict}()
cvar_results = Dict{Float64, Dict}()

# Load POF results - each file may contain multiple thresholds
for i in 1:5
    summary_file1 = joinpath(data_root, "summary_POF_sample=$(sample_num)_#$i.jld2")
    summary_file2 = joinpath(data_root, "summary_POF__sample=$(sample_num)_#$i.jld2")
    summary_file = isfile(summary_file1) ? summary_file1 : (isfile(summary_file2) ? summary_file2 : nothing)
    
    if summary_file !== nothing && isfile(summary_file)
        data = JLD2.load(summary_file)
        if haskey(data, "thresholds") && length(data["thresholds"]) > 0
            # Each file may contain multiple thresholds - load all of them
            for (idx, thresh) in enumerate(data["thresholds"])
                if !(thresh in keys(pof_results))  # Only load if not already loaded
                    pof_results[thresh] = Dict(
                        "pof_smooth" => data["final_pof_smooth"][idx],
                        "pof_hard" => data["final_pof_hard"][idx],
                        "cvar" => data["final_cvar"][idx],
                        "inj_rate" => data["final_inj_rates"][idx]
                    )
                    println("  ✓ Loaded POF threshold=$(thresh) from $summary_file")
                end
            end
        end
    end
end

# Load CVaR results - each file may contain multiple thresholds
for i in 1:5
    summary_file1 = joinpath(data_root, "summary_CVaR_sample=$(sample_num)_#$i.jld2")
    summary_file2 = joinpath(data_root, "summary_CVaR__sample=$(sample_num)_#$i.jld2")
    summary_file = isfile(summary_file1) ? summary_file1 : (isfile(summary_file2) ? summary_file2 : nothing)
    
    if summary_file !== nothing && isfile(summary_file)
        data = JLD2.load(summary_file)
        if haskey(data, "thresholds") && length(data["thresholds"]) > 0
            for (idx, thresh) in enumerate(data["thresholds"])
                if !(thresh in keys(cvar_results))  # Only load if not already loaded
                    cvar_results[thresh] = Dict(
                        "cvar" => data["final_cvar"][idx],
                        "pof_smooth" => data["final_pof_smooth"][idx],
                        "pof_hard" => data["final_pof_hard"][idx],
                        "inj_rate" => data["final_inj_rates"][idx]
                    )
                    println("  ✓ Loaded CVaR threshold=$(thresh) from $summary_file")
                end
            end
        end
    end
end

# Fill missing from merged files (check archive first)
expected_thresholds = [2.0, 3.0, 4.0, 5.0, 6.0]
missing_cvar = setdiff(expected_thresholds, keys(cvar_results))
missing_pof = setdiff(expected_thresholds, keys(pof_results))

# Try main directory first, then archive
if !isempty(missing_cvar)
    merged_file = joinpath(data_root, "summary__CVaR__sample=$(sample_num).jld2")
    if isfile(merged_file)
        println("  Extracting missing CVaR thresholds from merged summary: $missing_cvar")
        try
            merged_data = JLD2.load(merged_file)
            for thresh in missing_cvar
                idx = findfirst(x -> abs(x - thresh) < 1e-6, merged_data["thresholds"])
                if idx !== nothing && !(thresh in keys(cvar_results))
                    cvar_results[thresh] = Dict(
                        "cvar" => merged_data["final_cvar"][idx],
                        "pof_smooth" => merged_data["final_pof_smooth"][idx],
                        "pof_hard" => merged_data["final_pof_hard"][idx],
                        "inj_rate" => merged_data["final_inj_rates"][idx]
                    )
                    println("    ✓ Extracted CVaR threshold=$(thresh) MPa")
                end
            end
        catch e
            println("  ⚠️  Error loading merged CVaR summary: $e")
        end
    end
end

if !isempty(missing_pof)
    merged_file = joinpath(data_root, "summary__POF__sample=$(sample_num).jld2")
    if isfile(merged_file)
        println("  Extracting missing POF thresholds from merged summary: $missing_pof")
        try
            merged_data = JLD2.load(merged_file)
            for thresh in missing_pof
                idx = findfirst(x -> abs(x - thresh) < 1e-6, merged_data["thresholds"])
                if idx !== nothing && !(thresh in keys(pof_results))
                    pof_results[thresh] = Dict(
                        "pof_smooth" => merged_data["final_pof_smooth"][idx],
                        "pof_hard" => merged_data["final_pof_hard"][idx],
                        "cvar" => merged_data["final_cvar"][idx],
                        "inj_rate" => merged_data["final_inj_rates"][idx]
                    )
                    println("    ✓ Extracted POF threshold=$(thresh) MPa")
                end
            end
        catch e
            println("  ⚠️  Error loading merged POF summary: $e")
        end
    end
end

# Extract data
all_thresholds = sort(collect(union(keys(pof_results), keys(cvar_results))))
common_thresholds = sort(collect(intersect(keys(pof_results), keys(cvar_results))))

if length(common_thresholds) == 0
    error("No common thresholds found!")
end

sorted_thresholds = common_thresholds
pof_smooth = [pof_results[t]["pof_smooth"] for t in sorted_thresholds]
pof_hard = [pof_results[t]["pof_hard"] for t in sorted_thresholds]
cvar_vals = [cvar_results[t]["cvar"] for t in sorted_thresholds]
inj_rates_pof = [pof_results[t]["inj_rate"] for t in sorted_thresholds]
inj_rates_cvar = [cvar_results[t]["inj_rate"] for t in sorted_thresholds]

# Compute comparison metrics
# CVaR/POF ratio (shows how much more conservative CVaR is)
cvar_pof_ratio = cvar_vals ./ pof_hard

# Relative changes (normalized to first threshold)
pof_rel_change = (pof_hard .- pof_hard[1]) ./ pof_hard[1]
cvar_rel_change = (cvar_vals .- cvar_vals[1]) ./ cvar_vals[1]

# Normalized values (0-1 scale)
pof_normalized = (pof_hard .- minimum(pof_hard)) ./ (maximum(pof_hard) - minimum(pof_hard))
cvar_normalized = (cvar_vals .- minimum(cvar_vals)) ./ (maximum(cvar_vals) - minimum(cvar_vals))

println()
println("Data summary:")
println("  Thresholds: ", sorted_thresholds)
println("  POF (hard): ", pof_hard)
println("  CVaR: ", cvar_vals)
println("  CVaR/POF ratio: ", cvar_pof_ratio)
println()

mkpath(plot_root)

# Plot 1: CVaR/POF Ratio (shows how much more conservative CVaR is)
fig, ax = subplots(figsize=(10, 6))
ax.plot(sorted_thresholds, cvar_pof_ratio, "o-", linewidth=2.5, markersize=10, 
        label="CVaR / POF", color="#d62728", alpha=0.8)
ax.axhline(1.0, linestyle="--", linewidth=2, color="gray", alpha=0.5, label="Equal (1.0)")
ax.set_xlabel("Pressure Threshold (MPa)", fontsize=14, fontweight="bold")
ax.set_ylabel("CVaR / POF Ratio", fontsize=14, fontweight="bold")
ax.set_title("CVaR/POF Ratio vs Threshold\n(Higher ratio = CVaR more conservative)", 
             fontsize=16, fontweight="bold")
ax.legend(fontsize=12, loc="best", framealpha=0.9)
ax.grid(true, alpha=0.3, linestyle="--")

# Add annotations
for (i, t) in enumerate(sorted_thresholds)
    ax.annotate(@sprintf("%.2f", cvar_pof_ratio[i]), 
                (t, cvar_pof_ratio[i]), 
                textcoords="offset points", xytext=(0,10), ha="center", 
                fontsize=9, color="#d62728")
end

plt.tight_layout()
plot_file = joinpath(plot_root, "cvar_pof_ratio_sample=$(sample_num).png")
safesave(plot_file, fig)
close(fig)
println("✓ Saved: $plot_file")

# Plot 2: Relative Change Comparison (normalized to first threshold)
fig, ax = subplots(figsize=(10, 6))
ax.plot(sorted_thresholds, pof_rel_change .* 100, "o-", linewidth=2.5, markersize=10, 
        label="POF (relative change %)", color="#1f77b4", alpha=0.8)
ax.plot(sorted_thresholds, cvar_rel_change .* 100, "^-", linewidth=2.5, markersize=10, 
        label="CVaR (relative change %)", color="#ff7f0e", alpha=0.8)
ax.axhline(0.0, linestyle="--", linewidth=2, color="gray", alpha=0.5)
ax.set_xlabel("Pressure Threshold (MPa)", fontsize=14, fontweight="bold")
ax.set_ylabel("Relative Change (%)", fontsize=14, fontweight="bold")
ax.set_title("Relative Change vs Threshold\n(Normalized to first threshold)", 
             fontsize=16, fontweight="bold")
ax.legend(fontsize=12, loc="best", framealpha=0.9)
ax.grid(true, alpha=0.3, linestyle="--")
plt.tight_layout()
plot_file = joinpath(plot_root, "relative_change_comparison_sample=$(sample_num).png")
safesave(plot_file, fig)
close(fig)
println("✓ Saved: $plot_file")

# Plot 3: Normalized Comparison (both on 0-1 scale)
fig, ax = subplots(figsize=(10, 6))
ax.plot(sorted_thresholds, pof_normalized, "o-", linewidth=2.5, markersize=10, 
        label="POF (normalized 0-1)", color="#1f77b4", alpha=0.8)
ax.plot(sorted_thresholds, cvar_normalized, "^-", linewidth=2.5, markersize=10, 
        label="CVaR (normalized 0-1)", color="#ff7f0e", alpha=0.8)
ax.set_xlabel("Pressure Threshold (MPa)", fontsize=14, fontweight="bold")
ax.set_ylabel("Normalized Value (0-1)", fontsize=14, fontweight="bold")
ax.set_title("Normalized Comparison (0-1 Scale)\nPOF vs CVaR", 
             fontsize=16, fontweight="bold")
ax.legend(fontsize=12, loc="best", framealpha=0.9)
ax.grid(true, alpha=0.3, linestyle="--")
plt.tight_layout()
plot_file = joinpath(plot_root, "normalized_comparison_sample=$(sample_num).png")
safesave(plot_file, fig)
close(fig)
println("✓ Saved: $plot_file")

# Plot 4: Dual Y-axis comparison (proper scale for each)
fig, ax1 = subplots(figsize=(10, 6))
color1 = "C0"
ax1.set_xlabel("Pressure Threshold (MPa)", fontsize=14, fontweight="bold")
ax1.set_ylabel("POF", color=color1, fontsize=14, fontweight="bold")
line1 = ax1.plot(sorted_thresholds, pof_hard, "o-", linewidth=2.5, markersize=10, 
                 label="POF (hard)", color=color1)
ax1.tick_params(axis="y", labelcolor=color1)
ax1.grid(true, alpha=0.3, linestyle="--")

ax2 = ax1.twinx()
color2 = "C1"
ax2.set_ylabel("CVaR", color=color2, fontsize=14, fontweight="bold")
line2 = ax2.plot(sorted_thresholds, cvar_vals, "^-", linewidth=2.5, markersize=10, 
                 label="CVaR", color=color2)
ax2.tick_params(axis="y", labelcolor=color2)

# Combined legend
lines = vcat(line1, line2)
labels = [l.get_label() for l in lines]
ax1.legend(lines, labels, loc="upper left", fontsize=12, framealpha=0.9)

ax1.set_title("POF vs CVaR (Dual Y-axis)\n(Sample #$(sample_num))", 
              fontsize=16, fontweight="bold")
plt.tight_layout()
plot_file = joinpath(plot_root, "dual_axis_comparison_sample=$(sample_num).png")
safesave(plot_file, fig)
close(fig)
println("✓ Saved: $plot_file")

# Plot 5: Optimized Injection Rate Comparison
fig, ax = subplots(figsize=(10, 6))
ax.plot(sorted_thresholds, inj_rates_pof, "o-", linewidth=2.5, markersize=10, 
        label="POF-optimized", color="#2ca02c", alpha=0.8)
ax.plot(sorted_thresholds, inj_rates_cvar, "^-", linewidth=2.5, markersize=10, 
        label="CVaR-optimized", color="#d62728", alpha=0.8)
ax.set_xlabel("Pressure Threshold (MPa)", fontsize=14, fontweight="bold")
ax.set_ylabel("Optimal Injection Rate", fontsize=14, fontweight="bold")
ax.set_title("Optimal Injection Rate: POF vs CVaR\n(Sample #$(sample_num))", 
             fontsize=16, fontweight="bold")
ax.legend(fontsize=12, loc="best", framealpha=0.9)
ax.grid(true, alpha=0.3, linestyle="--")

# Add annotations
for (i, t) in enumerate(sorted_thresholds)
    ax.annotate(@sprintf("%.4f", inj_rates_pof[i]), 
                (t, inj_rates_pof[i]), 
                textcoords="offset points", xytext=(0,10), ha="center", 
                fontsize=9, color="#2ca02c")
    ax.annotate(@sprintf("%.4f", inj_rates_cvar[i]), 
                (t, inj_rates_cvar[i]), 
                textcoords="offset points", xytext=(0,-15), ha="center", 
                fontsize=9, color="#d62728")
end

plt.tight_layout()
plot_file = joinpath(plot_root, "inj_rate_comparison_advanced_sample=$(sample_num).png")
safesave(plot_file, fig)
close(fig)
println("✓ Saved: $plot_file")

println()
println("=" ^ 80)
println("All advanced comparison plots saved to: $plot_root")
println("=" ^ 80)

