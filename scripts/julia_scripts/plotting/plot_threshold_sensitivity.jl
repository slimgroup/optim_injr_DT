#!/usr/bin/env julia
# Plot threshold sensitivity analysis results
# Reads summary data from threshold_sensitivity.jl output and generates plots

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using Printf
using ArgParse
using Dates

# PyCall setup (if needed)
if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
    include(joinpath(@__DIR__, "..", "..", "..", "src", "utils.jl"))
    setup_pycall()
end

# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

function parse_commandline()
    s = ArgParseSettings(description="Plot threshold sensitivity analysis results")
    
    @add_arg_table! s begin
        "--idx_num", "-i"
            help = "Sample index (default: 128)"
            arg_type = Int
            default = 128
        
        "--summary_path"
            help = "Path to summary JLD2 file (default: auto-detect from idx_num)"
            arg_type = String
            default = ""
        
        "--output_dir"
            help = "Output directory for plots (default: plotsdir)"
            arg_type = String
            default = ""
    end
    
    return parse_args(s)
end

# ─────────────────────────────────────────────────────────────────────────────
# Main plotting function
# ─────────────────────────────────────────────────────────────────────────────

function plot_threshold_sensitivity(summary_path::String, output_dir::String, idx_num::Int)
    # Load summary data
    if !isfile(summary_path)
        error("Summary file not found: $(summary_path)")
    end
    
    println("Loading summary from: $(summary_path)")
    data = JLD2.load(summary_path)
    
    # Extract data
    thresholds = data["thresholds"]
    final_inj_rates = data["final_inj_rates"]
    final_objs = data["final_objs"]
    final_obj_bases = data["final_obj_bases"]
    final_penalties = data["final_penalties"]
    final_pof_smooth = data["final_pof_smooth"]
    final_pof_hard = data["final_pof_hard"]
    final_cvar = data["final_cvar"]
    gamma_used = data["gamma_used"]
    eps_used = data["eps_used"]
    converged = data["converged"]
    
    # Extract risk parameters if available
    risk_params = get(data, "risk_params", Dict())
    use_pof = get(risk_params, "use_pof", false)
    use_cvar = get(risk_params, "use_cvar", false)
    eps_pof = get(risk_params, "eps_pof", nothing)
    gamma_cvar = get(risk_params, "gamma_cvar", nothing)  # Global default
    alpha_cvar = get(risk_params, "alpha_cvar", nothing)
    
    # Check for per-threshold gamma (from gamma table)
    per_threshold_gamma = get(risk_params, "per_threshold_gamma", nothing)
    per_threshold_eps = get(risk_params, "per_threshold_eps", nothing)
    
    println("Loaded $(length(thresholds)) threshold values")
    println("Threshold range: $(minimum(thresholds)) - $(maximum(thresholds)) MPa")
    println()
    
    # Print diagnostic information
    println("Data summary:")
    println("  Injection rates: min=$(minimum(final_inj_rates)), max=$(maximum(final_inj_rates))")
    println("  POF (smooth): min=$(minimum(final_pof_smooth)), max=$(maximum(final_pof_smooth))")
    println("  POF (hard): min=$(minimum(final_pof_hard)), max=$(maximum(final_pof_hard))")
    println("  CVaR: min=$(minimum(final_cvar)), max=$(maximum(final_cvar))")
    if per_threshold_gamma !== nothing
        println("  Using per-threshold gamma values (from gamma table)")
    elseif !isnothing(gamma_cvar)
        println("  Using global gamma = $(gamma_cvar)")
    end
    println()
    
    # Create output directory
    if isempty(output_dir)
        plot_path = plotsdir("DT_control", "exp_name=step1", "threshold_sensitivity")
    else
        plot_path = output_dir
    end
    mkpath(plot_path)
    
    println("Saving plots to: $(plot_path)")
    println()
    
    # ─────────────────────────────────────────────────────────────────────────
    # Plot 1: Injection rate vs threshold
    # ─────────────────────────────────────────────────────────────────────────
    fig, ax = subplots(figsize=(8, 6))
    ax.plot(thresholds, final_inj_rates, "o-", linewidth=2, markersize=8, color="C0")
    
    # Check if injection rates are all the same (might indicate hitting bound)
    if length(unique(final_inj_rates)) == 1
        ax.axhline(y=final_inj_rates[1], color="gray", linestyle="--", 
                   linewidth=1, alpha=0.5, label="Constant rate")
        ax.legend(fontsize=10)
        println("  ⚠️  Warning: All injection rates are identical ($(final_inj_rates[1]))")
        println("     This may indicate hitting an upper bound or optimization issue")
    end
    
    ax.set_xlabel("Pressure Threshold t (MPa)", fontsize=14)
    ax.set_ylabel("Optimal Injection Rate", fontsize=14)
    ax.set_title("Optimal Injection Rate vs Threshold\n(Sample $(idx_num))", fontsize=16)
    ax.grid(true, alpha=0.3)
    plt.tight_layout()
    safesave(joinpath(plot_path, "inj_rate_vs_threshold__sample=$(idx_num).png"), fig)
    close(fig)
    println("✓ Saved: inj_rate_vs_threshold__sample=$(idx_num).png")
    
    # ─────────────────────────────────────────────────────────────────────────
    # Plot 2: Objective vs threshold
    # ─────────────────────────────────────────────────────────────────────────
    fig, ax = subplots(figsize=(8, 6))
    ax.plot(thresholds, final_objs, "o-", linewidth=2, markersize=8, 
            label="Total Objective", color="C0")
    ax.plot(thresholds, final_obj_bases, "s--", linewidth=2, markersize=6, 
            label="Base Objective", color="C1")
    if any(!isnan, final_penalties)
        ax.plot(thresholds, final_penalties, "^:", linewidth=1.5, markersize=5, 
                label="Penalty", color="C2", alpha=0.7)
    end
    ax.set_xlabel("Pressure Threshold t (MPa)", fontsize=14)
    ax.set_ylabel("Objective Value", fontsize=14)
    ax.set_title("Objective vs Threshold\n(Sample $(idx_num))", fontsize=16)
    ax.legend(fontsize=12)
    ax.grid(true, alpha=0.3)
    plt.tight_layout()
    safesave(joinpath(plot_path, "objective_vs_threshold__sample=$(idx_num).png"), fig)
    close(fig)
    println("✓ Saved: objective_vs_threshold__sample=$(idx_num).png")
    
    # ─────────────────────────────────────────────────────────────────────────
    # Plot 3: POF vs threshold
    # ─────────────────────────────────────────────────────────────────────────
    fig, ax = subplots(figsize=(8, 6))
    ax.plot(thresholds, final_pof_smooth, "o-", linewidth=2, markersize=8, 
            label="POF (smooth)", color="C0")
    ax.plot(thresholds, final_pof_hard, "s--", linewidth=2, markersize=6, 
            label="POF (hard)", color="C1")
    
    # Add eps line if available
    if !isnothing(eps_pof) && use_pof
        ax.axhline(y=eps_pof, color="r", linestyle=":", linewidth=2, 
                   label="eps = $(eps_pof)", alpha=0.7)
    end
    
    ax.set_xlabel("Pressure Threshold t (MPa)", fontsize=14)
    ax.set_ylabel("Probability of Failure", fontsize=14)
    ax.set_title("POF vs Threshold\n(Sample $(idx_num))", fontsize=16)
    ax.legend(fontsize=12)
    ax.grid(true, alpha=0.3)
    plt.tight_layout()
    safesave(joinpath(plot_path, "pof_vs_threshold__sample=$(idx_num).png"), fig)
    close(fig)
    println("✓ Saved: pof_vs_threshold__sample=$(idx_num).png")
    
    # ─────────────────────────────────────────────────────────────────────────
    # Plot 4: CVaR vs threshold
    # ─────────────────────────────────────────────────────────────────────────
    fig, ax = subplots(figsize=(8, 6))
    ax.plot(thresholds, final_cvar, "o-", linewidth=2, markersize=8, color="C0")
    
    # Add gamma reference line(s)
    # If per-threshold gamma exists, plot them as points
    if per_threshold_gamma !== nothing && use_cvar
        gamma_values = [per_threshold_gamma[t] for t in thresholds]
        ax.plot(thresholds, gamma_values, "s:", linewidth=1.5, markersize=6, 
                label="gamma (per threshold)", color="r", alpha=0.7)
        ax.legend(fontsize=12)
    elseif !isnothing(gamma_cvar) && use_cvar
        ax.axhline(y=gamma_cvar, color="r", linestyle=":", linewidth=2, 
                   label="gamma = $(gamma_cvar)", alpha=0.7)
        ax.legend(fontsize=12)
    end
    
    ax.set_xlabel("Pressure Threshold t (MPa)", fontsize=14)
    ax.set_ylabel("CVaR", fontsize=14)
    ax.set_title("CVaR vs Threshold\n(Sample $(idx_num))", fontsize=16)
    ax.grid(true, alpha=0.3)
    plt.tight_layout()
    safesave(joinpath(plot_path, "cvar_vs_threshold__sample=$(idx_num).png"), fig)
    close(fig)
    println("✓ Saved: cvar_vs_threshold__sample=$(idx_num).png")
    
    # ─────────────────────────────────────────────────────────────────────────
    # Plot 5: Combined 2x2 view
    # ─────────────────────────────────────────────────────────────────────────
    fig, axes = subplots(2, 2, figsize=(14, 10))
    
    # Top-left: Injection rate
    axes[1,1].plot(thresholds, final_inj_rates, "o-", linewidth=2, markersize=8, color="C0")
    axes[1,1].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[1,1].set_ylabel("Optimal Injection Rate", fontsize=12)
    axes[1,1].set_title("Injection Rate", fontsize=14)
    axes[1,1].grid(true, alpha=0.3)
    
    # Top-right: Objective
    axes[1,2].plot(thresholds, final_objs, "o-", linewidth=2, markersize=8, 
                    label="Total", color="C0")
    axes[1,2].plot(thresholds, final_obj_bases, "s--", linewidth=1.5, markersize=5, 
                    label="Base", color="C1")
    axes[1,2].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[1,2].set_ylabel("Objective Value", fontsize=12)
    axes[1,2].set_title("Objective", fontsize=14)
    axes[1,2].legend(fontsize=10)
    axes[1,2].grid(true, alpha=0.3)
    
    # Bottom-left: POF
    axes[2,1].plot(thresholds, final_pof_smooth, "o-", linewidth=2, markersize=8, 
                    label="Smooth", color="C0")
    axes[2,1].plot(thresholds, final_pof_hard, "s--", linewidth=1.5, markersize=5, 
                    label="Hard", color="C1")
    if !isnothing(eps_pof) && use_pof
        axes[2,1].axhline(y=eps_pof, color="r", linestyle=":", linewidth=1.5, 
                          label="eps=$(eps_pof)", alpha=0.7)
    end
    axes[2,1].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[2,1].set_ylabel("POF", fontsize=12)
    axes[2,1].set_title("Probability of Failure", fontsize=14)
    axes[2,1].legend(fontsize=10)
    axes[2,1].grid(true, alpha=0.3)
    
    # Bottom-right: CVaR
    axes[2,2].plot(thresholds, final_cvar, "o-", linewidth=2, markersize=8, color="C0")
    if per_threshold_gamma !== nothing && use_cvar
        gamma_values = [per_threshold_gamma[t] for t in thresholds]
        axes[2,2].plot(thresholds, gamma_values, "s:", linewidth=1.5, markersize=5, 
                       label="gamma (per threshold)", color="r", alpha=0.7)
        axes[2,2].legend(fontsize=10)
    elseif !isnothing(gamma_cvar) && use_cvar
        axes[2,2].axhline(y=gamma_cvar, color="r", linestyle=":", linewidth=1.5, 
                           label="gamma=$(gamma_cvar)", alpha=0.7)
        axes[2,2].legend(fontsize=10)
    end
    axes[2,2].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[2,2].set_ylabel("CVaR", fontsize=12)
    axes[2,2].set_title("CVaR", fontsize=14)
    axes[2,2].grid(true, alpha=0.3)
    
    plt.suptitle("Threshold Sensitivity Analysis (Sample $(idx_num))", 
                 fontsize=16, y=0.995)
    plt.tight_layout(rect=[0, 0, 1, 0.99])
    safesave(joinpath(plot_path, "sensitivity_summary__sample=$(idx_num).png"), fig)
    close(fig)
    println("✓ Saved: sensitivity_summary__sample=$(idx_num).png")
    
    # ─────────────────────────────────────────────────────────────────────────
    # Plot 6: Risk metrics comparison (POF and CVaR together)
    # ─────────────────────────────────────────────────────────────────────────
    fig, ax1 = subplots(figsize=(10, 6))
    
    # POF on left y-axis
    color1 = "C0"
    ax1.set_xlabel("Pressure Threshold t (MPa)", fontsize=14)
    ax1.set_ylabel("POF", color=color1, fontsize=14)
    line1 = ax1.plot(thresholds, final_pof_smooth, "o-", linewidth=2, markersize=8, 
                      label="POF (smooth)", color=color1)
    line2 = ax1.plot(thresholds, final_pof_hard, "s--", linewidth=2, markersize=6, 
                      label="POF (hard)", color="C1")
    ax1.tick_params(axis="y", labelcolor=color1)
    ax1.grid(true, alpha=0.3)
    
    if !isnothing(eps_pof) && use_pof
        ax1.axhline(y=eps_pof, color="r", linestyle=":", linewidth=2, 
                    label="eps=$(eps_pof)", alpha=0.7)
    end
    
    # CVaR on right y-axis
    ax2 = ax1.twinx()
    color2 = "C2"
    ax2.set_ylabel("CVaR", color=color2, fontsize=14)
    line3 = ax2.plot(thresholds, final_cvar, "^:", linewidth=2, markersize=8, 
                      label="CVaR", color=color2)
    ax2.tick_params(axis="y", labelcolor=color2)
    
    # Add gamma reference
    if per_threshold_gamma !== nothing && use_cvar
        gamma_values = [per_threshold_gamma[t] for t in thresholds]
        ax2.plot(thresholds, gamma_values, "s:", linewidth=1.5, markersize=6, 
                 label="gamma (per threshold)", color="orange", alpha=0.7)
    elseif !isnothing(gamma_cvar) && use_cvar
        ax2.axhline(y=gamma_cvar, color="orange", linestyle=":", linewidth=2, 
                    label="gamma=$(gamma_cvar)", alpha=0.7)
    end
    
    # Combined legend
    lines = vcat(line1, line2, line3)
    labels = [l.get_label() for l in lines]
    ax1.legend(lines, labels, loc="upper left", fontsize=11)
    
    ax1.set_title("Risk Metrics vs Threshold\n(Sample $(idx_num))", fontsize=16)
    plt.tight_layout()
    safesave(joinpath(plot_path, "risk_metrics_vs_threshold__sample=$(idx_num).png"), fig)
    close(fig)
    println("✓ Saved: risk_metrics_vs_threshold__sample=$(idx_num).png")
    
    println()
    println("=" ^ 80)
    println("All plots saved successfully!")
    println("=" ^ 80)
    println("Output directory: $(plot_path)")
    println()
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    args = parse_commandline()
    idx_num = args["idx_num"]
    
    # Determine summary file path
    summary_path = args["summary_path"]
    if isempty(summary_path)
        summary_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                               "summary__sample=$(idx_num).jld2")
    end
    
    # Determine output directory
    output_dir = args["output_dir"]
    
    println("=" ^ 80)
    println("Threshold Sensitivity Plotting")
    println("=" ^ 80)
    println("Sample index: $(idx_num)")
    println("Summary file: $(summary_path)")
    println()
    
    plot_threshold_sensitivity(summary_path, output_dir, idx_num)
end

main()

