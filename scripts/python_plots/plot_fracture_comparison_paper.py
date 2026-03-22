#!/usr/bin/env python
"""
Paper figure: Fracture vs non-fracture comparison (tight crop, minimal whitespace).
Crops frame titles; larger fonts than the split-panel script in plot_fracture_comparison.py.
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FRAMES_ROOT = os.path.join(
    BASE, "plots", "DT_control", "videos_5cases_20260112_000354"
)
OUT_DIR = os.path.join(BASE, "plots", "paper_figures")
os.makedirs(OUT_DIR, exist_ok=True)


def crop_frame(path, top_frac=0.09, bottom_frac=0.0, left_frac=0.0, right_frac=0.0):
    """Load frame and crop padding."""
    img = Image.open(path)
    w, h = img.size
    return np.array(img.crop((
        int(w * left_frac),
        int(h * top_frac),
        int(w * (1 - right_frac)),
        int(h * (1 - bottom_frac)),
    )))


def make_2col_figure():
    """2-column: POF vs CVaR, final time step. Tight layout."""
    frame_pof  = os.path.join(FRAMES_ROOT, "frames_POF_eps00", "frame_0060.png")
    frame_cvar = os.path.join(FRAMES_ROOT, "frames_CVaR_gamma01_alpha001", "frame_0060.png")

    img_pof  = crop_frame(frame_pof,  top_frac=0.09, bottom_frac=0.01)
    img_cvar = crop_frame(frame_cvar, top_frac=0.09, bottom_frac=0.01)

    fig, axes = plt.subplots(1, 2, figsize=(13, 6.2))
    fig.subplots_adjust(wspace=0.02, left=0.01, right=0.99, top=0.90, bottom=0.01)

    axes[0].imshow(img_pof)
    axes[0].set_title("(a) POF  $\\varepsilon = 0$  (Non-Fracture)",
                      fontsize=17, fontweight="bold", pad=4)
    axes[0].axis("off")

    axes[1].imshow(img_cvar)
    axes[1].set_title("(b) CVaR  $\\gamma = 0.1,\\  \\alpha = 0.01$  (Fracture)",
                      fontsize=17, fontweight="bold", pad=4)
    axes[1].axis("off")

    fig.suptitle(
        "Forward Simulation on Ground Truth  (t = 480 days,  rate $\\times 3$)",
        fontsize=19, fontweight="bold", y=0.98
    )

    fname = os.path.join(OUT_DIR, "fracture_comparison_2col.png")
    fig.savefig(fname, dpi=250, bbox_inches="tight", pad_inches=0.02)
    print(f"Saved: {fname}")
    plt.close(fig)


def make_3col_figure():
    """3-column: POF | CVaR | No Control, final time step. Tight layout."""
    dirs = [
        ("frames_POF_eps00",
         "(a) POF $\\varepsilon = 0$\n(Non-Fracture)"),
        ("frames_CVaR_gamma01_alpha001",
         "(b) CVaR $\\gamma = 0.1,\\ \\alpha = 0.01$\n(Fracture)"),
        ("frames_No_Control",
         "(c) No Control\n(Severe Fracture)"),
    ]

    fig, axes = plt.subplots(1, 3, figsize=(19, 6.2))
    fig.subplots_adjust(wspace=0.02, left=0.01, right=0.99, top=0.88, bottom=0.01)

    for i, (d, title) in enumerate(dirs):
        img = crop_frame(os.path.join(FRAMES_ROOT, d, "frame_0060.png"),
                         top_frac=0.09, bottom_frac=0.01)
        axes[i].imshow(img)
        axes[i].set_title(title, fontsize=16, fontweight="bold", pad=4)
        axes[i].axis("off")

    fig.suptitle(
        "Forward Simulation on Ground Truth  (t = 480 days,  rate $\\times 3$)",
        fontsize=19, fontweight="bold", y=0.98
    )

    fname = os.path.join(OUT_DIR, "fracture_comparison_3col.png")
    fig.savefig(fname, dpi=250, bbox_inches="tight", pad_inches=0.02)
    print(f"Saved: {fname}")
    plt.close(fig)


def make_time_evolution():
    """3x3 grid: columns = cases, rows = time steps. Minimal whitespace."""
    case_dirs = [
        ("frames_POF_eps00",            "POF $\\varepsilon = 0$"),
        ("frames_CVaR_gamma01_alpha001", "CVaR $\\gamma=0.1,\\ \\alpha=0.01$"),
        ("frames_No_Control",           "No Control"),
    ]
    time_frames = [
        (10, "t = 80 d"),
        (30, "t = 240 d"),
        (60, "t = 480 d"),
    ]

    fig, axes = plt.subplots(3, 3, figsize=(18, 15.5))
    fig.subplots_adjust(wspace=0.02, hspace=0.06,
                        left=0.04, right=0.99, top=0.93, bottom=0.01)

    for row, (fnum, tlabel) in enumerate(time_frames):
        for col, (cdir, clabel) in enumerate(case_dirs):
            fpath = os.path.join(FRAMES_ROOT, cdir, f"frame_{fnum:04d}.png")
            img = crop_frame(fpath, top_frac=0.09, bottom_frac=0.01)
            ax = axes[row, col]
            ax.imshow(img)
            ax.axis("off")

            if row == 0:
                ax.set_title(clabel, fontsize=17, fontweight="bold", pad=4)

        # Row label
        axes[row, 0].text(
            -0.03, 0.5, tlabel, transform=axes[row, 0].transAxes,
            fontsize=16, fontweight="bold", va="center", ha="right",
            rotation=90
        )

    fig.suptitle(
        "Time Evolution: Safety Margin & CO$_2$ Saturation  (rate $\\times 3$)",
        fontsize=20, fontweight="bold", y=0.98
    )

    fname = os.path.join(OUT_DIR, "fracture_time_evolution.png")
    fig.savefig(fname, dpi=200, bbox_inches="tight", pad_inches=0.02)
    print(f"Saved: {fname}")
    plt.close(fig)


if __name__ == "__main__":
    make_2col_figure()
    make_3col_figure()
    make_time_evolution()
    print("\nAll figures saved!")
