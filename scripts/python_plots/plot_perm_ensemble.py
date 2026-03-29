#!/usr/bin/env python
"""
Paper figure: Permeability ensemble statistics
Shows: (a) Ground truth (sample 2000), (b) Ensemble mean, (c) Ensemble std
Colorbars consistent with optim_inject.jl
"""
import os, sys
import gc
import numpy as np
import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
import colorcet as cc

# -- Paths -----------------------------------------------------------------
BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.path.join(BASE, "data")
OUT_DIR = os.path.join(BASE, "plots", "paper_figures")
os.makedirs(OUT_DIR, exist_ok=True)

# -- Domain ----------------------------------------------------------------
nx, nz = 512, 256
dx, dz = 6.25, 6.25
h = 0.0
GROUND_TRUTH_IDX = 1999
extent = (0, (nx - 1) * dx, h + (nz - 1) * dz, h)

# -- Load data (chunked: never hold full 2000x512x256 in RAM) --------------
perm_path = os.path.join(DATA_DIR, "geo", "wise_perm_models_2000_new.jld2")
CHUNK = 64
print(f"Loading (chunked) {perm_path} ...")
with h5py.File(perm_path, "r") as f:
    dset = f["BroadK"]
    print(f"  raw HDF5 shape: {dset.shape}")
    nz_h, nx_h, n_models = dset.shape
    assert (nx_h, nz_h) == (nx, nz), "Unexpected BroadK spatial shape"
    sum_logk = np.zeros((nx, nz), dtype=np.float64)
    sumsq_logk = np.zeros((nx, nz), dtype=np.float64)
    for s in range(0, n_models, CHUNK):
        w = min(CHUNK, n_models - s)
        block = dset[:, :, s : s + w]
        BK = np.ascontiguousarray(block.transpose(2, 1, 0), dtype=np.float32)
        lk = np.log10(np.clip(BK, np.float32(1e-30), None))
        sum_logk += lk.sum(axis=0)
        lk64 = lk.astype(np.float64)
        sumsq_logk += np.square(lk64).sum(axis=0)
        del block, BK, lk, lk64
    gt_block = dset[:, :, GROUND_TRUTH_IDX]
    logK_gt = np.log10(
        np.clip(
            np.ascontiguousarray(gt_block.transpose(1, 0), dtype=np.float32),
            np.float32(1e-30),
            None,
        )
    )

n_models = int(n_models)
logK_mean = (sum_logk / n_models).astype(np.float32)
logK_std = np.sqrt(
    np.maximum(sumsq_logk / n_models - np.square(logK_mean.astype(np.float64)), 0.0)
).astype(np.float32)
del sum_logk, sumsq_logk
gc.collect()

print(f"  GT   range: [{logK_gt.min():.2f}, {logK_gt.max():.2f}]")
print(f"  Mean range: [{logK_mean.min():.2f}, {logK_mean.max():.2f}]")
print(f"  Std  range: [{logK_std.min():.3f}, {logK_std.max():.3f}]")

cmap_perm = cc.cm["rainbow4"]

plt.rcParams.update({
    "font.size": 16,
    "axes.labelsize": 16,
    "axes.titlesize": 18,
    "xtick.labelsize": 14,
    "ytick.labelsize": 14,
})

fig = plt.figure(figsize=(16.0, 5.05))
gs = GridSpec(
    2,
    3,
    figure=fig,
    height_ratios=[1.0, 0.04],
    hspace=0.05,
    wspace=0.10,
)

vmin_p, vmax_p = 0.0, 4.0
vmax_std = float(np.ceil(logK_std.max() * 10) / 10)

ax0 = fig.add_subplot(gs[0, 0])
im0 = ax0.imshow(logK_gt.T, vmin=vmin_p, vmax=vmax_p, extent=extent, cmap=cmap_perm)
ax0.set_title("(a) Ground Truth", fontsize=18, fontweight="bold", pad=3)
ax0.set_xlabel("X [m]", fontsize=19, labelpad=2)
ax0.set_ylabel("Depth [m]", fontsize=19)
ax0.tick_params(labelsize=14, length=3, pad=2)

