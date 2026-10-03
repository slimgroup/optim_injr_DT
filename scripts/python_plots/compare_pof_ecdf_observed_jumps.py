#!/usr/bin/env python3
"""Compare the frozen 1500-point PoF ECDF with exact observed-jump rendering.

Run export_pof_jump_comparison.jl via Slurm first. This lightweight renderer
reads its verified bootstrap diagnostics and exports only new PNG figures.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
os.environ.setdefault("MPLCONFIGDIR", str(BASE / ".mplconfig"))
import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.ticker import MultipleLocator, FormatStrFormatter
import numpy as np

CACHE = BASE / "data/figure_exports/figures6_7_decimal4_20260910_005149/case_result.jld2"
JUMP_DIR = BASE / "data/figure_exports/pof_eps001_jump_comparison_20260916"
FIGURE_ROOT = BASE / "plots/DT_control/exp_name=step1/statistical_analysis/ecdf"
SOURCE_PNG = FIGURE_ROOT / "labels_reviewed_v6_20260915/cdf_POF_eps0.01.png"
DEFAULT_OUTDIR = FIGURE_ROOT / "jump_comparison_20260916"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_results(jump_dir):
    with h5py.File(CACHE, "r") as f:
        cr = {}
        for ref in f[f["case_result"][()]["kvvec"]]:
            pair = f[ref][()]
            cr[pair["first"].decode()] = f[pair["second"]][()]
        metadata = {k: f[k][()].item() for k in (
            "bootstrap_resamples", "confidence", "threshold", "seed",
            "schedule_element", "schedule_length", "inj_start",
        )}
    jumps = np.genfromtxt(jump_dir / "observed_jump_ecdf.csv", delimiter=",", names=True)
    assert len(cr["data"]) == cr["n"] == 128
    assert metadata["schedule_element"] == 6 and metadata["schedule_length"] == 12
    np.testing.assert_array_equal(jumps["rate"], np.unique(cr["data"]))
    idx = np.searchsorted(jumps["rate"], cr["xg"], side="right")
    for old, new in (("ecdf_v", "ecdf"), ("ci_lo", "ci_lower"), ("ci_hi", "ci_upper")):
        np.testing.assert_array_equal(np.r_[0.0, jumps[new]][idx], cr[old])
    for key, series in (("x_conservative", "ci_upper"), ("x_ecdf", "ecdf"), ("x_optimistic", "ci_lower")):
        crossing = jumps["rate"][np.flatnonzero(jumps[series] >= metadata["threshold"])[0]]
        assert crossing == cr[key], key
    return cr, jumps, metadata


def draw_series(ax, cr, jumps, exact):
    if exact:
        x = np.r_[cr["xg"][0], jumps["rate"], cr["xg"][-1]]
        ecdf = np.r_[0.0, jumps["ecdf"], 1.0] * 100
        lo = np.r_[0.0, jumps["ci_lower"], 1.0] * 100
        hi = np.r_[0.0, jumps["ci_upper"], 1.0] * 100
        ax.fill_between(x, lo, hi, step="post", color="#BBDEFB", alpha=0.5)
        ax.step(x, ecdf, where="post", color="#1565C0", lw=2)
    else:
        ax.fill_between(cr["xg"], cr["ci_lo"] * 100, cr["ci_hi"] * 100,
                        color="#BBDEFB", alpha=0.5)
        ax.plot(cr["xg"], cr["ecdf_v"] * 100, color="#1565C0", lw=2)
    ax.axhline(1.0, color="#D62728", ls="--", lw=1.5)
    for key, color in (("x_conservative", "#FF6F00"), ("x_ecdf", "#2E7D32"),
                       ("x_optimistic", "#1565C0")):
        ax.plot(cr[key], 1.0, "*", color=color, ms=11, zorder=5)


def draw_panel(ax, cr, jumps, exact):
    draw_series(ax, cr, jumps, exact)
    ax.set_xlim(cr["xg"][0], cr["xg"][-1])
    ax.set_ylim(0, 100)
    ax.set_xlabel("Injection Rate (m³/s)", fontsize=16)
    ax.set_ylabel("Violation probability (%)", fontsize=16)
    ax.tick_params(labelsize=13)
    ax.xaxis.set_major_locator(MultipleLocator(0.05))
    ax.xaxis.set_major_formatter(FormatStrFormatter("%.2f"))
    ax.grid(ls="--", lw=0.3, alpha=0.5)
    inset = ax.inset_axes([0.38, 0.12, 0.57, 0.50])
    draw_series(inset, cr, jumps, exact)
    inset.set_xlim(cr["x_conservative"] * 0.85, cr["x_optimistic"] * 1.15)
    inset.set_ylim(0, 8)
    inset.set_title("Left tail zoom (0–8%)", fontsize=12)
    inset.set_xlabel("Injection Rate (m³/s)", fontsize=11)
    inset.set_ylabel("Violation probability (%)", fontsize=11)
    inset.tick_params(labelsize=10)
    inset.xaxis.set_major_locator(MultipleLocator(0.005))
    inset.xaxis.set_major_formatter(FormatStrFormatter("%.3f"))
    inset.grid(ls="--", lw=0.3, alpha=0.4)
    specifications = [
        ("x_conservative", r"$q_k^{\star}$", "#FF6F00", "#E65100", "#FFF3E0", (-32, 18)),
        ("x_ecdf", "ECDF", "#2E7D32", "#1B5E20", "#E8F5E9", (0, 45)),
        ("x_optimistic", "Opt.", "#1565C0", "#0D47A1", "#E3F2FD", (32, 18)),
    ]
    for key, name, color, text_color, fill, offset in specifications:
        inset.annotate(
            f"{name}\n{cr[key]:.4f}", xy=(cr[key], 1.0), xytext=offset,
            textcoords="offset points", fontsize=11, color=text_color,
            fontweight="bold", ha="center",
            bbox=dict(boxstyle="round,pad=0.2", facecolor=fill, alpha=0.9, edgecolor=color),
            arrowprops=dict(arrowstyle="->", color=color, lw=1.5, mutation_scale=14, shrinkB=7),
        )
    _, connectors = ax.indicate_inset_zoom(inset, edgecolor="gray", alpha=0.4)
    for idx, connector in enumerate(connectors):
        connector.set_visible(idx < 2)
    return inset


def add_legend(fig, fontsize=14, y=0.89):
    fig.legend(handles=[
        Patch(facecolor="#BBDEFB", alpha=0.5, label="95% Bootstrap CI (B=10000)"),
        Line2D([0], [0], color="#1565C0", lw=2, label="Empirical CDF"),
        Line2D([0], [0], color="#D62728", lw=1.5, ls="--", label="Target p = 1%"),
    ], loc="upper center", bbox_to_anchor=(0.52, y), ncol=3, frameon=False,
               fontsize=fontsize, handlelength=2.2, columnspacing=1.4)


def save_checked(fig, path):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    for text in fig.findobj(match=plt.Text):
        # Out-of-range tick labels may exist as visible artists but are not drawn.
        if text.get_visible() and text.get_text() and text in fig.texts:
            box = text.get_window_extent(renderer)
            assert box.x0 >= 0 and box.y0 >= 0 and box.x1 <= fig.bbox.width and box.y1 <= fig.bbox.height, text.get_text()
    fig.savefig(path, dpi=220, facecolor="white")
    plt.close(fig)
    print(f"Saved: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jump-dir", type=Path, default=JUMP_DIR)
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    args = parser.parse_args()
    if args.outdir.exists():
        raise FileExistsError(f"Choose a new output directory: {args.outdir}")
    sources = [CACHE, SOURCE_PNG, args.jump_dir / "observed_jump_ecdf.csv",
               args.jump_dir / "verification.toml"]
    hashes = {str(p.relative_to(BASE)): sha256(p) for p in sources}
    cr, jumps, metadata = load_results(args.jump_dir)
    args.outdir.mkdir(parents=True)
    plt.rcParams.update({"font.family": "DejaVu Sans", "mathtext.fontset": "dejavusans"})

    fig, axes = plt.subplots(1, 2, figsize=(18, 9.5))
    fig.subplots_adjust(left=0.06, right=0.985, bottom=0.105, top=0.77, wspace=0.22)
    fig.suptitle("PoF ε = 0.01: 1500-point grid vs. observed-jump ECDF", fontsize=23,
                 fontweight="bold", y=0.974)
    fig.text(0.52, 0.918, "Step 1 · first-step initialization · M=128 · injection schedule element 6/12",
             ha="center", fontsize=15)
    add_legend(fig, y=0.886)
    for ax, exact, title in zip(axes, (False, True), (
        "Current: 1,500 grid points + straight segments",
        f"No grid: {len(jumps)} observed jumps + exact steps",
    )):
        draw_panel(ax, cr, jumps, exact)
        ax.set_title(title, fontsize=17, fontweight="bold", pad=14)
    save_checked(fig, args.outdir / "comparison_POF_eps0.01.png")

    fig, ax = plt.subplots(figsize=(10, 8.2))
    fig.subplots_adjust(left=0.12, right=0.98, bottom=0.11, top=0.815)
    fig.suptitle("Observed-jump ECDF (PoF ε = 0.01)", fontsize=24, fontweight="bold", y=0.978)
    fig.text(0.55, 0.919, "Step 1 · first-step initialization · M=128 · schedule element 6/12",
             ha="center", fontsize=12.5)
    add_legend(fig, fontsize=12, y=0.877)
    draw_panel(ax, cr, jumps, True)
    save_checked(fig, args.outdir / "cdf_POF_eps0.01_observed_jumps.png")

    dense_ranks = np.searchsorted(np.sort(cr["data"]), cr["xg"], side="right")
    jump_ranks = np.searchsorted(np.sort(cr["data"]), jumps["rate"], side="right")
    missing = jumps["rate"][~np.isin(jump_ranks, dense_ranks)]
    verification = dict(
        source_sha256=hashes, ensemble_size=int(cr["n"]), unique_jump_count=len(jumps),
        bootstrap=metadata, current_grid_size=len(cr["xg"]),
        ecdf_and_bands_exactly_equal_at_all_1500_old_grid_points=True,
        omitted_jump_locations_in_old_grid=missing.tolist(),
        q_conservative=float(cr["x_conservative"]), q_ecdf=float(cr["x_ecdf"]),
        q_optimistic=float(cr["x_optimistic"]), all_three_markers_unchanged=True,
        new_rendering="Right-continuous step(post), confidence fill step=post",
        no_grid_points_used_in_new_rendering="Only 89 data jumps plus two display boundaries",
        prior_mode="First monitoring-step initialization; no previous monitoring export",
    )
    assert hashes == {str(p.relative_to(BASE)): sha256(p) for p in sources}
    (args.outdir / "verification.json").write_text(json.dumps(verification, indent=2) + "\n")
    print(json.dumps(verification, indent=2))


if __name__ == "__main__":
    main()
