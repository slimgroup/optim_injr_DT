#!/usr/bin/env julia
# ─────────────────────────────────────────────────────────────────────────────
# Paper figure: Permeability ensemble statistics
# Shows: (a) Ground truth (sample 2000), (b) Ensemble mean, (c) Ensemble std
# All 2000 permeability realizations from wise_perm_models_2000_new.jld2
# ─────────────────────────────────────────────────────────────────────────────

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using PyPlot
using PyCall
using Statistics
using Dates
using Printf

include(srcdir("utils.jl"))
setup_pycall()
@pyimport cmasher

# ─────────────────────────────────────────────────────────────────────────────
# Domain parameters
const N_GRID = (512, 1, 256)
const D_CELL = (6.25, 100.0, 6.25)
const H_TOP  = 0.0
const MD     = 9.869232667160131e-16   # millidarcy → m²
const GROUND_TRUTH_IDX = 2000

# ─────────────────────────────────────────────────────────────────────────────
# Output directory
out_dir = plotsdir("paper_figures")
mkpath(out_dir)

# ─────────────────────────────────────────────────────────────────────────────
# Load permeability data
println("Loading permeability data (may take a moment for 2 GB file)...")
perm_path = datadir("geo/wise_perm_models_2000_new.jld2")
perm_data = JLD2.load(perm_path)
BroadK    = perm_data["BroadK"]   # (2000, 512, 256)
N_samples = size(BroadK, 1)
println("Loaded $N_samples permeability realizations of size $(size(BroadK, 2)) × $(size(BroadK, 3))")

# ─────────────────────────────────────────────────────────────────────────────
# Compute ensemble statistics in log₁₀ space (natural for log-normal perm)
println("Computing ensemble statistics in log₁₀(K [mD]) space...")

logK_all = log10.(BroadK)               # (2000, 512, 256)
logK_mean = dropdims(mean(logK_all; dims=1); dims=1)  # (512, 256)
logK_std  = dropdims( std(logK_all; dims=1); dims=1)  # (512, 256)

# Ground truth
logK_gt = log10.(BroadK[GROUND_TRUTH_IDX, :, :])

println("  Mean range:  [$(minimum(logK_mean)), $(maximum(logK_mean))]")
println("  Std range:   [$(minimum(logK_std)), $(maximum(logK_std))]")
println("  GT range:    [$(minimum(logK_gt)), $(maximum(logK_gt))]")

# ─────────────────────────────────────────────────────────────────────────────
# Create 3-panel horizontal figure
println("Generating figure...")
rc("font", family="serif", size=13)
rc("xtick", labelsize=12)
rc("ytick", labelsize=12)
rc("axes", labelsize=14, titlesize=15)
rc("text", usetex=false)

fig, axes = subplots(1, 3, figsize=(16, 4.2), sharey=true)
extent = (0, (N_GRID[1]-1)*D_CELL[1], H_TOP+(N_GRID[3]-1)*D_CELL[3], H_TOP)

# Shared colorbar range for panels (a) and (b)
vmin_perm, vmax_perm = 0.0, 4.0

# ── Panel (a): Ground truth ──────────────────────────────────────────────
ax = axes[1]
im_gt = ax.imshow(transpose(logK_gt), vmin=vmin_perm, vmax=vmax_perm,
                  extent=extent, cmap="cet_rainbow4", aspect="auto")
ax.set_title("(a) Ground Truth (sample $GROUND_TRUTH_IDX)")
ax.set_xlabel("X [m]")
ax.set_ylabel("Depth [m]")

# ── Panel (b): Ensemble mean ─────────────────────────────────────────────
ax = axes[2]
im_mean = ax.imshow(transpose(logK_mean), vmin=vmin_perm, vmax=vmax_perm,
                    extent=extent, cmap="cet_rainbow4", aspect="auto")
ax.set_title("(b) Ensemble Mean (N=$N_samples)")
ax.set_xlabel("X [m]")

# ── Panel (c): Ensemble std ──────────────────────────────────────────────
ax = axes[3]
im_std = ax.imshow(transpose(logK_std),
                   extent=extent, cmap="cet_CET_L8", aspect="auto",
                   vmin=0, vmax=maximum(logK_std))
ax.set_title("(c) Ensemble Std Dev")
ax.set_xlabel("X [m]")

# Colorbars
fig.subplots_adjust(right=0.88, wspace=0.1, bottom=0.18, top=0.88)

# Shared colorbar for (a) and (b) - spans the left two panels
cbar_ax1 = fig.add_axes([0.125, 0.06, 0.49, 0.025])
clb1 = fig.colorbar(im_mean, cax=cbar_ax1, orientation="horizontal")
clb1.set_label("log₁₀(K [mD])", fontsize=12)
clb1.set_ticks([0, 1, 2, 3, 4])
clb1.set_ticklabels(["0 (1 mD)", "1 (10)", "2 (100)", "3 (1000)", "4 (10⁴)"])

# Separate colorbar for (c)
cbar_ax2 = fig.add_axes([0.645, 0.06, 0.23, 0.025])
clb2 = fig.colorbar(im_std, cax=cbar_ax2, orientation="horizontal")
clb2.set_label("Std Dev [log₁₀(mD)]", fontsize=12)

# Save
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
for ext in ["png", "pdf"]
    fname = joinpath(out_dir, "perm_ensemble_statistics_$(ts).$(ext)")
    savefig(fname, dpi=300, bbox_inches="tight")
    println("Saved: $fname")
end
close(fig)

# ─────────────────────────────────────────────────────────────────────────────
# Additional figure: difference between ground truth and mean
println("Generating ground truth – mean difference figure...")

diff_gt_mean = logK_gt .- logK_mean

fig2, ax2 = subplots(figsize=(10, 4))
im_diff = ax2.imshow(transpose(diff_gt_mean),
                     extent=extent, cmap="seismic", aspect="auto",
                     vmin=-2, vmax=2)
clb = fig2.colorbar(im_diff, fraction=0.046*(N_GRID[3]*D_CELL[3]/(N_GRID[1]*D_CELL[1])), pad=0.04)
clb.set_label("Δ log₁₀(K [mD])")
ax2.set_title("Ground Truth – Ensemble Mean")
ax2.set_xlabel("X [m]")
ax2.set_ylabel("Depth [m]")
plt.tight_layout()

for ext in ["png", "pdf"]
    fname = joinpath(out_dir, "perm_gt_minus_mean_$(ts).$(ext)")
    savefig(fname, dpi=300, bbox_inches="tight")
    println("Saved: $fname")
end
close(fig2)

println("Done!")
