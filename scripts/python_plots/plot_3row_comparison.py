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
import cmasher
BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_FILE = os.path.join(BASE, "plots", "paper_figures", "forward_sim_data.jld2")
OUT_DIR   = os.path.join(BASE, "plots", "paper_figures")

if not os.path.exists(DATA_FILE):
    sys.exit(f"ERROR: {DATA_FILE} not found. Run run_forward_export.jl first.")

nx, nz = 512, 256
dx, dz = 6.25, 6.25
extent = (0, (nx - 1) * dx, (nz - 1) * dz, 0)
THRESHOLD = 4.0
DT_DAYS = 8.0
SUBSTEPS_PER_PERIOD = 10
SECONDS_PER_DAY = 24 * 60 * 60
RHO_CO2 = 700.0  # kg/m^3, from JutulDarcyRules.ρCO2

print("Loading data ...")
data = {}
with h5py.File(DATA_FILE, "r") as f:
    data["p0"]    = f["p0"][:]
    data["p_max"] = f["p_max"][:].T
    for ck in ["POF_eps0", "CVaR_g01_a001", "No_Control"]:
        data[f"{ck}_rates"] = f[f"{ck}_rates"][:]
        data[f"{ck}_sat"]  = f[f"{ck}_sat_final"][:].T
        data[f"{ck}_pres"] = f[f"{ck}_pres_final"][:].T
p0, p_max = data["p0"], data["p_max"]

cases = [
    ("POF_eps0",      "(a)  POF  $\\varepsilon = 0$\n(Non-Fracture)"),
    ("CVaR_g01_a001", "(b)  CVaR  $\\gamma{=}0.1,\\ \\alpha{=}0.01$\n(Fracture)"),
    ("No_Control",    "(c)  No Control\n(Severe Fracture)"),
]


def format_total_mass_mt(total_volume_m3):
    total_mass_mt = total_volume_m3 * RHO_CO2 / 1e9
    return f"{total_mass_mt:.2f} Mt"


case_annotations = {}
period_seconds = DT_DAYS * SUBSTEPS_PER_PERIOD * SECONDS_PER_DAY
for ck, _ in cases:
    rates = np.asarray(data[f"{ck}_rates"], dtype=float).ravel()
    total_volume = float(np.sum(rates) * period_seconds)
    case_annotations[ck] = (
        f"Rate: {rates[-1]:.4f} m$^3$/s\n"
        f"CO$_2$: {format_total_mass_mt(total_volume)}"
    )

# ── Colormaps ──────────────────────────────────────────────────────────────
cmap_margin = mcolors.ListedColormap(np.vstack([
    plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)),
    plt.cm.Blues(np.linspace(0.0, 1.0, 230)),
]))
cmap_pres = cc.cm["CET_L3_r"]
cmap_sat = cmasher.rainforest_r

dp_vmax = 0
for ck, _ in cases:
    dp_vmax = max(dp_vmax, np.max((data[f"{ck}_pres"] - p0) / 1e6))
dp_vmax = min(dp_vmax * 1.05, THRESHOLD * 1.6)

# ── Figure ─────────────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 26,
    "axes.labelsize": 28,
    "axes.titlesize": 28,
    "xtick.labelsize": 24,
    "ytick.labelsize": 24,
})

fig = plt.figure(figsize=(24, 16))
outer = gridspec.GridSpec(3, 1, figure=fig,
                          hspace=0.12, top=0.87, bottom=0.05, left=0.09, right=0.95)

row_imgs = [None, None, None]
row_ylabels = [
    "Safety Margin $r$\nDepth [m]",
    "Diff. Pressure $(p{-}p_0)$\nDepth [m]",
    "CO$_2$ Saturation\nDepth [m]",
]
first_row_axes = []

for row_idx in range(3):
    inner = gridspec.GridSpecFromSubplotSpec(
        1, 4, subplot_spec=outer[row_idx],
        width_ratios=[1, 1, 1, 0.04], wspace=0.12
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
            ax.set_title(cases[col][1], fontsize=32, fontweight="bold", pad=4)
            ax.text(
                0.03, 0.96, case_annotations[ck],
                transform=ax.transAxes,
                fontsize=22,
                ha="left",
                va="top",
                bbox=dict(boxstyle="round,pad=0.28", facecolor="white", alpha=0.82, edgecolor="0.6"),
            )
            first_row_axes.append(ax)
        elif row_idx == 1:
            dp = (pres - p0) / 1e6
            im = ax.imshow(dp.T, extent=extent, cmap=cmap_pres,
                           vmin=0, vmax=dp_vmax, aspect="auto")
        else:
            im = ax.imshow(sat.T, extent=extent, cmap=cmap_sat,
                           vmin=0, vmax=1, aspect="auto")

        if row_idx < 2:
            ax.set_xticklabels([])
        else:
            ax.set_xlabel("X [m]", fontsize=28)
        if col == 0:
            ax.set_ylabel(row_ylabels[row_idx], fontsize=26)
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
                   fontsize=20, ha="center", va="top", fontstyle="italic")
        cb.ax.text(0.5, 1.02, "(safe)", transform=cb.ax.transAxes,
                   fontsize=20, ha="center", va="bottom", fontstyle="italic")
    elif row_idx == 1:
        cb = fig.colorbar(row_imgs[1], cax=cax)
        cb.set_label("MPa", fontsize=26, labelpad=8)
    else:
        cb = fig.colorbar(row_imgs[2], cax=cax)
    cb.ax.tick_params(labelsize=22)

fig.suptitle(
    "Non-Fracture vs Fracture: Safety Margin, Pressure, and CO$_2$ Plume  (t = 480 days)",
    fontsize=36, fontweight="bold", x=0.5, y=0.96)

fname = os.path.join(OUT_DIR, "fracture_comparison_3x3.png")
fig.savefig(fname, dpi=250, bbox_inches="tight", pad_inches=0.01)
print(f"Saved: {fname}")
plt.close(fig)
print("Done!")
