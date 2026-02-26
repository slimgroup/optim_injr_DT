#!/usr/bin/env python
"""
Paper figure: Permeability ensemble statistics
Shows: (a) Ground truth (sample 2000), (b) Ensemble mean, (c) Ensemble std
Colorbars consistent with optim_inject.jl
"""
import os, sys
import numpy as np
import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import colorcet as cc

# ── Paths ──────────────────────────────────────────────────────────────────
BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.path.join(BASE, "data")
OUT_DIR  = os.path.join(BASE, "plots", "paper_figures")
os.makedirs(OUT_DIR, exist_ok=True)

# ── Domain ─────────────────────────────────────────────────────────────────
nx, nz = 512, 256
dx, dz = 6.25, 6.25
h = 0.0
GROUND_TRUTH_IDX = 1999   # 0-based (sample 2000 in Julia 1-based)
extent = (0, (nx-1)*dx, h+(nz-1)*dz, h)

# ── Load data ──────────────────────────────────────────────────────────────
perm_path = os.path.join(DATA_DIR, "geo", "wise_perm_models_2000_new.jld2")
print(f"Loading {perm_path} ...")
with h5py.File(perm_path, "r") as f:
    # HDF5 stores Julia (2000,512,256) as (256,512,2000) due to column-major
    raw = f["BroadK"][:]
print(f"  raw HDF5 shape: {raw.shape}")
BroadK = raw.transpose(2, 1, 0)   # → (2000, 512, 256)
print(f"  BroadK shape (reordered): {BroadK.shape}")

# ── Compute log10 statistics ──────────────────────────────────────────────
logK = np.log10(np.clip(BroadK, 1e-30, None))   # avoid log(0)
logK_gt   = logK[GROUND_TRUTH_IDX]               # (512, 256)
logK_mean = logK.mean(axis=0)                     # (512, 256)
logK_std  = logK.std(axis=0)                      # (512, 256)

print(f"  GT   range: [{logK_gt.min():.2f}, {logK_gt.max():.2f}]")
print(f"  Mean range: [{logK_mean.min():.2f}, {logK_mean.max():.2f}]")
print(f"  Std  range: [{logK_std.min():.3f}, {logK_std.max():.3f}]")

# ── Colormap (same as optim_inject.jl: "cet_rainbow4") ───────────────────
cmap_perm = cc.cm["rainbow4"]   # colorcet rainbow4

# ── 3-panel figure ────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 13,
    "axes.labelsize": 14,
    "axes.titlesize": 15,
    "xtick.labelsize": 12,
    "ytick.labelsize": 12,
})

fig, axes = plt.subplots(1, 3, figsize=(16.5, 4.5), sharey=True)

# Shared perm color range (matches optim_inject.jl: vmin=0, vmax=4)
vmin_p, vmax_p = 0, 4

# (a) Ground truth
im0 = axes[0].imshow(logK_gt.T, vmin=vmin_p, vmax=vmax_p,
                     extent=extent, cmap=cmap_perm, aspect="auto")
axes[0].set_title("(a)  Ground Truth")
axes[0].set_xlabel("X [m]")
axes[0].set_ylabel("Depth [m]")

# (b) Ensemble mean
im1 = axes[1].imshow(logK_mean.T, vmin=vmin_p, vmax=vmax_p,
                     extent=extent, cmap=cmap_perm, aspect="auto")
axes[1].set_title(f"(b)  Ensemble Mean  (N = {BroadK.shape[0]})")
axes[1].set_xlabel("X [m]")

# (c) Ensemble std
vmax_std = float(np.ceil(logK_std.max() * 10) / 10)   # round up
im2 = axes[2].imshow(logK_std.T, vmin=0, vmax=vmax_std,
                     extent=extent, cmap="cet_CET_L8", aspect="auto")
axes[2].set_title("(c)  Ensemble Std Dev")
axes[2].set_xlabel("X [m]")

# ── Colorbars (matching optim_inject.jl ticks) ───────────────────────────
fig.subplots_adjust(bottom=0.22, top=0.90, left=0.05, right=0.88, wspace=0.10)

# Shared colorbar for (a) and (b)
cax1 = fig.add_axes([0.05, 0.07, 0.52, 0.03])
clb1 = fig.colorbar(im1, cax=cax1, orientation="horizontal")
clb1.set_ticks(np.log10([1, 10, 1000]))
clb1.set_ticklabels(["1", "1e1", "1e3"])
clb1.set_label("log$_{10}$(K)  [mD]", fontsize=13)

# Colorbar for (c)
cax2 = fig.add_axes([0.62, 0.07, 0.25, 0.03])
clb2 = fig.colorbar(im2, cax=cax2, orientation="horizontal")
clb2.set_label("Std Dev  [log$_{10}$(mD)]", fontsize=13)

for ext in ["png", "pdf"]:
    fname = os.path.join(OUT_DIR, f"perm_ensemble_statistics.{ext}")
    fig.savefig(fname, dpi=300, bbox_inches="tight")
    print(f"Saved: {fname}")
plt.close(fig)

# ── Bonus: GT – Mean difference ──────────────────────────────────────────
fig2, ax2 = plt.subplots(figsize=(10, 4))
diff = logK_gt - logK_mean
im_d = ax2.imshow(diff.T, extent=extent, cmap="seismic", aspect="auto",
                  vmin=-2, vmax=2)
clb = fig2.colorbar(im_d, fraction=0.046*(nz*dz/(nx*dx)), pad=0.04)
clb.set_label("Δ log$_{10}$(K [mD])")
ax2.set_title("Ground Truth – Ensemble Mean")
ax2.set_xlabel("X [m]"); ax2.set_ylabel("Depth [m]")
plt.tight_layout()
for ext in ["png", "pdf"]:
    fname = os.path.join(OUT_DIR, f"perm_gt_minus_mean.{ext}")
    fig2.savefig(fname, dpi=300, bbox_inches="tight")
    print(f"Saved: {fname}")
plt.close(fig2)

print("Done!")
