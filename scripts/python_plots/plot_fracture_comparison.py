#!/usr/bin/env python
"""
Paper figure: Fracture vs Non-Fracture Forward Simulation Comparison
Composes existing simulation video frames into a clean 3-column paper figure.
Columns: POF (non-fracture) | CVaR (moderate fracture) | No Control (severe fracture)
Rows: Relative Pressure Margin | CO2 Saturation
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from PIL import Image

# ── Paths ──────────────────────────────────────────────────────────────────
BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FRAMES_ROOT = os.path.join(
    BASE, "plots", "DT_control",
    "videos_5cases_20260112_000354"
)
OUT_DIR = os.path.join(BASE, "plots", "paper_figures")
os.makedirs(OUT_DIR, exist_ok=True)

# ── Frame paths (final time step = 60) ────────────────────────────────────
frame_pof  = os.path.join(FRAMES_ROOT, "frames_POF_eps00",           "frame_0060.png")
frame_cvar = os.path.join(FRAMES_ROOT, "frames_CVaR_gamma01_alpha001", "frame_0060.png")
frame_nc   = os.path.join(FRAMES_ROOT, "frames_No_Control",          "frame_0060.png")

for p in [frame_pof, frame_cvar, frame_nc]:
    assert os.path.exists(p), f"Missing: {p}"

# ── Load and crop images ──────────────────────────────────────────────────
# Each frame has: title bar, safety margin panel + colorbar, saturation panel + colorbar
# We crop to extract just the plot panels (without individual titles)

def load_and_split(path):
    """Load a frame and split into safety margin (top) and saturation (bottom) panels."""
    img = Image.open(path)
    w, h = img.size
    # The frame layout: title ~10%, safety margin ~42%, saturation ~48%
    # Approximate crop regions (adjusted based on 150dpi frames)
    title_end = int(h * 0.085)
    mid_point = int(h * 0.50)
    return img, (w, h), title_end, mid_point

# ── 3-column composite figure ─────────────────────────────────────────────
# We'll use matplotlib to place the images with proper labels

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 14,
    "axes.titlesize": 16,
})

fig = plt.figure(figsize=(18, 11))

# Read images
img_pof  = plt.imread(frame_pof)
img_cvar = plt.imread(frame_cvar)
img_nc   = plt.imread(frame_nc)

# Create 1x3 grid
gs = GridSpec(1, 3, figure=fig, wspace=0.03, hspace=0.02,
             left=0.02, right=0.98, top=0.92, bottom=0.02)

cases = [
    ("(a) POF  $\\varepsilon = 0$ (Non-Fracture)", img_pof),
    ("(b) CVaR  $\\gamma = 0.1,\\ \\alpha = 0.01$ (Fracture)", img_cvar),
    ("(c) No Control (Severe Fracture)", img_nc),
]

for i, (title, img) in enumerate(cases):
    ax = fig.add_subplot(gs[0, i])
    ax.imshow(img)
    ax.set_title(title, fontsize=14, pad=4)
    ax.axis("off")

fig.suptitle(
    "Forward Simulation on Ground Truth Permeability  (t = 480 days,  rate $\\times$3)",
    fontsize=17, fontweight="bold", y=0.97
)

fname = os.path.join(OUT_DIR, "fracture_comparison_3col.png")
fig.savefig(fname, dpi=200, bbox_inches="tight", pad_inches=0.1)
print(f"Saved: {fname}")
plt.close(fig)

# ── Also create a 2-column version (POF vs CVaR only) ────────────────────
fig2 = plt.figure(figsize=(13, 11))
gs2 = GridSpec(1, 2, figure=fig2, wspace=0.03,
              left=0.02, right=0.98, top=0.92, bottom=0.02)

for i, (title, img) in enumerate(cases[:2]):
    ax = fig2.add_subplot(gs2[0, i])
    ax.imshow(img)
    ax.set_title(title, fontsize=15, pad=4)
    ax.axis("off")

fig2.suptitle(
    "Forward Simulation on Ground Truth  (t = 480 days,  rate $\\times$3)",
    fontsize=17, fontweight="bold", y=0.97
)

fname2 = os.path.join(OUT_DIR, "fracture_comparison_2col.png")
fig2.savefig(fname2, dpi=200, bbox_inches="tight", pad_inches=0.1)
print(f"Saved: {fname2}")
plt.close(fig2)

# ── Time evolution comparison (frames at t=80, 240, 480 days) ─────────────
print("\nGenerating time evolution comparison...")
time_frames = [
    (10, "t = 80 days"),
    (30, "t = 240 days"),
    (60, "t = 480 days"),
]

fig3 = plt.figure(figsize=(18, 14))
gs3 = GridSpec(3, 3, figure=fig3, wspace=0.03, hspace=0.12,
              left=0.02, right=0.98, top=0.94, bottom=0.02)

case_dirs = [
    ("frames_POF_eps00", "POF $\\varepsilon = 0$"),
    ("frames_CVaR_gamma01_alpha001", "CVaR $\\gamma=0.1$"),
    ("frames_No_Control", "No Control"),
]

for row, (frame_num, time_label) in enumerate(time_frames):
    for col, (cdir, clabel) in enumerate(case_dirs):
        fpath = os.path.join(FRAMES_ROOT, cdir, f"frame_{frame_num:04d}.png")
        img = plt.imread(fpath)
        ax = fig3.add_subplot(gs3[row, col])
        ax.imshow(img)
        ax.axis("off")
        if row == 0:
            ax.set_title(clabel, fontsize=15, pad=4)
        if col == 0:
            ax.set_ylabel(time_label, fontsize=14, labelpad=10)
            ax.yaxis.set_visible(True)
            ax.set_yticks([])

fig3.suptitle(
    "Time Evolution: Safety Margin & CO$_2$ Saturation  (rate $\\times$3)",
    fontsize=17, fontweight="bold", y=0.97
)

fname3 = os.path.join(OUT_DIR, "fracture_time_evolution.png")
fig3.savefig(fname3, dpi=200, bbox_inches="tight", pad_inches=0.1)
print(f"Saved: {fname3}")
plt.close(fig3)

print("\nAll figures saved!")
