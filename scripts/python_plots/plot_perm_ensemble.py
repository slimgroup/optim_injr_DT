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
    "font.size": 22,
    "axes.labelsize": 24,
    "axes.titlesize": 30,
    "xtick.labelsize": 20,
    "ytick.labelsize": 20,
})

fig, axes = plt.subplots(1, 3, figsize=(21, 7), sharey=True)

vmin_p, vmax_p = 0, 4

im0 = axes[0].imshow(logK_gt.T, vmin=vmin_p, vmax=vmax_p,
                     extent=extent, cmap=cmap_perm, aspect="auto")
axes[0].set_xlabel("X [m]")
axes[0].set_ylabel("Depth [m]")

im1 = axes[1].imshow(logK_mean.T, vmin=vmin_p, vmax=vmax_p,
                     extent=extent, cmap=cmap_perm, aspect="auto")
axes[1].set_xlabel("X [m]")

vmax_std = float(np.ceil(logK_std.max() * 10) / 10)
im2 = axes[2].imshow(logK_std.T, vmin=0, vmax=vmax_std,
                     extent=extent, cmap="cet_CET_L8", aspect="auto")
axes[2].set_xlabel("X [m]")

fig.subplots_adjust(bottom=0.24, top=0.88, left=0.07, right=0.98, wspace=0.18)

pos0 = axes[0].get_position()
pos1 = axes[1].get_position()
pos2 = axes[2].get_position()

cbar_y = 0.06
cbar_h = 0.03

cax1 = fig.add_axes([pos0.x0, cbar_y, pos1.x1 - pos0.x0, cbar_h])
clb1 = fig.colorbar(im1, cax=cax1, orientation="horizontal")
clb1.set_ticks(np.log10([1, 10, 1000]))
clb1.set_ticklabels(["1", "1e1", "1e3"])
clb1.set_label("log$_{10}$(K)  [mD]", fontsize=22)

cax2 = fig.add_axes([pos2.x0, cbar_y, pos2.width, cbar_h])
clb2 = fig.colorbar(im2, cax=cax2, orientation="horizontal")
clb2.set_label("Std Dev  [log$_{10}$(mD)]", fontsize=22)

# Render to get accurate visual extents, then place titles centered over
# each subplot's full visual area (including ylabel/ticks)
fig.canvas.draw()
renderer = fig.canvas.get_renderer()
inv = fig.transFigure.inverted()
titles = ["(a) Ground Truth", f"(b) Ensemble Mean (N={BroadK.shape[0]})", "(c) Ensemble Std Dev"]
for i, ax in enumerate(axes):
    pos = ax.get_position()
    tb = ax.get_tightbbox(renderer).transformed(inv)
    vis_cx = (tb.x0 + tb.x1) / 2
    ax_cx = pos.x0 + pos.width / 2
    x_offset = (vis_cx - ax_cx) / pos.width
    ax.set_title(titles[i], fontsize=30, fontweight="bold", pad=12,
                 x=0.5 + x_offset)

for ext in ["png", "pdf"]:
    fname = os.path.join(OUT_DIR, f"perm_ensemble_statistics.{ext}")
    fig.savefig(fname, dpi=300)
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