ax1 = fig.add_subplot(gs[0, 1], sharey=ax0)
im1 = ax1.imshow(logK_mean.T, vmin=vmin_p, vmax=vmax_p, extent=extent, cmap=cmap_perm)
ax1.set_title(f"(b) Ensemble Mean (N={n_models})", fontsize=18, fontweight="bold", pad=3)
ax1.set_xlabel("X [m]", fontsize=19, labelpad=2)
plt.setp(ax1.get_yticklabels(), visible=False)
ax1.tick_params(labelsize=14, length=3, pad=2)

ax2 = fig.add_subplot(gs[0, 2], sharey=ax0)
im2 = ax2.imshow(logK_std.T, vmin=0.0, vmax=vmax_std, extent=extent, cmap="cet_CET_L8")
ax2.set_title("(c) Ensemble Std Dev", fontsize=18, fontweight="bold", pad=3)
ax2.set_xlabel("X [m]", fontsize=19, labelpad=2)
plt.setp(ax2.get_yticklabels(), visible=False)
ax2.tick_params(labelsize=14, length=3, pad=2)

cb_gs_left = gs[1, 0:2].subgridspec(1, 1)
cax_left = fig.add_subplot(cb_gs_left[0, 0])
clb_left = fig.colorbar(im0, cax=cax_left, orientation="horizontal")
clb_left.set_ticks(np.log10([1, 10, 1000]))
clb_left.set_ticklabels(["1", "1e1", "1e3"])
clb_left.ax.tick_params(labelsize=14, length=2, pad=1)

cb_gs_right = gs[1, 2].subgridspec(1, 1)
cax_right = fig.add_subplot(cb_gs_right[0, 0])
clb_right = fig.colorbar(im2, cax=cax_right, orientation="horizontal")
clb_right.set_ticks(np.arange(0.0, vmax_std + 0.001, 0.5))
clb_right.ax.tick_params(labelsize=14, length=2, pad=1)

fig.suptitle(
    "Permeability Ensemble Statistics",
    fontsize=27,
    fontweight="bold",
    y=0.962,
)
fig.subplots_adjust(left=0.075, right=0.965, top=0.875, bottom=0.085)

fname = os.path.join(OUT_DIR, "perm_ensemble_statistics.png")
fig.savefig(fname, dpi=300, bbox_inches="tight")
print(f"Saved: {fname}")
plt.close(fig)

# -- Bonus: GT - Mean difference (tight margins, no tight_layout whitespace) -
fig2 = plt.figure(figsize=(12, 5.2))
ax2 = fig2.add_axes([0.055, 0.11, 0.805, 0.78])
diff = logK_gt - logK_mean
im_d = ax2.imshow(diff.T, extent=extent, cmap="seismic", aspect="auto", vmin=-2, vmax=2)
ax2.set_title("Ground Truth - Ensemble Mean", fontsize=16, fontweight="bold", pad=6)
ax2.set_xlabel("X [m]", fontsize=14)
ax2.set_ylabel("Depth [m]", fontsize=14)
ax2.tick_params(labelsize=12, length=3, pad=2)
cax = fig2.add_axes([0.875, 0.11, 0.022, 0.78])
clb = fig2.colorbar(im_d, cax=cax)
clb.set_label("Delta log$_{10}$(K [mD])", fontsize=13, labelpad=6)
clb.ax.tick_params(labelsize=11)
fname = os.path.join(OUT_DIR, "perm_gt_minus_mean.png")
fig2.savefig(fname, dpi=300, bbox_inches="tight", pad_inches=0.02)
print(f"Saved: {fname}")
plt.close(fig2)

print("Done!")
