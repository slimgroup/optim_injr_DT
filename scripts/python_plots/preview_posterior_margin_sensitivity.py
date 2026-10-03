#!/usr/bin/env python3
"""Render explicitly parameterized relative-margin sensitivity previews on Slurm.

Only the pressure argument used by relative margin is transformed. The original
JLD2 files and the pressure-difference/saturation rows remain unchanged. The
transformation is recorded outside the image, for disclosure in the caption.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

os.environ.setdefault("MPLBACKEND", "Agg")
import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm, ListedColormap
from matplotlib.gridspec import GridSpec
from matplotlib.ticker import MaxNLocator
from matplotlib.transforms import Bbox
import numpy as np
from PIL import Image

from export_posterior_appendix_e import load_original, sha256, write_json
from preview_posterior_relative_margin import array_hash
from restyle_paper_pngs import CASES, verify_layout

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "plots/paper_figures/posterior_relative_margin_preview_20261002_v2"
HISTORICAL = ROOT / "plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909"
REFERENCE = ROOT / "plots/paper_figures/cvar_day728_sensitivity_1p22x.jld2"
ROWS = ["relative_margin", "pressure_diff", "sat"]


def prepare(out, mode, factor):
    out.mkdir(parents=True, exist_ok=False)
    (out / "arrays").mkdir()
    source = json.loads((BASE / "source_validation.json").read_text())
    hashes = json.loads((BASE / "delivery_checksums.json").read_text())
    assert sha256(BASE / "source_validation.json") == hashes["source_validation.json"]
    with h5py.File(REFERENCE, "r") as ref:
        reference_count = int(np.count_nonzero(ref["pres"][:] > ref["p_max"][:]))
    report = {"interpretation": "User-requested pressure sensitivity, not an unmodified posterior or a forward simulation",
        "transformation": ("p_used = pres_Hyd + factor * (p - pres_Hyd)" if mode == "increment" else "p_used = factor * p"),
        "relative_margin": "r_used = (p_max - p_used) / p_max; p_max = pres_Hyd + 4e6 Pa",
        "mode": mode, "factor": factor, "factor_shared_across_cases_and_steps": True,
        "selection_basis": "Exploratory visual sensitivity chosen by comparison with the reference's exceeding-cell count; not estimated or validated by a physical model",
        "count_definition": "Number of grid cells with posterior mean of the transformed margin below zero; not a probability or per-realization count",
        "mean_color_limits": [-.1, 1.], "zero_color_boundary_exact": True,
        "sample_axis": 0, "ddof": 0, "reference": str(REFERENCE.relative_to(ROOT)),
        "reference_sha256": sha256(REFERENCE), "reference_exceeding_cells": reference_count,
        "steps": {}}
    max_std = 0.
    for step in range(1, 5):
        unscaled = {}
        for stat in ("mean", "std"):
            name = f"arrays/{stat}_step{step}.npz"
            assert sha256(BASE / name) == hashes[name]
            with np.load(BASE / name) as cache:
                unscaled[stat] = {k: cache[k].copy() for k in cache.files}
        source_info = source["steps"][str(step)]
        path = ROOT / source_info["source"]
        assert sha256(path) == source_info["sha256"], path
        fields = {stat: {key: value for key, value in unscaled[stat].items() if not key.startswith("relative_margin")}
                  for stat in ("mean", "std")}
        audit = {"source": source_info["source"], "sha256": source_info["sha256"], "cases": {}}
        with h5py.File(path, "r") as f:
            hyd = f["pres_Hyd"][:].astype(np.float32)
            pmax = hyd + np.float32(4e6)
            for col, key in enumerate(("X_post1", "X_post2", "X_post3")):
                assert f[key].shape == (128, 2, 256, 512)
                pressure = f[key][:, 1].astype(np.float32)
                used = (hyd[None] + np.float32(factor) * (pressure - hyd[None])
                        if mode == "increment" else np.float32(factor) * pressure)
                margin = (pmax[None] - used) / pmax[None]
                mean = np.mean(margin, axis=0)
                std = np.std(margin, axis=0)
                original_mean = np.mean(pressure, axis=0, dtype=np.float64)
                transformed_mean = (hyd + factor * (original_mean - hyd)
                                    if mode == "increment" else factor * original_mean)
                expected_mean = (pmax - transformed_mean) / pmax
                expected_std = factor * np.std(pressure, axis=0, dtype=np.float64) / pmax
                np.testing.assert_allclose(mean, expected_mean, rtol=2e-5, atol=2e-6)
                np.testing.assert_allclose(std, expected_std, rtol=2e-4, atol=2e-6)
                for stat, field in (("mean", mean), ("std", std)):
                    assert np.isfinite(field).all()
                    fields[stat][f"relative_margin_{col}"] = field
                    for var in ("pressure_diff", "sat"):
                        np.testing.assert_array_equal(fields[stat][f"{var}_{col}"], unscaled[stat][f"{var}_{col}"])
                max_std = max(max_std, float(std.max()))
                audit["cases"][key] = {
                    "sample_count": 128,
                    "mean_field_exceeding_cells": int(np.count_nonzero(mean < 0)),
                    "unscaled_mean_field_exceeding_cells": int(np.count_nonzero(unscaled["mean"][f"relative_margin_{col}"] < 0)),
                    "min_mean_relative_margin": float(mean.min()), "max_mean_relative_margin": float(mean.max()),
                    "max_std_relative_margin": float(std.max()),
                    "per_sample_exceeding_cell_counts": np.count_nonzero(margin < 0, axis=(1, 2)).tolist(),
                    "mean_array_sha256": array_hash(mean), "std_array_sha256": array_hash(std),
                    "mean_identity_max_absolute_error": float(np.max(np.abs(mean - expected_mean))),
                    "std_identity_max_absolute_error": float(np.max(np.abs(std - expected_std))),
                    "retained_rows_exactly_equal": True}
                del pressure, used, margin
        assert sha256(path) == source_info["sha256"]
        audit["source_unchanged_after_read"] = True
        report["steps"][str(step)] = audit
        for stat in ("mean", "std"):
            with (out / "arrays" / f"{stat}_step{step}.npz").open("xb") as stream:
                np.savez_compressed(stream, **fields[stat])
        print(f"Step {step}: mean-field exceeding cells {[c['mean_field_exceeding_cells'] for c in audit['cases'].values()]}", flush=True)
    report["std_color_limits"] = [0., float(np.ceil(max_std * 1000) / 1000)]
    write_json(out / "validation.json", report)
    return report


def render(out, report):
    ppu = load_original("scripts/python_plots/plot_posterior_uncertainty.py", "sensitivity_style", out)
    colors = np.vstack([plt.cm.Reds_r(np.linspace(0., .85, 26)), plt.cm.Blues(np.linspace(0., 1., 230))])
    cmap_margin = ListedColormap(colors)
    cmap_margin.set_under(plt.cm.Reds_r(0.))
    edges = np.r_[np.linspace(-.1, 0., 27), np.linspace(0., 1., 231)[1:]]
    norm = BoundaryNorm(edges, 256)
    assert norm(-np.finfo(float).eps) < 26 and norm(0.) == 26
    assert norm(np.finfo(float).eps) >= 26
    matplotlib.rcParams.update({"font.family": "DejaVu Sans", "mathtext.fontset": "dejavusans"})
    entries = []
    token = f"{report['mode']}_{report['factor']:.5f}".replace(".", "p")
    for step in range(1, 5):
        for stat in ("mean", "std"):
            with np.load(out / "arrays" / f"{stat}_step{step}.npz") as f:
                fields = {k: f[k].copy() for k in f.files}
            with np.load(HISTORICAL / "validation" / f"posterior_{stat}_step{step}.npz") as f:
                old = {k: f[k].copy() for k in f.files}
            fig = plt.figure(figsize=(16, 8.2), dpi=400)
            gs = GridSpec(3, 4, figure=fig, width_ratios=[1, 1, 1, .035], hspace=.10,
                          wspace=.10, left=.115, right=.94, top=.95, bottom=.08)
            axes, cbaxes, checks = [], [], []
            labels = ["Relative margin", "Pressure difference", r"CO$_2$ saturation"]
            for row, var in enumerate(ROWS):
                old_row = 2 if var == "sat" else 0
                for col in range(3):
                    i = old_row * 4 + col
                    field = fields[f"{var}_{col}"]
                    ax = fig.add_subplot(gs[row, col]); axes.append(ax)
                    cmap = ppu.VAR_CONFIG[var]["cmap"] if stat == "mean" else "inferno"
                    if var == "relative_margin" and stat == "mean":
                        settings = {"cmap": cmap_margin, "norm": norm}
                    else:
                        lo, hi = report["std_color_limits"] if var == "relative_margin" else old[f"axes{i}_image0_clim"]
                        settings = {"cmap": cmap, "vmin": lo, "vmax": hi}
                    im = ax.imshow(field, extent=old[f"axes{i}_image0_extent"],
                                   origin=str(old[f"axes{i}_image0_origin"]), **settings)
                    np.testing.assert_array_equal(im.get_array(), field)
                    ax.set_xlim(old[f"axes{i}_xlim"]); ax.set_ylim(old[f"axes{i}_ylim"])
                    if var != "relative_margin":
                        np.testing.assert_array_equal(field, old[f"axes{i}_image0"])
                        np.testing.assert_array_equal(im.get_clim(), old[f"axes{i}_image0_clim"])
                        np.testing.assert_array_equal(im.cmap(np.linspace(0, 1, 256)), old[f"axes{i}_image0_cmap"])
                    if row == 0:
                        ax.set_title(CASES[col], fontsize=17, weight="bold", pad=5)
                        if stat == "mean":
                            count = int(np.count_nonzero(field < 0))
                            expected = report["steps"][str(step)]["cases"][f"X_post{col+1}"]["mean_field_exceeding_cells"]
                            assert count == expected
                            ax.text(.025, .95, f"min(mean $r$): {field.min():.4f}\nMean-field exceeding cells: {count:,}",
                                    transform=ax.transAxes, va="top", fontsize=11,
                                    bbox={"boxstyle": "round,pad=0.25", "facecolor": "white", "alpha": .86, "edgecolor": "0.6"})
                    if col == 0:
                        suffix = "\nstandard deviation" if stat == "std" else ""
                        ax.set_ylabel(labels[row] + suffix + "\nDepth [m]", fontsize=15, labelpad=12)
                    else:
                        ax.tick_params(labelleft=False)
                    if row == 2:
                        ax.set_xlabel("X [m]", fontsize=16)
                        ax.xaxis.set_major_locator(MaxNLocator(nbins=5))
                    else:
                        ax.tick_params(labelbottom=False)
                    ax.tick_params(labelsize=13, length=3, pad=2)
                    checks.append({"row": var, "case": col, "sha256": array_hash(field),
                                   "color_limits": list(im.get_clim()),
                                   "below_color_range": int(np.count_nonzero(field < im.get_clim()[0])),
                                   "above_color_range": int(np.count_nonzero(field > im.get_clim()[1]))})
                cax = fig.add_subplot(gs[row, 3]); cbaxes.append(cax)
                cb = fig.colorbar(im, cax=cax, extend="min" if row == 0 and stat == "mean" else "neither")
                cb.ax.tick_params(labelsize=13)
                if var == "pressure_diff":
                    cb.set_label("MPa", fontsize=15)
                elif var == "relative_margin":
                    cb.set_label(r"$r=(p_{\max}-p)/p_{\max}$" if stat == "mean" else r"$\mathrm{SD}(r)$", fontsize=15)
                    if stat == "mean":
                        cb.set_ticks([0., .25, .5, .75, 1.])
                        cb.ax.text(.5, -.07, r"$r<0$", transform=cb.ax.transAxes, ha="center", va="top", fontsize=11)
                    else:
                        cb.locator = MaxNLocator(nbins=5); cb.update_ticks()
            fig.canvas.draw()
            for row, cax in enumerate(cbaxes):
                box = axes[row * 3 + 2].get_position(); prior = cax.get_position()
                cax.set_position([prior.x0, box.y0, prior.width, box.height])
            renderer = fig.canvas.get_renderer()
            case_top = max(ax.title.get_window_extent(renderer).y1 for ax in axes[:3])
            title = "Posterior mean" if stat == "mean" else "Posterior standard deviation"
            main = fig.suptitle(title + rf" at monitoring step $k={step}$", fontsize=28, weight="bold",
                                y=(case_top + 6 * fig.dpi / 72) / fig.bbox.height, va="bottom")
            fig.canvas.draw()
            bbox = Bbox.from_bounds(0, 0, 16, main.get_window_extent(fig.canvas.get_renderer()).y1 / fig.dpi + .055)
            layout = verify_layout(fig, bbox)
            path = out / f"posterior_{stat}_relative_margin_sensitivity_{token}_step{step}.png"
            with path.open("xb") as stream:
                fig.savefig(stream, format="png", dpi=400, facecolor="white", bbox_inches=bbox, pad_inches=0)
            with Image.open(path) as image:
                size = list(image.size); image.verify()
            entries.append({"path": path.name, "source_step": step, "statistic": stat,
                            "sha256": sha256(path), "pixels": size, "layout": layout, "field_checks": checks})
            plt.close(fig)
            print(f"Rendered {path.name}", flush=True)
    write_json(out / "manifest.json", {"status": "sensitivity preview; do not substitute for unmodified posterior results without a caption explaining the transformation",
        "factor": report["factor"], "mode": report["mode"], "row_order": ROWS,
        "generating_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "slurm_job_id": os.environ.get("SLURM_JOB_ID"), "figures": entries})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("increment", "absolute"), required=True)
    parser.add_argument("--factor", type=float, required=True)
    args = parser.parse_args()
    if not np.isfinite(args.factor) or args.factor < 1.:
        parser.error("factor must be finite and at least one")
    out = args.output.resolve()
    report = prepare(out, args.mode, args.factor)
    render(out, report)
    for source in (Path(__file__), ROOT / "scripts/shell/submit/submit_posterior_margin_sensitivity.sh"):
        target = out / "provenance" / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as src, target.open("xb") as dst:
            shutil.copyfileobj(src, dst)
    write_json(out / "checksums.json", {str(p.relative_to(out)): sha256(p) for p in out.rglob("*") if p.is_file()})


if __name__ == "__main__":
    main()
