#!/usr/bin/env python
"""
Paper figure: 3-row × 3-column forward simulation comparison.
Row 1: Relative pressure margin  r = (p_frac − p) / p_frac
Row 2: Differential pressure  (p − p₀) in MPa
Row 3: CO₂ Saturation
Columns: POF ε=0 | CVaR γ=0.1 α=0.01 | No Control
Ground truth permeability: sample 2000.
"""
import os, sys
import numpy as np
import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import matplotlib.gridspec as gridspec
import colorcet as cc

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_FILE = os.path.join(BASE, "plots", "paper_figures", "forward_sim_data.jld2")
OUT_DIR   = os.path.join(BASE, "plots", "paper_figures")

if not os.path.exists(DATA_FILE):
    sys.exit(f"ERROR: {DATA_FILE} not found. Run run_forward_export.jl first.")

nx, nz = 512, 256
dx, dz = 6.25, 6.25
extent = (0, (nx - 1) * dx, (nz - 1) * dz, 0)
THRESHOLD = 4.0

print("Loading data ...")
data = {}
with h5py.File(DATA_FILE, "r") as f:
    data["p0"]    = f["p0"][:]
    data["p_max"] = f["p_max"][:].T
    for ck in ["POF_eps0", "CVaR_g01_a001", "No_Control"]:
        data[f"{ck}_sat"]  = f[f"{ck}_sat_final"][:].T
        data[f"{ck}_pres"] = f[f"{ck}_pres_final"][:].T
p0, p_max = data["p0"], data["p_max"]

cases = [
    ("POF_eps0",      "(a)  POF  $\\varepsilon = 0$   (Non-Fracture)"),
    ("CVaR_g01_a001", "(b)  CVaR  $\\gamma{=}0.1,\\ \\alpha{=}0.01$   (Fracture)"),
    ("No_Control",    "(c)  No Control   (Severe Fracture)"),
]

# ── Colormaps ──────────────────────────────────────────────────────────────
cmap_margin = mcolors.ListedColormap(np.vstack([
    plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)),
    plt.cm.Blues(np.linspace(0.0, 1.0, 230)),
]))
cmap_pres = cc.cm["CET_L3_r"]
try:
    import cmasher; cmap_sat = cmasher.rainforest_r
except ImportError:
    cmap_sat = "viridis"

dp_vmax = 0
for ck, _ in cases:
    dp_vmax = max(dp_vmax, np.max((data[f"{ck}_pres"] - p0) / 1e6))
dp_vmax = min(dp_vmax * 1.05, THRESHOLD * 1.6)

# ── Figure ─────────────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 18,
    "axes.labelsize": 19,
    "axes.titlesize": 20,
    "xtick.labelsize": 16,
    "ytick.labelsize": 16,
})

fig = plt.figure(figsize=(20, 12))
outer = gridspec.GridSpec(3, 1, figure=fig,
                          hspace=0.15, top=0.89, bottom=0.06, left=0.07, right=0.99)

row_imgs = [None, None, None]
row_ylabels = [
    "Safety Margin $r$\nDepth [m]",
    "Diff. Pressure $(p{-}p_0)$\nDepth [m]",
    "CO$_2$ Saturation\nDepth [m]",
]

for row_idx in range(3):
    inner = gridspec.GridSpecFromSubplotSpec(
        1, 4, subplot_spec=outer[row_idx],
        width_ratios=[1, 1, 1, 0.04], wspace=0.05
    )
    for col in range(3):
        ax = fig.add_subplot(inner[0, col])
        ck = cases[col][0]
        sat  = data[f"{ck}_sat"]
        pres = data[f"{ck}_pres"]

        if row_idx == 0:
            r = (p_max - pres) / p_max
            im = ax.imshow(r.T, extent=extent, cmap=cmap_margin,
                           vmin=-0.1, vmax=1.0, aspect="auto")
        elif row_idx == 1:
            dp = (pres - p0) / 1e6
            im = ax.imshow(dp.T, extent=extent, cmap=cmap_pres,
                           vmin=0, vmax=dp_vmax, aspect="auto")
        else:
            im = ax.imshow(sat.T, extent=extent, cmap=cmap_sat,
                           vmin=0, vmax=1, aspect="auto")

        if row_idx == 0:
            ax.set_title(cases[col][1], fontsize=20, fontweight="bold", pad=10)
        if row_idx < 2:
            ax.set_xticklabels([])
        else:
            ax.set_xlabel("X [m]", fontsize=19)
        if col == 0:
            ax.set_ylabel(row_ylabels[row_idx], fontsize=17)
        else:
            ax.set_yticklabels([])

        row_imgs[row_idx] = im

    # Colorbar
    cax = fig.add_subplot(inner[0, 3])
    if row_idx == 0:
        cb = fig.colorbar(row_imgs[0], cax=cax, extend="min")
        cb.set_ticks([0, 0.25, 0.5, 0.75, 1.0])
        cb.set_ticklabels(["0", "0.25", "0.5", "0.75", "1.0"])
        # "<0 (frac)" at the extended tip, "safe" at top
        cb.ax.text(0.5, -0.06, "<0 (frac.)", transform=cb.ax.transAxes,
                   fontsize=13, ha="center", va="top", fontstyle="italic")
        cb.ax.text(0.5, 1.02, "(safe)", transform=cb.ax.transAxes,
                   fontsize=13, ha="center", va="bottom", fontstyle="italic")
    elif row_idx == 1:
        cb = fig.colorbar(row_imgs[1], cax=cax)
        cb.set_label("MPa", fontsize=17, labelpad=8)
    else:
        cb = fig.colorbar(row_imgs[2], cax=cax)
    cb.ax.tick_params(labelsize=15)

fig.suptitle(
    "Non-Fracture vs Fracture: Safety Margin, Pressure, and CO$_2$ Plume  (t = 480 days)",
    fontsize=22, fontweight="bold", y=0.97
)

for ext in ["png", "pdf"]:
    fname = os.path.join(OUT_DIR, f"fracture_comparison_3x3.{ext}")
    fig.savefig(fname, dpi=250, bbox_inches="tight", pad_inches=0.04)
    print(f"Saved: {fname}")
plt.close(fig)
print("Done!")
