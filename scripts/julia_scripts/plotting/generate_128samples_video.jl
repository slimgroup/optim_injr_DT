#!/usr/bin/env julia
# Generate video showing 128 permeability samples (first monitoring step)
# This creates a video that cycles through different permeability realizations
# to show the geological uncertainty - NO SIMULATION NEEDED
#
# Just visualize the permeability fields from the 128 posterior samples

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JutulDarcyRules
using PyPlot
using JLD2
using Printf
using Dates
using PyCall

# ─────────────────────────────────────────────────────────────────────────────
# Constants
const N = (512, 1, 256)  # Grid dimensions
const D = (6.25, 100.0, 6.25)  # Cell size (m)
const H = 0.0  # Top depth

# Number of permeability samples
const N_SAMPLES = 128

# ─────────────────────────────────────────────────────────────────────────────
# Create frame for video (just permeability) - matching optim_inject.jl style
function create_frame(K, sample_idx, actual_idx, output_path; n=N, d=D, h=H)
    
    rc("font", family="serif")
    rc("xtick", labelsize=15)
    rc("ytick", labelsize=15)
    
    fig, ax = subplots(figsize=(10, 5))
    im_ratio = n[3] * d[3] / (n[1] * d[1])
    extent = (0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h)
    
    # Plot log10 permeability (in mD)
    logK = log10.(K ./ JutulDarcyRules.md)  # Convert to mD and take log10
    
    # Use jet colormap (rainbow style matching optim_inject.jl)
    im = ax.imshow(transpose(logK), vmin=0, vmax=4, extent=extent, cmap="jet")
    
    clb = fig.colorbar(im, ax=ax, fraction=0.046*im_ratio, pad=0.04)
    clb.ax.set_title("Md", fontsize=15)
    # Set ticks at log10([1, 10, 1000]) = [0, 1, 3] - matching optim_inject.jl
    clb.set_ticks([0, 1, 3])
    clb.set_ticklabels(["1", "1e1", "1e3"])
    
    ax.set_xlabel("X[m]", fontsize=15)
    ax.set_ylabel("Depth[m]", fontsize=15)
    ax.set_title("Permeability Sample $sample_idx / $N_SAMPLES  (idx=$actual_idx)", 
                 fontsize=20, fontweight="bold")
    
    plt.tight_layout(pad=0.5)
    
    frame_file = joinpath(output_path, @sprintf("frame_%04d.png", sample_idx))
    savefig(frame_file, dpi=150, bbox_inches="tight")
    close(fig)
    
    return frame_file
end

# ─────────────────────────────────────────────────────────────────────────────
# Main function
function main()
    println("="^60)
    println("Generating 128-sample permeability video (NO simulation)")
    println("="^60)
    
    perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
    println("Loading permeability from: $perm_path")
    perm_data = JLD2.load(perm_path)
    BroadK = perm_data["BroadK"]
    println("Loaded $(size(BroadK, 1)) permeability samples")
    
    state_path = datadir("state/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2")
    println("Loading sample indices from: $state_path")
    state_data = JLD2.load(state_path)
    sample_indices = state_data["idx_t1"]
    println("Using $(length(sample_indices)) posterior samples")
    
    ts = Dates.format(now(), "yyyymmdd_HHMMSS")
    output_root = plotsdir("DT_control", "video_128perm_$(ts)")
    mkpath(output_root)
    println("Output directory: $output_root")
    
    frames_dir = joinpath(output_root, "frames")
    mkpath(frames_dir)
    
    println("\nGenerating frames for $(N_SAMPLES) permeability samples...")
    
    for s in 1:N_SAMPLES
        idx = sample_indices[s]
        K = BroadK[idx, :, :] * JutulDarcyRules.md
        
        create_frame(K, s, idx, frames_dir)
        
        if s % 20 == 0
            println("  Frame $s / $N_SAMPLES")
        end
    end
    
    println("\nFrames saved in: $frames_dir")
    println("Run 'python scripts/create_videos_from_frames.py' to create videos")
    println("\n" * "="^60)
    println("Frame generation complete!")
    println("Output directory: $output_root")
    println("="^60)
end

main()
