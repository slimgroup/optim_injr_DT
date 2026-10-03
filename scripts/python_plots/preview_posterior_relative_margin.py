#!/usr/bin/env python3
"""Preview relative margin / pressure difference / saturation from original inputs.

Run through Slurm. Never replace existing paper exports or modify input data.
The wide and focused previews differ only in the relative-margin color limits.
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
from matplotlib.gridspec import GridSpec
from matplotlib.ticker import MaxNLocator
from matplotlib.transforms import Bbox
import numpy as np
from PIL import Image

from export_posterior_appendix_e import BASELINE_COMMIT, load_original, sha256, write_json
from restyle_paper_pngs import CASES, verify_layout

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909"
ROWS = ["relative_margin", "pressure_diff", "sat"]
STATS = ("mean", "std")


def array_hash(a):
    import hashlib
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


def prepare(out):
    out.mkdir(parents=True, exist_ok=False)
    inputs = json.loads((REFERENCE / "input_checksums.json").read_text())
    cache_hashes = json.loads((REFERENCE / "delivery_checksums.json").read_text())
    (out / "arrays").mkdir()
    report = {"formula": "r = (p_max - p) / p_max; p_max = pres_Hyd + 4e6 Pa",
              "row_order": ROWS, "sample_axis": 0, "ddof": 0,
              "calculation_dtype": "float32, matching historical loader",
              "pressure_amplification_factor": 1.0, "steps": {}}
    extrema = {s: [float("inf"), float("-inf")] for s in STATS}
    for step in range(1, 5):
        relative = f"data/posterior/three_set_posteriro_samples_t{step}_pof_cvar.jld2"
        source = ROOT / relative
        before = sha256(source)
        assert before == inputs[relative]["sha256"], f"Historical input changed: {relative}"
        caches = {}
        for stat in STATS:
            name = f"validation/posterior_{stat}_step{step}.npz"
            assert sha256(REFERENCE / name) == cache_hashes[name]
            with np.load(REFERENCE / name, allow_pickle=False) as f:
                caches[stat] = {k: f[k].copy() for k in f.files}
        arrays = {s: {} for s in STATS}
        audit = {"source": relative, "sha256": before, "cases": {}}
        with h5py.File(source, "r") as f:
            hyd = f["pres_Hyd"][:].astype(np.float32)
            pmax = hyd + np.float32(4e6)
            assert np.isfinite(pmax).all() and (pmax > 0).all()
            audit["p_max_Pa_range"] = [float(pmax.min()), float(pmax.max())]
            for col, key in enumerate(("X_post1", "X_post2", "X_post3")):
                raw = f[key][:]
                assert raw.shape == (128, 2, 256, 512), (key, raw.shape)
                pressure = raw[:, 1].astype(np.float32)
                sat = raw[:, 0].astype(np.float32)
                del raw
                margin = (pmax[None] - pressure) / pmax[None]
                pressure_diff_mpa = (pressure - hyd[None]) * 1e-6
                assert np.isfinite(margin).all()
                case = {"sample_count": len(pressure), "statistics": {}}
                for stat in STATS:
                    operation = np.mean if stat == "mean" else np.std
                    derived = operation(margin, axis=0)
                    # Reproduce the retained rows independently from the original samples.
                    for var, values, old_row in (("pressure_diff", pressure_diff_mpa, 0),
                                                 ("sat", sat, 2)):
                        field = operation(values, axis=0)
                        old = caches[stat][f"axes{old_row * 4 + col}_image0"]
                        np.testing.assert_array_equal(field, old)
                        arrays[stat][f"{var}_{col}"] = old
                    # The identities use float64 reductions as an independent check.
                    # Final maps retain the established float32 reduction convention.
                    if stat == "mean":
                        identity = (pmax - np.mean(pressure, axis=0, dtype=np.float64)) / pmax
                    else:
                        identity = np.std(pressure, axis=0, dtype=np.float64) / pmax
                    np.testing.assert_allclose(derived, identity, rtol=2e-5, atol=2e-6)
                    arrays[stat][f"relative_margin_{col}"] = derived
                    lo, hi = float(derived.min()), float(derived.max())
                    extrema[stat][0] = min(extrema[stat][0], lo)
                    extrema[stat][1] = max(extrema[stat][1], hi)
                    case["statistics"][stat] = {
                        "relative_margin_min_max": [lo, hi],
                        "relative_margin_spatial_percentiles_1_50_99": np.percentile(derived, [1, 50, 99]).tolist(),
                        "relative_margin_array_sha256": array_hash(derived),
                        "identity_max_absolute_error": float(np.abs(derived - identity).max()),
                        "pressure_difference_and_saturation_exactly_equal_to_paper_cache": True}
                audit["cases"][key] = case
                del pressure, sat, margin, pressure_diff_mpa
        assert sha256(source) == before, f"Input changed during preview: {relative}"
        audit["source_unchanged_after_read"] = True
        for stat in STATS:
            with (out / "arrays" / f"{stat}_step{step}.npz").open("xb") as stream:
                np.savez_compressed(stream, **arrays[stat])
        report["steps"][str(step)] = audit
        print(f"Step {step}: original input verified; retained rows exactly match; margin computed", flush=True)
    # Full plotted range, shared across all four steps AND all three cases.
    # No percentile clipping, case-specific pressure scaling, or changed data.
    mean_lo = np.floor(extrema["mean"][0] * 100) / 100
    mean_hi = np.ceil(extrema["mean"][1] * 100) / 100
    std_hi = np.ceil(extrema["std"][1] * 1000) / 1000
    report["relative_margin_extrema_all_steps_cases"] = extrema
    report["relative_margin_color_limits"] = {
        "wide": {"mean": [-.1, 1.0], "std": [0., 1.]},
        "focused": {"mean": [float(mean_lo), float(mean_hi)], "std": [0., float(std_hi)]}}
    report["wide_std_note"] = "Nonnegative 0..1 scale; negative standard deviation is not meaningful."
    write_json(out / "source_validation.json", report)
    print(json.dumps(report["relative_margin_color_limits"]), flush=True)


def render(out, variants, steps):
    report = json.loads((out / "source_validation.json").read_text())
    ppu = load_original("scripts/python_plots/plot_posterior_uncertainty.py", "margin_preview_style", out)
    matplotlib.rcParams.update({"font.family": "DejaVu Sans", "mathtext.fontset": "dejavusans"})
    entries = []
    labels = ["Relative margin", "Pressure difference", r"CO$_2$ saturation"]
    for step in steps:
        for stat in STATS:
            with np.load(out / "arrays" / f"{stat}_step{step}.npz") as f:
                fields = {k: f[k].copy() for k in f.files}
            with np.load(REFERENCE / "validation" / f"posterior_{stat}_step{step}.npz") as f:
                old = {k: f[k].copy() for k in f.files}
            for variant in variants:
                fig = plt.figure(figsize=(16, 8.2), dpi=400)
                gs = GridSpec(3, 4, figure=fig, width_ratios=[1, 1, 1, .035], hspace=.10,
                              wspace=.10, left=.115, right=.94, top=.95, bottom=.08)
                axes, cbaxes, checks = [], [], []
                for row, var in enumerate(ROWS):
                    old_row = 0 if var != "sat" else 2
                    for col in range(3):
                        index = old_row * 4 + col
                        ax = fig.add_subplot(gs[row, col]); axes.append(ax)
                        clim = (report["relative_margin_color_limits"][variant][stat]
                                if var == "relative_margin" else old[f"axes{index}_image0_clim"])
                        cmap = ppu.VAR_CONFIG[var]["cmap"] if stat == "mean" else "inferno"
                        field = fields[f"{var}_{col}"]
                        im = ax.imshow(field, cmap=cmap, vmin=clim[0], vmax=clim[1],
                                       extent=old[f"axes{index}_image0_extent"],
                                       origin=str(old[f"axes{index}_image0_origin"]))
                        ax.set_xlim(old[f"axes{index}_xlim"]); ax.set_ylim(old[f"axes{index}_ylim"])
                        np.testing.assert_array_equal(im.get_array(), field)
                        if var != "relative_margin":
                            np.testing.assert_array_equal(field, old[f"axes{index}_image0"])
                            np.testing.assert_array_equal(im.get_clim(), old[f"axes{index}_image0_clim"])
                            np.testing.assert_array_equal(im.cmap(np.linspace(0, 1, 256)),
                                                          old[f"axes{index}_image0_cmap"])
                        else:
                            assert field.min() >= clim[0] and field.max() <= clim[1]
                        # Preserve historical saturation limits, including float32
                        # mean values a few ulps above the existing 0.9 maximum.
                        outside = int(np.count_nonzero((field < clim[0]) | (field > clim[1])))
                        checks.append({"row": var, "case": col, "sha256": array_hash(field),
                                       "clim": list(clim), "cells_outside_color_limits": outside,
                                       "no_added_color_clipping": True,
                                       "maximum_upper_color_limit_excess": max(0., float(field.max()) - float(clim[1]))})
                        if row == 0:
                            ax.set_title(CASES[col], fontsize=17, weight="bold", pad=5)
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
                    cax = fig.add_subplot(gs[row, 3]); cbaxes.append(cax)
                    cb = fig.colorbar(im, cax=cax); cb.ax.tick_params(labelsize=13)
                    if var == "pressure_diff":
                        cb.set_label("MPa", fontsize=15)
                    if var == "relative_margin":
                        cb.set_label(r"$r=(p_{\max}-p)/p_{\max}$" if stat == "mean" else r"$\mathrm{SD}(r)$",
                                     fontsize=15)
                        cb.locator = MaxNLocator(nbins=5); cb.update_ticks()
                fig.canvas.draw()
                for row, cax in enumerate(cbaxes):
                    box = axes[row * 3 + 2].get_position(); prev = cax.get_position()
                    cax.set_position([prev.x0, box.y0, prev.width, box.height])
                renderer = fig.canvas.get_renderer()
                case_top = max(ax.title.get_window_extent(renderer).y1 for ax in axes[:3])
                title = "Posterior mean" if stat == "mean" else "Posterior standard deviation"
                main = fig.suptitle(title + rf" at monitoring step $k={step}$", fontsize=28, weight="bold",
                                    y=(case_top + 6 * fig.dpi / 72) / fig.bbox.height, va="bottom")
                fig.canvas.draw()
                upper = main.get_window_extent(fig.canvas.get_renderer()).y1 / fig.dpi + .055
                bbox = Bbox.from_bounds(0, 0, 16, upper)
                layout = verify_layout(fig, bbox)
                stem = f"posterior_{stat}_relative_margin_pressurediff_sat_step{step}"
                target = out / variant / (stem + ".png")
                target.parent.mkdir(exist_ok=True)
                with target.open("xb") as stream:
                    fig.savefig(stream, format="png", dpi=400, facecolor="white", bbox_inches=bbox, pad_inches=0)
                with Image.open(target) as image:
                    size = list(image.size); image.verify()
                entries.append({"path": str(target.relative_to(out)), "step": step, "statistic": stat,
                                "variant": variant, "sha256": sha256(target), "pixels": size,
                                "layout": layout, "field_checks": checks})
                plt.close(fig)
                print(f"Rendered {variant}/{stem}.png", flush=True)
    write_json(out / "manifest.json", {"status": "preview, not installed into paper paths",
        "row_order": ROWS, "source_validation": "source_validation.json", "historical_commit": BASELINE_COMMIT,
        "generating_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "slurm_job_id": os.environ.get("SLURM_JOB_ID"), "python_numpy_matplotlib": [__import__("sys").version, np.__version__, matplotlib.__version__],
        "case_specific_pressure_amplification": False, "figures": entries})
    for source in (Path(__file__), ROOT / "scripts/shell/submit/submit_posterior_margin_preview.sh",
                   ROOT / "scripts/python_plots/restyle_paper_pngs.py", ROOT / "scripts/python_plots/export_posterior_appendix_e.py"):
        target = out / "provenance" / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as src, target.open("xb") as dst:
            shutil.copyfileobj(src, dst)
    write_json(out / "checksums.json", {str(p.relative_to(out)): sha256(p) for p in sorted(out.rglob("*")) if p.is_file()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phase", choices=("all", "prepare", "render"), default="all")
    parser.add_argument("--variants", nargs="+", choices=("wide", "focused"), default=["wide", "focused"])
    parser.add_argument("--steps", nargs="+", type=int, choices=(1, 2, 3, 4), default=[1, 2, 3, 4])
    args = parser.parse_args()
    if args.phase in ("all", "prepare"):
        prepare(args.output.resolve())
    if args.phase in ("all", "render"):
        render(args.output.resolve(), args.variants, args.steps)


if __name__ == "__main__":
    main()
