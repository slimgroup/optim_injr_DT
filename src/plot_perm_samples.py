#!/usr/bin/env python3
"""
Script to generate multi-panel permeability samples figure for paper
Shows 3 representative permeability realizations from the ensemble
Uses the same plotting style as optim_inject.jl
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib import rcParams
import h5py
from datetime import datetime
import os
import random
import colorcet as cc  # For cet_rainbow4 colormap

# Set up plotting style
rcParams['font.family'] = 'serif'
rcParams['xtick.labelsize'] = 12
rcParams['ytick.labelsize'] = 12

# Domain parameters (from optim_inject.jl)
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0

# millidarcy constant
md = 9.869232667160131e-16

# Paths
base_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data_path = os.path.join(base_path, "data")
plots_path = os.path.join(base_path, "plots", "DT_control", "exp_name=step1")
os.makedirs(plots_path, exist_ok=True)

# Load permeability data (JLD2 files are HDF5 compatible)
perm_path = os.path.join(data_path, "geo/wise_perm_models_2000_new.jld2")
print(f"Loading permeability data from: {perm_path}")
with h5py.File(perm_path, 'r') as f:
    print(f"Keys in file: {list(f.keys())}")
    BroadK = f['BroadK'][:]
print(f"BroadK shape: {BroadK.shape}")

# Load monitoring step 1 indices
monitoring_step = 1
state_path = os.path.join(data_path, f"state/Wise128_state_t{monitoring_step}_rtm1_broad_NL_SNR28.jld2")
print(f"Loading indices from: {state_path}")
with h5py.File(state_path, 'r') as f:
    print(f"Keys in state file: {list(f.keys())}")
    indices = f[f'idx_t{monitoring_step}'][:]
    # Convert to 0-based indexing for Python
    indices = indices.astype(int) - 1  # Julia uses 1-based indexing

print(f"Number of samples in monitoring step 1: {len(indices)}")
print(f"Indices range: {indices.min()+1} to {indices.max()+1} (1-based)")

# Randomly select 3 samples
random.seed(2025)
selected_sample_positions = sorted(random.sample(range(len(indices)), 3))
selected_perm_indices = [indices[i] for i in selected_sample_positions]

print(f"Selected sample positions (1-based): {[p+1 for p in selected_sample_positions]}")
print(f"Corresponding permeability indices (1-based): {[idx+1 for idx in selected_perm_indices]}")

# Calculate im_ratio (matching optim_inject.jl)
im_ratio = n[2] * d[2] / (n[0] * d[0])  # nz*dz / (nx*dx)

# Create multi-panel figure with larger panels
fig, axes = plt.subplots(1, 3, figsize=(18, 6), sharey=True)

for panel_idx, (sample_pos, perm_idx) in enumerate(zip(selected_sample_positions, selected_perm_indices)):
    # BroadK shape is (256, 512, 2000) in h5py (reversed from Julia's column-major order)
    # axis 0 = nz (256), axis 1 = nx (512), axis 2 = samples (2000)
    K = BroadK[:, :, perm_idx] * md
    logK = np.log10(K / md)  # Already (nz=256, nx=512) - matches Julia's post-transpose
    
    ax = axes[panel_idx]
    # extent = (left, right, bottom, top) for x and depth axes
    # Matching optim_inject.jl: extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h)
    im = ax.imshow(logK, vmin=0, vmax=4, 
                   extent=(0, (n[0]-1)*d[0], h+(n[2]-1)*d[2], h), 
                   cmap=cc.cm.rainbow4)  # cet_rainbow4 colormap
    
    ax.set_title(f"Realization {sample_pos+1}", fontsize=18)
    ax.set_xlabel("X [m]", fontsize=12)
    if panel_idx == 0:
        ax.set_ylabel("Depth [m]", fontsize=12)

# Add single colorbar for all panels
# Give more space to main panels, make colorbar shorter and thinner
fig.subplots_adjust(right=0.90, wspace=0.08)
cbar_ax = fig.add_axes([0.91, 0.30, 0.008, 0.4])  # [left, bottom, width, height]
clb = fig.colorbar(im, cax=cbar_ax)
clb.ax.set_title("Md", fontsize=12)
clb.set_ticks(np.log10([1, 10, 1000]))  # [0, 1, 3]
clb.set_ticklabels(["1", "1e1", "1e3"])  # Matching optim_inject.jl

# Note: tight_layout with colorbar axes can cause warnings, so we skip it
# The subplots_adjust above handles the layout

# Save figure (PNG only)
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
filename = os.path.join(plots_path, f"permeability_samples_{timestamp}.png")
plt.savefig(filename, dpi=300, bbox_inches="tight")
print(f"Saved figure to: {filename}")

plt.close(fig)
print("Done!")
