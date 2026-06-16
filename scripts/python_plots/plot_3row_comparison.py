#!/usr/bin/env python
"""
Paper figure: 3-row × 3-column forward simulation comparison.
Row 1: Relative pressure margin  r = (p_frac - p) / p_max
Row 2: Differential pressure  (p - p0) in MPa
Row 3: CO2 saturation
Columns: PoF ε=0 | CVaR γ=0.1 α=0.01 | No Control
Ground truth permeability: sample 2000.

First-row text boxes (two lines): (1) $q_k^*$ — tabulated for PoF/CVaR, last-period sim
rate for No Control (same label for a uniform figure); (2) injected CO₂ (same formula all columns).
"""
import os
import sys
import numpy as np
import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.gridspec import GridSpec
import colorcet as cc
import cmasher

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_FILE = os.path.join(BASE, "plots/paper_figures", "forward_sim_data.jld2")
OUT_DIR = os.path.join(BASE, "plots", "paper_figures")

# q_k* (m³/s, CDF / injection_rate_arrays.md scale) — only for PoF and CVaR columns.
QK_STAR = {
    "POF_eps0": 0.02630,
    "CVaR_g01_a001": 0.07470,
}
FORWARD_RATE_MULTIPLIER = 3.0

_CASE_KEYS = ["POF_eps0", "CVaR_g01_a001", "No_Control"]

if not os.path.exists(DATA_FILE):
    sys.exit(f"ERROR: {DATA_FILE} not found. Run run_forward_export.jl first.")


def _check_jld2_keys(path):
    with h5py.File(path, "r") as f:
        for ck in _CASE_KEYS:
            if f"{ck}_rates" not in f:
                sys.exit(
                    f"ERROR: {path} has no dataset '{ck}_rates'. "
                    "Regenerate with: julia --project=. scripts/julia_scripts/data_collection/forward_exports/run_forward_export.jl"
                )


_check_jld2_keys(DATA_FILE)

nx, nz = 512, 256
dx, dz = 6.25, 6.25
extent = (0, (nx - 1) * dx, (nz - 1) * dz, 0)
THRESHOLD = 4.0
DT_DAYS = 8.0
SUBSTEPS_PER_PERIOD = 10
SECONDS_PER_DAY = 24 * 60 * 60
RHO_CO2 = 700.0

print("Loading data ...")
data = {}
with h5py.File(DATA_FILE, "r") as f:
    data["p0"] = f["p0"][:]
    data["p_max"] = f["p_max"][:].T
    for ck in _CASE_KEYS:
        data[f"{ck}_rates"] = f[f"{ck}_rates"][:]
        data[f"{ck}_sat"] = f[f"{ck}_sat_final"][:].T
        data[f"{ck}_pres"] = f[f"{ck}_pres_final"][:].T
p0, p_max = data["p0"], data["p_max"]

cases = [
    ("POF_eps0", "(a) PoF ε = 0 (Non-Fracture)"),
    ("CVaR_g01_a001", "(b) CVaR γ = 0.1, α = 0.01 (Fracture)"),
    ("No_Control", "(c) No Control (Severe Fracture)"),
]


def format_total_mass_mt(total_volume_m3):
    total_mass_mt = total_volume_m3 * RHO_CO2 / 1e9
    return f"{total_mass_mt:.2f} Mt"


# Injected CO2 in annotations is reported on the unscaled/base-rate schedule.
# The forward fields in forward_sim_data.jld2 were generated with rates x3
# for visual contrast, so divide by FORWARD_RATE_MULTIPLIER for the labels.
#   Not "q_k* x total days": base_rates[] is the length-6 increasing schedule.
#   total_volume_m3 = sum(base_rates[k] x period_seconds)
#   when each of the 6 control periods has the same duration period_seconds.
#   period_seconds = DT_DAYS x SUBSTEPS_PER_PERIOD x SECONDS_PER_DAY.
#   mass [Mt] = total_volume_m3 x RHO_CO2 [kg/m3] / 1e9.
case_annotations = {}
period_seconds = DT_DAYS * SUBSTEPS_PER_PERIOD * SECONDS_PER_DAY
for ck, _ in cases:
    rates = np.asarray(data[f"{ck}_rates"], dtype=float).ravel()
    base_rates = rates / FORWARD_RATE_MULTIPLIER
    total_volume = float(np.sum(base_rates) * period_seconds)
    co2_line = f"Injected CO$_2$: {format_total_mass_mt(total_volume)}"
    last_sim = float(rates[-1])
    if ck in QK_STAR:
        case_annotations[ck] = (
            f"$q_k^*$ = {QK_STAR[ck]:.4f} m$^3$/s\n" + co2_line
        )
    else:
        # No risk cap in optimization: report the unscaled baseline terminal rate.
        case_annotations[ck] = (
            f"$q_k^*$ = {last_sim / FORWARD_RATE_MULTIPLIER:.4f} m$^3$/s\n" + co2_line
        )

