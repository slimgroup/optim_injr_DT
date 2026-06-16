#!/usr/bin/env python3
"""Real ground-truth controlled/no-control comparison at the common severe-fracture day."""

import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(__file__).resolve().parents[2] / ".mplconfig"))

import cmasher
import colorcet as cc
import h5py
import matplotlib

matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.gridspec import GridSpec

BASE = Path(__file__).resolve().parents[2]
OUTDIR = BASE / "plots" / "paper_figures"
SENSITIVITY = float(os.environ.get("CVAR_SENSITIVITY", "1.0"))
SENSITIVITY_TAG = f"{SENSITIVITY:.2f}".replace(".", "p")
OUTFILE = (
    OUTDIR / f"fracture_comparison_3x3_four_steps_cvar_sensitivity_{SENSITIVITY_TAG}x.png"
    if SENSITIVITY != 1.0
    else OUTDIR / "fracture_comparison_3x3_four_steps_base.png"
)
DAY = 728.0
DT_DAYS = 8.0
SUBSTEP = int(DAY / DT_DAYS) - 1
PERIOD_DAYS = 80.0
SECONDS_PER_DAY = 86400
RHO_CO2 = 700.0

CASES = [
    ("POF_eps0", r"(a) PoF $\varepsilon = 0$", OUTDIR / "controlled_day728_POF_eps0.jld2"),
    (
        "CVaR_g01_a001",
        r"(b) CVaR $\gamma = 0.1,\ \alpha = 0.01$",
        OUTDIR / f"cvar_day728_sensitivity_{SENSITIVITY_TAG}x.jld2"
        if SENSITIVITY != 1.0
        else OUTDIR / "controlled_day728_CVaR_g01_a001.jld2",
    ),
    ("No_Control", "(c) No Control (Severe Fracture)", OUTDIR / "no_control_delayed_ramp_10_periods.jld2"),
]


def injected_mt(rates: np.ndarray, day: float) -> float:
    remaining = day
    volume = 0.0
    for rate in rates:
        duration = min(PERIOD_DAYS, remaining)
        if duration <= 0:
            break
        volume += rate * duration * SECONDS_PER_DAY
        remaining -= duration
    return volume * RHO_CO2 / 1e9


def rate_at_day(rates: np.ndarray, day: float) -> float:
    return float(rates[min(int(np.ceil(day / PERIOD_DAYS)) - 1, len(rates) - 1)])


def main() -> None:
    fields = {}
    dp_vmax = 0.0
    for key, title, path in CASES:
        with h5py.File(path, "r") as f:
            p0 = f["p0"][:]
            p_max = f["p_max"][:].T
            if key == "No_Control":
                pres = f["pres_all"][SUBSTEP].T
                sat = f["sat_all"][SUBSTEP].T
                rates = f["full_rates"][:]
                display_rates = rates
            else:
                pres = f["pres"][:].T
                sat = f["sat"][:].T
                rates = f["rates"][:]
                display_rates = f["base_rates"][:] if key == "CVaR_g01_a001" and "base_rates" in f else rates
        margin = (p_max - pres) / p_max
        dp = (pres - p0) / 1e6
        fields[key] = (title, margin, dp, sat, rates, display_rates, injected_mt(rates, DAY))
        dp_vmax = max(dp_vmax, float(dp.max()))

    cmap_margin = mcolors.ListedColormap(
        np.vstack([plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)), plt.cm.Blues(np.linspace(0.0, 1.0, 230))])
    )
    extent = (0, 511 * 6.25, 255 * 6.25, 0)
    plt.rcParams.update({"font.size": 16, "axes.labelsize": 17, "axes.titlesize": 17, "xtick.labelsize": 14, "ytick.labelsize": 14})
    fig = plt.figure(figsize=(16.0, 8.9))
    gs = GridSpec(3, 4, figure=fig, width_ratios=[1, 1, 1, 0.035], hspace=0.10, wspace=0.10)
    row_imgs = [None, None, None]

    for row in range(3):
        for col, (key, _, _) in enumerate(CASES):
            title, margin, dp, sat, rates, display_rates, mass = fields[key]
            ax = fig.add_subplot(gs[row, col])
            if row == 0:
                im = ax.imshow(margin.T, extent=extent, cmap=cmap_margin, vmin=-0.1, vmax=1.0)
                ax.set_title(title, fontweight="bold", pad=4)
                ax.text(
                    0.03,
                    0.94,
                    f"Active rate at day {DAY:.0f}: {rate_at_day(display_rates, DAY):.4f} m$^3$/s\n"
                    f"Injected CO$_2$ through day {DAY:.0f}: {mass:.2f} Mt\n"
                    f"min(r): {margin.min():.3f}; frac. cells: {(margin < 0).sum():,}",
                    transform=ax.transAxes,
                    fontsize=11,
                    ha="left",
                    va="top",
                    bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.84, edgecolor="0.6"),
                )
            elif row == 1:
                im = ax.imshow(dp.T, extent=extent, cmap=cc.cm["CET_L3_r"], vmin=0.0, vmax=dp_vmax * 1.05)
            else:
                im = ax.imshow(sat.T, extent=extent, cmap=cmasher.rainforest_r, vmin=0.0, vmax=1.0)
            if row < 2:
                ax.set_xticklabels([])
            else:
                ax.set_xlabel("X [m]")
            if col == 0:
                ax.set_ylabel(["Safety Margin $r$\nDepth [m]", "Diff. Pressure $(p-p_0)$\nDepth [m]", "CO$_2$ Saturation\nDepth [m]"][row])
            else:
                ax.set_yticklabels([])
            row_imgs[row] = im

    cb0 = fig.colorbar(row_imgs[0], cax=fig.add_subplot(gs[0, 3]), extend="min")
    cb0.set_ticks([0, 0.25, 0.5, 0.75, 1])
    cb0.ax.text(0.5, 1.02, "(safe)", transform=cb0.ax.transAxes, ha="center", va="bottom", fontstyle="italic", fontsize=10)
    cb0.ax.text(0.5, -0.06, "<0 (frac.)", transform=cb0.ax.transAxes, ha="center", va="top", fontstyle="italic", fontsize=10)
    cb1 = fig.colorbar(row_imgs[1], cax=fig.add_subplot(gs[1, 3]))
    cb1.set_label("MPa")
    fig.colorbar(row_imgs[2], cax=fig.add_subplot(gs[2, 3]))
    fig.suptitle(f"Real Ground-Truth Fracture Comparison at Day {DAY:.0f}", fontsize=23, fontweight="bold", y=0.962)
    fig.subplots_adjust(left=0.075, right=0.965, top=0.89, bottom=0.10)
    fig.savefig(OUTFILE, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {OUTFILE}")


if __name__ == "__main__":
    main()
