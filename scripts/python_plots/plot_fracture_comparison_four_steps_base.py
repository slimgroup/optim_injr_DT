#!/usr/bin/env python3
"""Plot a base-rate ground-truth forward comparison at a monitoring-step boundary."""

from pathlib import Path

import colorcet as cc
import cmasher
import h5py
import matplotlib
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.gridspec import GridSpec

matplotlib.use("Agg")

BASE = Path(__file__).resolve().parents[2]
DATA_FILE = BASE / "plots" / "paper_figures" / "forward_sim_four_steps_base_data.jld2"
OUT_FILE = BASE / "plots" / "paper_figures" / "fracture_comparison_3x3_four_steps_base.png"

PLOT_CASES = [
    ("POF_eps0", r"(a) POF $\varepsilon = 0$"),
    ("CVaR_g01_a001", r"(b) CVaR $\gamma = 0.1,\ \alpha = 0.01$"),
    ("No_Control", "(c) No Control"),
]
STEP_END_PERIODS = [6, 12, 18, 24]
RHO_CO2 = 700.0
SECONDS_PER_DAY = 24 * 60 * 60


def choose_period(data):
    """Use the first monitoring boundary where no control has fractured."""
    no_control_pres = data["No_Control_pres_snaps"]
    p_max = data["p_max"]
    for period in STEP_END_PERIODS:
        r = (p_max - no_control_pres[period - 1]) / p_max
        if np.any(r < 0):
            return period
    return STEP_END_PERIODS[-1]


def main():
    with h5py.File(DATA_FILE, "r") as f:
        data = {
            "p0": f["p0"][:],
            "p_max": f["p_max"][:].T,
            "period_days": float(f["period_days"][()]),
        }
        for key, _ in PLOT_CASES:
            data[f"{key}_rates"] = f[f"{key}_rates"][:]
            data[f"{key}_sat_snaps"] = f[f"{key}_sat_snaps"][:]
            data[f"{key}_pres_snaps"] = f[f"{key}_pres_snaps"][:]
            data[f"{key}_first_fracture_day"] = float(f[f"{key}_first_fracture_day"][()])

    period = choose_period(data)
    snap = period - 1
    day = period * data["period_days"]
    p0, p_max = data["p0"], data["p_max"]

    nx, nz = 512, 256
    extent = (0, (nx - 1) * 6.25, (nz - 1) * 6.25, 0)
    cmap_margin = mcolors.ListedColormap(np.vstack([
        plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)),
        plt.cm.Blues(np.linspace(0.0, 1.0, 230)),
    ]))

    fields = {}
    dp_vmax = 0.0
    for key, _ in PLOT_CASES:
        sat = data[f"{key}_sat_snaps"][snap].T
        pres = data[f"{key}_pres_snaps"][snap].T
        margin = (p_max - pres) / p_max
        pressure_diff = (pres - p0) / 1e6
        rates = data[f"{key}_rates"][:period]
        injected_mt = float(rates.sum() * data["period_days"] * SECONDS_PER_DAY * RHO_CO2 / 1e9)
        fields[key] = (margin, pressure_diff, sat, rates[-1], injected_mt)
        dp_vmax = max(dp_vmax, float(pressure_diff.max()))

    plt.rcParams.update({
        "font.size": 16,
        "axes.labelsize": 17,
        "axes.titlesize": 18,
        "xtick.labelsize": 14,
        "ytick.labelsize": 14,
    })
    fig = plt.figure(figsize=(16.0, 8.9))
    gs = GridSpec(3, 4, figure=fig, width_ratios=[1, 1, 1, 0.035], hspace=0.10, wspace=0.10)
    row_imgs = [None, None, None]
    row_ylabels = ["Safety Margin $r$\nDepth [m]", "Diff. Pressure $(p-p_0)$\nDepth [m]", "CO$_2$ Saturation\nDepth [m]"]

    for row in range(3):
        for col, (key, title) in enumerate(PLOT_CASES):
            margin, pressure_diff, sat, rate, injected_mt = fields[key]
            ax = fig.add_subplot(gs[row, col])
            if row == 0:
                im = ax.imshow(margin, extent=extent, cmap=cmap_margin, vmin=-0.1, vmax=1.0)
                frac_day = data[f"{key}_first_fracture_day"]
                frac_label = "none" if np.isnan(frac_day) else f"{frac_day:.0f} d"
                ax.set_title(title, fontweight="bold", pad=4)
                ax.text(
                    0.03, 0.94,
                    f"Rate: {rate:.4f} m$^3$/s\nInjected CO$_2$: {injected_mt:.2f} Mt\nFirst fracture: {frac_label}",
                    transform=ax.transAxes, fontsize=11.5, ha="left", va="top",
                    bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.82, edgecolor="0.6"),
                )
            elif row == 1:
                im = ax.imshow(pressure_diff, extent=extent, cmap=cc.cm["CET_L3_r"], vmin=0.0, vmax=dp_vmax * 1.05)
            else:
                im = ax.imshow(sat, extent=extent, cmap=cmasher.rainforest_r, vmin=0.0, vmax=1.0)
            if row < 2:
                ax.set_xticklabels([])
            else:
                ax.set_xlabel("X [m]")
            if col == 0:
                ax.set_ylabel(row_ylabels[row])
            else:
                ax.set_yticklabels([])
            row_imgs[row] = im

    cax0 = fig.add_subplot(gs[0, 3])
    cb0 = fig.colorbar(row_imgs[0], cax=cax0, extend="min")
    cb0.set_ticks([0.0, 0.25, 0.5, 0.75, 1.0])
    cb0.ax.text(0.5, 1.02, "(safe)", transform=cb0.ax.transAxes, fontsize=10.5, ha="center", va="bottom", fontstyle="italic")
    cb0.ax.text(0.5, -0.06, "<0 (frac.)", transform=cb0.ax.transAxes, fontsize=10.5, ha="center", va="top", fontstyle="italic")
    cax1 = fig.add_subplot(gs[1, 3])
    cb1 = fig.colorbar(row_imgs[1], cax=cax1)
    cb1.set_label("MPa")
    cax2 = fig.add_subplot(gs[2, 3])
    fig.colorbar(row_imgs[2], cax=cax2)

    fig.suptitle(f"Ground-Truth Forward Comparison at Day {day:.0f} (Base Rates, No Multiplier)", fontsize=23, fontweight="bold", y=0.962)
    fig.subplots_adjust(left=0.075, right=0.965, top=0.89, bottom=0.10)
    fig.savefig(OUT_FILE, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {OUT_FILE}")
    print(f"Selected monitoring boundary: period={period}, day={day:.0f}")


if __name__ == "__main__":
    main()
