#!/usr/bin/env julia
# Quick test script to check title positioning

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using PyPlot
using PyCall
@pyimport cmasher

# Constants
const N = (512, 1, 256)
const D = (6.25, 100.0, 6.25)
const H = 0.0

println("Generating test frame...")

rc("font", family="serif")
rc("xtick", labelsize=15)
rc("ytick", labelsize=15)

fig, axes = subplots(2, 1, figsize=(10, 8))
im_ratio = N[3] * D[3] / (N[1] * D[1])
extent = (0, (N[1]-1)*D[1], H+(N[3]-1)*D[3], H)

# Create dummy data (gradient for visualization)
safety_margin = ones(N[1], N[3]) .* 0.8  # uniform safe value
sat = zeros(N[1], N[3])
sat[240:260, 180:200] .= 0.5  # small saturation blob

# Top plot: Safety Margin
ax1 = axes[1]
np = pyimport("numpy")

vmin_margin = -0.1
vmax_margin = 1.0
n_negative = 23
n_positive = 233
red_colors = PyPlot.cm.Reds_r(np.linspace(0.0, 0.85, n_negative))
blue_colors = PyPlot.cm.Blues(np.linspace(0.0, 1.0, n_positive))
colors = vcat(red_colors, blue_colors)
cmap_margin = PyPlot.cm.colors.ListedColormap(colors)

im1 = ax1.imshow(transpose(safety_margin), extent=extent, cmap=cmap_margin, 
                 vmin=vmin_margin, vmax=vmax_margin)
clb1 = fig.colorbar(im1, ax=ax1, fraction=0.046*im_ratio, pad=0.04, extend="min")
clb1.ax.set_title("r", fontsize=14)
clb1.set_ticks([vmin_margin, 0.0, 0.5, 1.0])
clb1.set_ticklabels(["<0 (frac)", "0", "0.5", "1.0"])
ax1.set_ylabel("Depth[m]", fontsize=15)
ax1.set_title("Normalized Safety Margin  r = (p_frac - p) / p_frac", fontsize=14)
ax1.set_xticklabels([])

# Bottom plot: Saturation
ax2 = axes[2]
im2 = ax2.imshow(transpose(sat), vmin=0, vmax=1, extent=extent, cmap=cmasher.rainforest_r)
clb2 = fig.colorbar(im2, ax=ax2, fraction=0.046*im_ratio, pad=0.04)
clb2.set_ticks([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
ax2.set_xlabel("X[m]", fontsize=15)
ax2.set_ylabel("Depth[m]", fontsize=15)
ax2.set_title("Saturation", fontsize=14)

# Super title - bigger font, move to the right, less padding below
fig.suptitle("CVaR γ = 0.1, α = 0.01    t = 8 days", fontsize=18, fontweight="bold", 
             x=0.58, y=0.995, ha="center")

plt.tight_layout(rect=[0, 0, 1, 0.98], h_pad=1.5)

output_path = plotsdir("DT_control", "test_title_position.png")
# bbox_inches="tight" will crop the whitespace
savefig(output_path, dpi=150, bbox_inches="tight", pad_inches=0.1)
close(fig)

println("Test frame saved to: $output_path")
