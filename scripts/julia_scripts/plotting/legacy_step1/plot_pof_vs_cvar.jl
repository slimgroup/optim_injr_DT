#!/usr/bin/env julia
# Compare POF-only vs CVaR-only optimization results
# Demonstrates that CVaR control is more conservative (lower injection rates)

using Pkg
Pkg.activate(".")

# Set Julia depot path (same as submit scripts) - do this BEFORE loading Pkg
if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
    if !haskey(ENV, "JULIA_DEPOT_PATH")
        ENV["JULIA_DEPOT_PATH"] = get(ENV, "HOME", "") * "/julia-depot"
    end
    mkpath(ENV["JULIA_DEPOT_PATH"])
    println("Using Julia depot: $(ENV["JULIA_DEPOT_PATH"])")
end

# Only instantiate if DrWatson is not available (avoid unnecessary reinstalls)
try
    using DrWatson
catch
    println("DrWatson not found, running Pkg.instantiate()...")
    Pkg.instantiate()
    using DrWatson
end

@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using SlimPlotting
using ArgParse
using Printf

# PyCall setup (if needed)
if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
    include(joinpath(@__DIR__, "..", "..", "..", "src", "utils.jl"))
    setup_pycall()
end

"""
    plot_pof_vs_cvar_comparison(idx_num=128)

Load POF-only and CVaR-only summaries for a given sample index, and plot:
1) Injection rate vs threshold (POF control vs CVaR control)
2) Normalized risk: POF/eps and CVaR/gamma vs threshold

This demonstrates that CVaR control is more conservative (lower injection rates).
"""
function plot_pof_vs_cvar_comparison(; idx_num::Int=128)
    # ---------- paths ----------
    base_dir = datadir("DT_control", "exp_name=step1", "threshold_sensitivity")
    sum_pof_path  = joinpath(base_dir, "summary__POF__sample=$(idx_num).jld2")
    sum_cvar_path = joinpath(base_dir, "summary__CVaR__sample=$(idx_num).jld2")
    
    if !isfile(sum_pof_path)
        error("POF summary not found: $(sum_pof_path)\n" *
              "  Run POF-only optimization first with: --use_pof --use_cvar=false")
    end
    if !isfile(sum_cvar_path)
        error("CVaR summary not found: $(sum_cvar_path)\n" *
              "  Run CVaR-only optimization first with: --use_cvar --use_pof=false")
    end
    
    println("Loading POF summary:  $(sum_pof_path)")
    println("Loading CVaR summary: $(sum_cvar_path)")
    println()
    
    sum_pof  = JLD2.load(sum_pof_path)
    sum_cvar = JLD2.load(sum_cvar_path)
    
    # ---------- extract data ----------
    t_pof  = sum_pof["thresholds"]
    t_cvar = sum_cvar["thresholds"]
    
    if length(t_pof) != length(t_cvar)
        error("Threshold grids differ: POF has $(length(t_pof)) thresholds, CVaR has $(length(t_cvar))")
    end
    if !all(abs.(t_pof .- t_cvar) .< 1e-8)
        error("Threshold grids mismatch between POF and CVaR runs")
    end
    
    t = t_pof
    
    inj_pof  = sum_pof["final_inj_rates"]
    inj_cvar = sum_cvar["final_inj_rates"]
    
    pof_vals   = sum_pof["final_pof_hard"]      # Use hard POF for comparison
    eps_used   = sum_pof["eps_used"]
    cvar_vals  = sum_cvar["final_cvar"]
    gamma_used = sum_cvar["gamma_used"]
    
    # Normalize risk metrics by their thresholds
    # Handle potential division by zero or NaN
    norm_pof  = zeros(Float64, length(pof_vals))
    norm_cvar = zeros(Float64, length(cvar_vals))
    
    for i in eachindex(pof_vals)
        if !isnan(eps_used[i]) && eps_used[i] > 0
            norm_pof[i] = pof_vals[i] / eps_used[i]
        else
            norm_pof[i] = NaN
        end
        if !isnan(gamma_used[i]) && gamma_used[i] > 0
            norm_cvar[i] = cvar_vals[i] / gamma_used[i]
        elseif gamma_used[i] == 0.0
            # If gamma = 0, use absolute CVaR value (or mark as special)
            norm_cvar[i] = cvar_vals[i]
        else
            norm_cvar[i] = NaN
        end
    end
    
    # ---------- figure paths ----------
    plot_dir = plotsdir("DT_control", "exp_name=step1", "threshold_sensitivity")
    mkpath(plot_dir)
    
    println("=" ^ 80)
    println("POF vs CVaR Comparison (Sample $(idx_num))")
    println("=" ^ 80)
    println()
    
    # Print summary statistics
    println("Injection Rate Summary:")
    println("  POF control:  min=$(minimum(inj_pof)), max=$(maximum(inj_pof)), mean=$(mean(inj_pof))")
    println("  CVaR control: min=$(minimum(inj_cvar)), max=$(maximum(inj_cvar)), mean=$(mean(inj_cvar))")
    println("  Difference (POF - CVaR): mean=$(mean(inj_pof .- inj_cvar))")
    println()
    
    if mean(inj_pof) > mean(inj_cvar)
        println("✓ CVaR control is more conservative (lower injection rates)")
    else
        println("⚠️  Unexpected: POF control has lower injection rates")
    end
    println()
    
    # ---------- 1) Injection vs threshold ----------
    fig1, ax1 = subplots(figsize=(8, 6))
    ax1.plot(t, inj_pof,  "o-", linewidth=2, markersize=8, label="PoF control", color="C0")
    ax1.plot(t, inj_cvar, "s--", linewidth=2, markersize=8, label="CVaR control", color="C1")
    ax1.set_xlabel("Threshold t (MPa)", fontsize=14)
    ax1.set_ylabel("Optimal Injection Rate", fontsize=14)
    ax1.set_title("Injection Rate vs Threshold\nPoF vs CVaR Control (Sample $(idx_num))", fontsize=16)
    ax1.legend(fontsize=12)
    ax1.grid(true, alpha=0.3)
    plt.tight_layout()
    safesave(joinpath(plot_dir, "inj_vs_threshold__POF_vs_CVaR__sample=$(idx_num).png"), fig1)
    close(fig1)
    println("✓ Saved: inj_vs_threshold__POF_vs_CVaR__sample=$(idx_num).png")
    
    # ---------- 2) Risk utilization vs threshold ----------
    fig2, ax2 = subplots(figsize=(8, 6))
    ax2.plot(t, norm_pof,  "o-", linewidth=2, markersize=8, label="PoF / ε", color="C0")
    ax2.plot(t, norm_cvar, "s--", linewidth=2, markersize=8, label="CVaR / γ", color="C1")
    ax2.axhline(1.0, linestyle=":", linewidth=2, color="gray", alpha=0.7, label="Risk budget (1.0)")
    ax2.set_xlabel("Threshold t (MPa)", fontsize=14)
    ax2.set_ylabel("Risk Level / Budget", fontsize=14)
    ax2.set_title("Risk Utilization vs Threshold\nPoF vs CVaR Control (Sample $(idx_num))", fontsize=16)
    ax2.legend(fontsize=12)
    ax2.grid(true, alpha=0.3)
    plt.tight_layout()
    safesave(joinpath(plot_dir, "risk_utilization__POF_vs_CVaR__sample=$(idx_num).png"), fig2)
    close(fig2)
    println("✓ Saved: risk_utilization__POF_vs_CVaR__sample=$(idx_num).png")
    
    # ---------- 3) Combined comparison (2x2) ----------
    fig3, axes = subplots(2, 2, figsize=(14, 10))
    
    # Top-left: Injection rates
    axes[1,1].plot(t, inj_pof,  "o-", linewidth=2, markersize=8, label="PoF", color="C0")
    axes[1,1].plot(t, inj_cvar, "s--", linewidth=2, markersize=8, label="CVaR", color="C1")
    axes[1,1].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[1,1].set_ylabel("Injection Rate", fontsize=12)
    axes[1,1].set_title("Injection Rate", fontsize=14)
    axes[1,1].legend(fontsize=10)
    axes[1,1].grid(true, alpha=0.3)
    
    # Top-right: Risk utilization
    axes[1,2].plot(t, norm_pof,  "o-", linewidth=2, markersize=8, label="PoF/ε", color="C0")
    axes[1,2].plot(t, norm_cvar, "s--", linewidth=2, markersize=8, label="CVaR/γ", color="C1")
    axes[1,2].axhline(1.0, linestyle=":", linewidth=1.5, color="gray", alpha=0.7)
    axes[1,2].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[1,2].set_ylabel("Risk / Budget", fontsize=12)
    axes[1,2].set_title("Risk Utilization", fontsize=14)
    axes[1,2].legend(fontsize=10)
    axes[1,2].grid(true, alpha=0.3)
    
    # Bottom-left: PoF values
    pof_smooth_pof = sum_pof["final_pof_smooth"]
    pof_hard_pof   = sum_pof["final_pof_hard"]
    axes[2,1].plot(t, pof_smooth_pof, "o-", linewidth=2, markersize=8, label="PoF (smooth)", color="C0")
    axes[2,1].plot(t, pof_hard_pof,   "s--", linewidth=1.5, markersize=6, label="PoF (hard)", color="C0", alpha=0.7)
    if !all(isnan, eps_used) && any(eps_used .> 0)
        eps_val = eps_used[findfirst(x -> !isnan(x) && x > 0, eps_used)]
        axes[2,1].axhline(eps_val, linestyle=":", linewidth=1.5, color="r", alpha=0.7, label="ε=$(eps_val)")
    end
    axes[2,1].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[2,1].set_ylabel("PoF", fontsize=12)
    axes[2,1].set_title("PoF Values", fontsize=14)
    axes[2,1].legend(fontsize=10)
    axes[2,1].grid(true, alpha=0.3)
    
    # Bottom-right: CVaR values
    axes[2,2].plot(t, cvar_vals, "o-", linewidth=2, markersize=8, label="CVaR", color="C1")
    if !all(isnan, gamma_used) && any(gamma_used .>= 0)
        gamma_val = gamma_used[findfirst(x -> !isnan(x) && x >= 0, gamma_used)]
        if gamma_val > 0
            axes[2,2].axhline(gamma_val, linestyle=":", linewidth=1.5, color="r", alpha=0.7, label="γ=$(gamma_val)")
        end
    end
    axes[2,2].set_xlabel("Threshold t (MPa)", fontsize=12)
    axes[2,2].set_ylabel("CVaR", fontsize=12)
    axes[2,2].set_title("CVaR Values", fontsize=14)
    axes[2,2].legend(fontsize=10)
    axes[2,2].grid(true, alpha=0.3)
    
    plt.suptitle("PoF vs CVaR Control Comparison (Sample $(idx_num))", fontsize=16, y=0.995)
    plt.tight_layout(rect=[0, 0, 1, 0.99])
    safesave(joinpath(plot_dir, "pof_vs_cvar_comparison__sample=$(idx_num).png"), fig3)
    close(fig3)
    println("✓ Saved: pof_vs_cvar_comparison__sample=$(idx_num).png")
    
    println()
    println("=" ^ 80)
    println("All comparison plots saved successfully!")
    println("=" ^ 80)
    println("Output directory: $(plot_dir)")
    println()
end

# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

function parse_commandline()
    s = ArgParseSettings(description="Compare POF-only vs CVaR-only optimization results")
    
    @add_arg_table! s begin
        "--idx_num", "-i"
            help = "Sample index (default: 128)"
            arg_type = Int
            default = 128
    end
    
    return parse_args(s)
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    args = parse_commandline()
    idx_num = args["idx_num"]
    
    println("=" ^ 80)
    println("POF vs CVaR Comparison Plotting")
    println("=" ^ 80)
    println("Sample index: $(idx_num)")
    println()
    
    plot_pof_vs_cvar_comparison(idx_num=idx_num)
end

main()