cmap_margin = mcolors.ListedColormap(np.vstack([
    plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)),
    plt.cm.Blues(np.linspace(0.0, 1.0, 230)),
]))
cmap_pres = cc.cm["CET_L3_r"]
cmap_sat = cmasher.rainforest_r

dp_vmax = 0.0
for ck, _ in cases:
    dp_vmax = max(dp_vmax, float(np.max((data[f"{ck}_pres"] - p0) / 1e6)))
dp_vmax = min(dp_vmax * 1.05, THRESHOLD * 1.6)

plt.rcParams.update({
    "font.size": 17,
    "axes.labelsize": 17,
    "axes.titlesize": 19,
    "xtick.labelsize": 15,
    "ytick.labelsize": 15,
})

fig = plt.figure(figsize=(16.0, 8.9))
gs = GridSpec(
    3,
    4,
    figure=fig,
    width_ratios=[1.0, 1.0, 1.0, 0.035],
    hspace=0.10,
    wspace=0.10,
)

row_imgs = [None, None, None]
row_ylabels = [
    "Safety Margin $r$\nDepth [m]",
    "Diff. Pressure $(p-p_0)$\nDepth [m]",
    "CO$_2$ Saturation\nDepth [m]",
]

for row_idx in range(3):
    for col_idx, (ck, title) in enumerate(cases):
        ax = fig.add_subplot(gs[row_idx, col_idx])
        sat = data[f"{ck}_sat"]
        pres = data[f"{ck}_pres"]

        if row_idx == 0:
            img = (p_max - pres) / p_max
            im = ax.imshow(img.T, extent=extent, cmap=cmap_margin, vmin=-0.1, vmax=1.0)
            ax.set_title(title, fontsize=17, fontweight="bold", pad=4)
            ax.text(
                0.03,
                0.94,
                case_annotations[ck],
                transform=ax.transAxes,
                fontsize=12.5,
                ha="left",
                va="top",
                bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.82, edgecolor="0.6"),
            )
        elif row_idx == 1:
            img = (pres - p0) / 1e6
            im = ax.imshow(img.T, extent=extent, cmap=cmap_pres, vmin=0.0, vmax=dp_vmax)
        else:
            img = sat
            im = ax.imshow(img.T, extent=extent, cmap=cmap_sat, vmin=0.0, vmax=1.0)

        if row_idx < 2:
            ax.set_xticklabels([])
        else:
            ax.set_xlabel("X [m]", fontsize=17, labelpad=2)
        if col_idx == 0:
            ax.set_ylabel(row_ylabels[row_idx], fontsize=17)
        else:
            ax.set_yticklabels([])
        ax.tick_params(labelsize=15, length=3, pad=2)
        row_imgs[row_idx] = im

cax0 = fig.add_subplot(gs[0, 3])
cb0 = fig.colorbar(row_imgs[0], cax=cax0, extend="min")
cb0.set_ticks([0.0, 0.25, 0.5, 0.75, 1.0])
cb0.set_ticklabels(["0", "0.25", "0.5", "0.75", "1.0"])
cb0.ax.tick_params(labelsize=13, pad=1, length=2)
cb0.ax.text(0.5, 1.02, "(safe)", transform=cb0.ax.transAxes, fontsize=10.5, ha="center", va="bottom", fontstyle="italic")
cb0.ax.text(0.5, -0.06, "<0 (frac.)", transform=cb0.ax.transAxes, fontsize=10.5, ha="center", va="top", fontstyle="italic")

cax1 = fig.add_subplot(gs[1, 3])
cb1 = fig.colorbar(row_imgs[1], cax=cax1)
cb1.set_label("MPa", fontsize=17)
cb1.ax.tick_params(labelsize=15)

cax2 = fig.add_subplot(gs[2, 3])
cb2 = fig.colorbar(row_imgs[2], cax=cax2)
cb2.ax.tick_params(labelsize=15)

fig.suptitle(
    "Non-Fracture vs Fracture: Safety Margin, Pressure, and CO$_2$ Plume  (t = 480 days)",
    fontsize=24,
    fontweight="bold",
    y=0.962,
)
fig.subplots_adjust(left=0.075, right=0.965, top=0.89, bottom=0.10)

fname = os.path.join(OUT_DIR, "fracture_comparison_3x3.png")
fig.savefig(fname, dpi=300, bbox_inches="tight")
print(f"Saved: {fname}")
plt.close(fig)
print("Done!")
