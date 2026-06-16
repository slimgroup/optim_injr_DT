#!/usr/bin/env python3
"""Create the real 1920-day three-case fracture-comparison video."""

import json
import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(__file__).resolve().parents[2] / ".mplconfig"))

import cmasher
import colorcet as cc
import h5py
import imageio.v2 as imageio
import matplotlib

matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.gridspec import GridSpec

BASE = Path(__file__).resolve().parents[2]
OUTDIR = BASE / "plots" / "paper_figures"
VIDEO = OUTDIR / "fracture_comparison_three_cases_full_campaign.mp4"
METADATA = OUTDIR / "fracture_comparison_three_cases_full_campaign_metadata.json"
DT_DAYS = 8.0
FPS = 12

CASES = [
    ("POF_eps001", r"(a) PoF $\varepsilon = 0.01$", OUTDIR / "full_campaign_video_POF_eps001.jld2"),
    ("CVaR_g01_a001_sensitivity", r"(b) CVaR (Slight Fracture)", OUTDIR / "full_campaign_video_CVaR_g01_a001_sensitivity.jld2"),
    ("No_Control", "(c) No Control (Severe Fracture)", OUTDIR / "full_campaign_video_No_Control.jld2"),
]


def main() -> None:
    data = {}
    dp_vmax = 0.0
    for key, title, path in CASES:
        f = h5py.File(path, "r")
        p0 = f["p0"][:]
        p_max = f["p_max"][:].T
        data[key] = {
            "file": f,
            "title": title,
            "p0": p0,
            "p_max": p_max,
            "rates": f["rate_by_substep"][:],
            "min_margin": f["min_margin_by_substep"][:],
            "fractured_cells": f["fractured_cells_by_substep"][:],
            "multiplier": float(f["cvar_sensitivity_multiplier"][()]),
        }
        for idx in range(0, len(data[key]["rates"]), 10):
            pres = f["pres_all"][idx].T
            dp_vmax = max(dp_vmax, float(((pres - p0) / 1e6).max()))

    cmap_margin = mcolors.ListedColormap(
        np.vstack([plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)), plt.cm.Blues(np.linspace(0.0, 1.0, 230))])
    )
    extent = (0, 511 * 6.25, 255 * 6.25, 0)
    plt.rcParams.update({"font.size": 11, "axes.labelsize": 12, "axes.titlesize": 13})

    with imageio.get_writer(VIDEO, fps=FPS, codec="libx264", quality=8, macro_block_size=None) as writer:
        for frame_idx in range(240):
            fig = plt.figure(figsize=(14.4, 8.0))
            gs = GridSpec(3, 4, figure=fig, width_ratios=[1, 1, 1, 0.035], hspace=0.10, wspace=0.10)
            row_imgs = [None, None, None]
            day = (frame_idx + 1) * DT_DAYS

            for row in range(3):
                for col, (key, _, _) in enumerate(CASES):
                    case = data[key]
                    pres = case["file"]["pres_all"][frame_idx].T
                    sat = case["file"]["sat_all"][frame_idx].T
                    margin = (case["p_max"] - pres) / case["p_max"]
                    dp = (pres - case["p0"]) / 1e6
                    ax = fig.add_subplot(gs[row, col])
                    if row == 0:
                        im = ax.imshow(margin.T, extent=extent, cmap=cmap_margin, vmin=-0.1, vmax=1.0)
                        ax.set_title(case["title"], fontweight="bold", pad=3)
                        ax.text(
                            0.02,
                            0.96,
                            f"rate={case['rates'][frame_idx]:.4f} m$^3$/s\n"
                            f"min(r)={case['min_margin'][frame_idx]:.3f}; frac. cells={int(case['fractured_cells'][frame_idx]):,}",
                            transform=ax.transAxes,
                            fontsize=8,
                            ha="left",
                            va="top",
                            bbox=dict(boxstyle="round,pad=0.20", facecolor="white", alpha=0.82, edgecolor="0.6"),
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
            cb0.ax.text(0.5, 1.02, "(safe)", transform=cb0.ax.transAxes, ha="center", va="bottom", fontstyle="italic", fontsize=8)
            cb0.ax.text(0.5, -0.06, "<0 (frac.)", transform=cb0.ax.transAxes, ha="center", va="top", fontstyle="italic", fontsize=8)
            cb1 = fig.colorbar(row_imgs[1], cax=fig.add_subplot(gs[1, 3]))
            cb1.set_label("MPa")
            fig.colorbar(row_imgs[2], cax=fig.add_subplot(gs[2, 3]))
            fig.suptitle(f"Real Ground-Truth Forward Comparison | Day {day:.0f} / 1920", fontsize=18, fontweight="bold", y=0.965)
            fig.subplots_adjust(left=0.07, right=0.965, top=0.90, bottom=0.09)
            fig.canvas.draw()
            writer.append_data(np.asarray(fig.canvas.buffer_rgba())[:, :, :3])
            plt.close(fig)
            if (frame_idx + 1) % 20 == 0:
                print(f"Encoded frame {frame_idx + 1}/240")

    metadata = {
        "video": VIDEO.name,
        "ground_truth_permeability_index": 2000,
        "duration_days": 1920,
        "frame_interval_days": DT_DAYS,
        "cases": {
            "PoF eps=0.01": {"rate_multiplier": 1.0, "schedule": "documented optimized schedule"},
            "CVaR gamma=0.1 alpha=0.01 sensitivity": {
                "rate_multiplier": data["CVaR_g01_a001_sensitivity"]["multiplier"],
                "schedule": "documented optimized schedule multiplied by 1.22",
            },
            "No control": {"rate_multiplier": 1.0, "schedule": "10-period ramp to 0.2 m3/s; shut down after severe fracture at day 728"},
        },
    }
    METADATA.write_text(json.dumps(metadata, indent=2) + "\n")
    for case in data.values():
        case["file"].close()
    print(f"Saved: {VIDEO}")
    print(f"Saved: {METADATA}")


if __name__ == "__main__":
    main()
