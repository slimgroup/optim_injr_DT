#!/usr/bin/env python3
"""Compare real ground-truth no-control fracture severity across candidate rates."""

from pathlib import Path

import h5py
import matplotlib

matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np

BASE = Path(__file__).resolve().parents[2]
OUTDIR = BASE / "plots" / "paper_figures"
RATES = [0.10, 0.15, 0.20]


def tag(rate: float) -> str:
    return f"{rate:.2f}".replace(".", "p")


def main() -> None:
    cmap = mcolors.ListedColormap(
        np.vstack([plt.cm.Reds_r(np.linspace(0.0, 0.85, 26)), plt.cm.Blues(np.linspace(0.0, 1.0, 230))])
    )
    fig, axes = plt.subplots(2, len(RATES), figsize=(15.5, 7.5), sharex=True, sharey=True)
    extent = (0, 511 * 6.25, 255 * 6.25, 0)
    summaries = []

    for col, rate in enumerate(RATES):
        path = OUTDIR / f"no_control_severity_rate_{tag(rate)}.jld2"
        with h5py.File(path, "r") as f:
            p_max = f["p_max"][:].T
            pres = f["pres_all"][:]
            worst_idx = int(f["worst_substep"][()]) - 1
            worst_day = float(f["worst_day"][()])
            min_margin = f["min_margin_by_substep"][:]
            frac_cells = f["fractured_cells_by_substep"][:]

        worst = (p_max - pres[worst_idx].T) / p_max
        day480 = (p_max - pres[-1].T) / p_max
        summaries.append((rate, worst_day, float(min_margin[worst_idx]), int(frac_cells[worst_idx]), float(min_margin[-1]), int(frac_cells[-1])))

        for row, (field, label) in enumerate([(worst, f"Worst state: day {worst_day:.0f}"), (day480, "Day 480")]):
            ax = axes[row, col]
            im = ax.imshow(field.T, extent=extent, cmap=cmap, vmin=-0.25, vmax=1.0)
            if row == 0:
                ax.set_title(f"No control: {rate:.2f} m$^3$/s", fontweight="bold")
            ax.text(
                0.03,
                0.95,
                f"{label}\nmin(r)={field.min():.3f}\nfractured cells={(field < 0).sum():,}",
                transform=ax.transAxes,
                va="top",
                fontsize=11,
                bbox=dict(facecolor="white", edgecolor="0.6", alpha=0.85, boxstyle="round,pad=0.25"),
            )
            if col == 0:
                ax.set_ylabel("Worst relative margin\nDepth [m]" if row == 0 else "Relative margin at day 480\nDepth [m]")
            if row == 1:
                ax.set_xlabel("X [m]")

    cbar = fig.colorbar(im, ax=axes, fraction=0.025, pad=0.02, extend="min")
    cbar.set_label("Relative margin r")
    fig.suptitle("Ground-Truth No-Control Severe-Fracture Rate Sweep", fontsize=22, fontweight="bold")
    fig.subplots_adjust(left=0.07, right=0.92, top=0.88, bottom=0.10, hspace=0.12, wspace=0.08)
    out = OUTDIR / "no_control_severity_rate_sweep.png"
    fig.savefig(out, dpi=300, bbox_inches="tight")
    plt.close(fig)

    print("rate,worst_day,worst_min_r,worst_frac_cells,day480_min_r,day480_frac_cells")
    for row in summaries:
        print(",".join(map(str, row)))
    print(f"Saved: {out}")


if __name__ == "__main__":
    main()
