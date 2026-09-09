#!/usr/bin/env python3
"""Re-export the 11 historical paper figures without changing their numerics.

Run on a compute node. Original scripts are pinned to BASELINE_COMMIT because
the active working tree may contain a different statistical selection method.
No source data or historical assets are replaced. Replacing canonical exports
requires an explicit, checksum-matched previous handoff and creates backups.
"""

from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import types
from datetime import datetime, timezone
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
BASELINE_COMMIT = "279108409a3d165ceeed430502c583f9c05e3d3b"
os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-paper-export")
os.environ.setdefault("MPLBACKEND", "Agg")

import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.figure import Figure
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from matplotlib.text import Annotation, Text
from matplotlib.ticker import FormatStrFormatter, MaxNLocator
from matplotlib.transforms import Bbox
import numpy as np

ROW_VARS = ["pressure_diff", "pressure", "sat"]
TITLE_HEADER_INCHES = 0.5
CASE_TITLES = [
    r"(a) PoF $\varepsilon=0.0$",
    r"(b) PoF $\varepsilon=0.01$",
    r"(c) CVaR $\gamma=0.1$, $\alpha=0.01$",
]
EXPECTED_MISSING = {2: [113], 3: [11, 43, 54, 117], 4: [5, 16, 28, 36, 47, 117]}
SOURCE_PATHS = [
    "scripts/python_plots/plot_posterior_uncertainty.py",
    "scripts/python_plots/plot_posterior_summary_all_steps.py",
    *[f"scripts/python_plots/posterior_stats/plot_step{k}_paired_posterior_stats.py" for k in (2, 3, 4)],
]


def rel(path):
    return str(Path(path).resolve().relative_to(ROOT))


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write("\n")


def copy_new(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with Path(source).open("rb") as src, target.open("xb") as dst:
        shutil.copyfileobj(src, dst)
    assert sha256(source) == sha256(target)


def load_original(source, name, handoff):
    code = subprocess.check_output(["git", "show", f"{BASELINE_COMMIT}:{source}"], cwd=ROOT)
    snapshot = handoff / "provenance" / "original_sources" / source
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    snapshot.write_bytes(code)
    module = types.ModuleType(name)
    module.__file__ = str(ROOT / source)
    sys.modules[name] = module
    exec(compile(code, module.__file__, "exec"), module.__dict__)
    return module


def capture_plot(func, *args, **kwargs):
    """Use the original plotting function, preventing its save/close side effects."""
    with patch.object(Figure, "savefig"), patch.object(plt, "close"), redirect_stdout(io.StringIO()):
        func(*args, **kwargs)
        fig = plt.gcf()
    fig.canvas.draw()
    return fig


def all_axes(fig):
    for ax in fig.axes:
        yield ax
        yield from ax.child_axes


def numeric_contents(fig):
    """Snapshot plotted values, not screen positions or presentation text."""
    arrays = {}
    def put(key, value):
        arrays[key] = np.asarray(value).copy()
    for i, ax in enumerate(all_axes(fig)):
        prefix = f"axes{i}"
        put(prefix + "_xlim", ax.get_xlim())
        put(prefix + "_ylim", ax.get_ylim())
        for j, im in enumerate(ax.images):
            key = f"{prefix}_image{j}"
            put(key, im.get_array())
            put(key + "_clim", im.get_clim())
            put(key + "_extent", im.get_extent())
            put(key + "_cmap", im.cmap(np.linspace(0, 1, 256)))
            put(key + "_origin", im.origin)
        for j, line in enumerate(ax.lines):
            put(f"{prefix}_line{j}_x", line.get_xdata())
            put(f"{prefix}_line{j}_y", line.get_ydata())
        for j, collection in enumerate(ax.collections):
            for k, path in enumerate(collection.get_paths()):
                put(f"{prefix}_collection{j}_path{k}", path.vertices)
            if collection.get_array() is not None:
                put(f"{prefix}_collection{j}_array", collection.get_array())
        for j, artist in enumerate(ax.patches):
            if isinstance(artist, Rectangle):
                put(f"{prefix}_patch{j}", [artist.get_x(), artist.get_y(), artist.get_width(), artist.get_height()])
            else:
                put(f"{prefix}_patch{j}", artist.get_path().vertices)
        for j, text in enumerate(ax.texts):
            if isinstance(text, Annotation):
                put(f"{prefix}_annotation{j}_xy", text.xy)
    return arrays


def array_hashes(arrays):
    return {key: {"shape": list(a.shape), "dtype": str(a.dtype),
                  "sha256": hashlib.sha256(a.tobytes()).hexdigest()}
            for key, a in arrays.items()}


def verify_numeric_contents(before, fig):
    after = numeric_contents(fig)
    assert before.keys() == after.keys(), "Plot structure changed"
    for key in before:
        np.testing.assert_array_equal(before[key], after[key], err_msg=key)
    return array_hashes(after)


def format_posterior(fig, stat):
    fig._suptitle.remove()
    fig._suptitle = None
    fig.set_size_inches(16, 8.2)
    fig.subplots_adjust(left=0.105, right=0.945, top=0.95, bottom=0.08)
    labels = ["Pressure difference", "Reservoir pressure", r"CO$_2$ saturation"]
    field_axes = [ax for ax in fig.axes if ax.images]
    color_axes = [ax for ax in fig.axes if not ax.images]
    for row in range(3):
        for col in range(3):
            ax = field_axes[3 * row + col]
            if row == 0:
                ax.set_title(CASE_TITLES[col], fontsize=17, fontweight="bold", pad=5)
            if col == 0:
                label = labels[row] + ("\nstandard deviation" if stat == "std" else "")
                ax.set_ylabel(label + "\nDepth [m]", fontsize=15, labelpad=8)
            ax.tick_params(labelsize=13)
            if row == 2:
                ax.set_xlabel("X [m]", fontsize=16)
                ax.xaxis.set_major_locator(MaxNLocator(nbins=5))
    fig.canvas.draw()
    for row, cax in enumerate(color_axes):
        bounds = field_axes[3 * row + 2].get_position()
        old = cax.get_position()
        cax.set_position([old.x0, bounds.y0, old.width, bounds.height])
        cax.tick_params(labelsize=13)
        if row < 2:
            cax.set_ylabel("MPa", fontsize=15)


def format_statistical(fig, results, step):
    fig._suptitle.remove()
    fig._suptitle = None
    fig.set_size_inches(18, 9.4)
    fig.subplots_adjust(left=0.065, right=0.987, top=0.93, bottom=0.17, wspace=0.24, hspace=0.17)
    for col, result in enumerate(results):
        spec, x, q01, qlo, qhi, grid, ecdf, clo, chi = result
        hist, cdf = fig.axes[col], fig.axes[3 + col]
        # Retain the historical interval coordinates for numerical auditing,
        # but omit its shading from the paper presentation at the user's request.
        spans = list(hist.patches)[len(hist.containers[0].patches):]
        assert len(spans) == 1, "Expected one historical quantile-interval span"
        for span in spans:
            span.set_visible(False)
        qualification = (f"{len(x)} feasible completed; {128-len(x)} excluded" if col == 0
                         else f"{len(x)} completed samples")
        hist.set_title(CASE_TITLES[col] + "\n" + qualification, fontsize=14, fontweight="bold", pad=8)
        hist.set_ylabel("Count", fontsize=14)
        hist.texts[0].set_text(f"mean={np.mean(x):.5f}\nmedian={np.median(x):.5f}\n1% quantile={q01:.5f}")
        hist.texts[0].set_fontsize(11)
        cdf.set_xlabel(r"Injection-rate endpoint $q$ (m$^3$/s)", fontsize=14)
        cdf.set_ylabel("Cumulative probability (%)", fontsize=13)
        for ax in (hist, cdf):
            ax.tick_params(labelsize=11)
        inset = cdf.child_axes[0]
        inset.set_axes_locator(None)
        # Reattach a relative locator after enlarging the inset within its parent.
        from matplotlib.transforms import Bbox
        def locate_inset(ax, renderer, parent=cdf):
            box = Bbox.from_bounds(0.40, 0.12, 0.57, 0.45)
            return box.transformed(parent.transAxes).transformed(fig.transFigure.inverted())
        inset.set_axes_locator(locate_inset)
        inset.set_title("Left-tail zoom", fontsize=10, pad=4)
        inset.xaxis.set_major_locator(MaxNLocator(nbins=3))
        inset.xaxis.set_major_formatter(FormatStrFormatter("%.3f"))
        inset.tick_params(labelsize=9)
        annotations = [text for text in inset.texts if isinstance(text, Annotation)]
        for ann, label, pos in zip(annotations, [r"$q_k^*$", "ECDF", "Opt."],
                                   [(0.14, 0.43), (0.48, 0.72), (0.84, 0.43)]):
            ann.set_text(label + f"\n{ann.xy[0]:.5f}")
            ann.set_fontsize(9)
            ann.anncoords = "axes fraction"
            ann.set_position(pos)
    handles = [
        Line2D([], [], color="#1E8449", lw=2, label="Sample 1% quantile"),
        Line2D([], [], color="#1F618D", lw=2, label="Empirical CDF"),
        Patch(facecolor="#AED6F1", alpha=0.55, label="Pointwise 95% bootstrap confidence interval"),
        Line2D([], [], color="#C0392B", lw=1.2, ls="--", label="1% threshold"),
    ]
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.5, 0.015),
               ncol=2, fontsize=11, frameon=False, columnspacing=2)


def add_monitoring_title(fig, family, stem, step):
    """Add a header outside the existing canvas; keep every panel at its size."""
    if family == "posterior":
        quantity = "Posterior mean" if stem.startswith("posterior_mean_") else "Posterior standard deviation"
    else:
        quantity = "Injection-rate endpoint histogram and ECDF"
    title = quantity + rf" at monitoring step $k={step}$"
    width, height = fig.get_size_inches()
    fig.suptitle(title, x=0.5, y=1 + TITLE_HEADER_INCHES / (2 * height),
                 fontsize=20, fontweight="bold", va="center")
    # Expanding only the saved bounding box avoids resizing/repositioning any
    # existing axes, labels, legends, colorbars, or annotation boxes.
    return title, Bbox.from_bounds(0, 0, width, height + TITLE_HEADER_INCHES)


def layout_check(fig, extra_top_inches=0):
    """Check visible text against the canvas, excluding off-range tick labels."""
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    bounds = Bbox.from_extents(fig.bbox.x0, fig.bbox.y0, fig.bbox.x1,
                              fig.bbox.y1 + extra_top_inches * fig.dpi)
    problems = []
    unrendered_ticks = set()
    for ax in all_axes(fig):
        for axis in (ax.xaxis, ax.yaxis):
            lo, hi = sorted(axis.get_view_interval())
            visible_boxes = []
            for tick in axis.get_major_ticks() + axis.get_minor_ticks():
                if not lo <= tick.get_loc() <= hi:
                    unrendered_ticks.update([id(tick.label1), id(tick.label2)])
                elif tick.label1.get_visible() and tick.label1.get_text():
                    visible_boxes.append(tick.label1.get_window_extent(renderer))
            for left, right in zip(visible_boxes, visible_boxes[1:]):
                if left.overlaps(right):
                    problems.append(f"Overlapping tick labels on {axis.axis_name} axis")
    for text in fig.findobj(Text):
        if not text.get_visible() or not text.get_text() or id(text) in unrendered_ticks:
            continue
        box = text.get_window_extent(renderer)
        if box.width and box.height and (box.x0 < bounds.x0-1 or box.y0 < bounds.y0-1
                                        or box.x1 > bounds.x1+1 or box.y1 > bounds.y1+1):
            problems.append(text.get_text())
    if problems:
        raise ValueError(f"Text outside figure canvas: {problems}")
    if fig._suptitle is not None:
        title_box = fig._suptitle.get_window_extent(renderer)
        assert title_box.y0 >= fig.bbox.y1, "Global title overlaps the existing canvas"
    return {"visible_text_within_canvas": True, "tick_labels_do_not_overlap": True,
            "figsize_inches": list(fig.get_size_inches()), "added_header_inches": extra_top_inches}


class Export:
    def __init__(self, args):
        self.args = args
        self.handoff = args.handoff_dir.resolve()
        self.handoff.mkdir(parents=True, exist_ok=False)
        self.inputs = {}
        self.figures = []
        self.details = {}
        self.reference = None
        if args.reference_handoff:
            self.reference = json.loads((args.reference_handoff / "manifest.json").read_text())
        self.head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip()
        source_files = SOURCE_PATHS + [rel(Path(__file__)), "scripts/shell/submit/submit_posterior_appendix_e_export.sh"]
        for source in source_files:
            self.track(ROOT / source, "generating source, working tree")
            copy_new(ROOT / source, self.handoff / "provenance" / "export_sources" / source)
        diff = subprocess.check_output(["git", "diff", "--", "scripts", "docs"], cwd=ROOT)
        (self.handoff / "provenance" / "working_tree.patch").write_bytes(diff)

    def track(self, path, role):
        path = Path(path)
        key = rel(path)
        if key not in self.inputs:
            self.inputs[key] = {"sha256": sha256(path), "size_bytes": path.stat().st_size, "role": role}
        return key

    def original(self, source, name):
        return load_original(source, name, self.handoff)

    def save(self, fig, before, family, stem, step, source_png, paper_basename, datasets, script):
        title, export_bbox = add_monitoring_title(fig, family, stem, step)
        layout = layout_check(fig, extra_top_inches=TITLE_HEADER_INCHES)
        numeric = verify_numeric_contents(before, fig)
        canonical_path = f"plots/paper_figures/{family}/{stem}.png"
        reference = None
        if self.reference:
            reference = next(e for e in self.reference["figures"] if e["canonical_export_path"] == canonical_path)
            old_audit = json.loads((self.args.reference_handoff / reference["numeric_validation"]).read_text())
            assert numeric == old_audit["numeric_arrays"], f"Numeric content differs from previous export: {stem}"
        self.track(source_png, "preserved original PNG")
        outputs = {}
        for ext in self.args.formats:
            dest = self.handoff / family / f"{stem}.{ext}"
            dest.parent.mkdir(parents=True, exist_ok=True)
            with dest.open("xb") as f:
                fig.savefig(f, format=ext, dpi=400, facecolor="white", bbox_inches=export_bbox, pad_inches=0,
                            metadata={"Creator": "optim_injr_DT historical paper exporter"} if ext == "pdf" else None)
            outputs[ext] = {"handoff_path": str(dest.relative_to(self.handoff)), "sha256": sha256(dest)}
        plt.close(fig)
        png = self.handoff / family / f"{stem}.png"
        if reference:
            from PIL import Image
            old_png = self.args.reference_handoff / reference["outputs"]["png"]["handoff_path"]
            assert sha256(old_png) == reference["output_sha256"]
            with Image.open(old_png) as previous, Image.open(png) as current:
                if self.args.reference_change == "hide-quantile-interval":
                    assert current.size == previous.size
                    changed = np.any(np.asarray(previous) != np.asarray(current), axis=2)
                    if family == "posterior":
                        assert not np.any(changed), f"Posterior pixels changed: {stem}"
                        layout["previous_image_region_pixel_identical"] = True
                    else:
                        self.verify_removed_shading(fig, changed, stem, layout)
                else:
                    assert current.width == previous.width and current.height > previous.height
                    original_region = current.crop((0, current.height - previous.height, current.width, current.height))
                    np.testing.assert_array_equal(np.asarray(previous), np.asarray(original_region),
                                                  err_msg=f"Existing image region changed: {stem}")
                    layout["previous_image_region_pixel_identical"] = True
        compat = self.handoff / "paper_compat" / family / paper_basename
        copy_new(png, compat)
        audit = self.handoff / "validation" / f"{stem}.npz"
        audit.parent.mkdir(parents=True, exist_ok=True)
        with audit.open("xb") as f:
            np.savez_compressed(f, **before)
        write_json(audit.with_suffix(".json"), {"unchanged": True, "numeric_arrays": numeric, "layout": layout})
        self.figures.append({
            "source_path": rel(source_png), "source_step": step,
            "canonical_export_path": canonical_path, "global_title": title,
            "paper_current_path": f"figs/{family}/{paper_basename}",
            "input_dataset": datasets, "generating_script": script,
            "historical_commit": BASELINE_COMMIT,
            "source_sha256": self.inputs[rel(source_png)]["sha256"],
            "output_sha256": sha256(png), "compat_sha256": sha256(compat),
            "compat_path": str(compat.relative_to(self.handoff)), "outputs": outputs,
            "numeric_validation": str(audit.with_suffix(".json").relative_to(self.handoff)),
            "numeric_snapshot_sha256": sha256(audit),
        })
        print(f"Validated and exported {stem}", flush=True)

    @staticmethod
    def verify_removed_shading(fig, changed, stem, layout):
        allowed = np.zeros(changed.shape, dtype=bool)
        height, width = changed.shape
        scale = width / fig.bbox.width
        # Only the old purple spans and the shared bottom legend may change.
        regions = []
        for ax in fig.axes[:3]:
            span = list(ax.patches)[len(ax.containers[0].patches):][0]
            assert not span.get_visible()
            box = span.get_window_extent(fig.canvas.get_renderer())
            x0 = max(0, int(np.floor(box.x0 * scale)) - 3)
            x1 = min(width, int(np.ceil(box.x1 * scale)) + 3)
            y0 = max(0, height - int(np.ceil(box.y1 * scale)) - 3)
            y1 = min(height, height - int(np.floor(box.y0 * scale)) + 3)
            allowed[y0:y1, x0:x1] = True
            regions.append([x0, y0, x1, y1])
        legend_top = height - int(np.ceil(fig.bbox.height * scale * 0.12))
        allowed[legend_top:, :] = True
        assert not np.any(changed & ~allowed), f"Unexpected pixel changes: {stem}"
        assert np.any(changed), f"Expected the quantile interval to disappear: {stem}"
        layout.update({"pixels_outside_removed_shading_and_legend_identical": True,
                       "removed_interval_regions_pixels": regions,
                       "histogram_quantile_interval_visible": False})

    def posterior(self):
        if self.args.reuse_posterior_from_reference:
            self.reuse_posterior()
            return
        ppu = self.original(SOURCE_PATHS[0], "plot_posterior_uncertainty")
        summary = self.original(SOURCE_PATHS[1], "historical_posterior_summary")
        loaded, datasets, shapes = [], [], {}
        # All four steps are required even for a subset: color limits are shared.
        for step, cfg in enumerate(summary.STEP_CONFIG, 1):
            self.track(cfg["input"], "posterior input")
            with h5py.File(cfg["input"], "r") as f:
                shapes[step] = {key: {"shape": list(f[key].shape), "dtype": str(f[key].dtype)}
                                for key in [*ppu.CASES, "pres_Hyd"]}
            samples, _ = ppu.load_samples(str(cfg["input"]))
            loaded.append(samples)
            datasets.append([f"{rel(cfg['input'])}::{key}" for key in [*ppu.CASES, "pres_Hyd"]])
        ranges = {stat: summary.compute_shared_ranges(loaded, ROW_VARS, stat) for stat in ("mean", "std")}
        self.details["posterior"] = {"inputs": shapes, "shared_color_limits": ranges,
                                      "sample_axis": 0, "ddof": 0, "display_dtype": "float32",
                                      "row_order": ROW_VARS, "grid_orientation": "z,x; upper origin"}
        for step, (cfg, samples, inputs) in enumerate(zip(summary.STEP_CONFIG, loaded, datasets), 1):
            if step not in self.args.steps:
                continue
            for stat in ("mean", "std"):
                basename = f"state_{stat}_pressurediff_pressure_sat_all_cases.png"
                fig = capture_plot(ppu.plot_paper_style_summary, samples, str(self.handoff), stat, cfg["label"],
                                   row_vars=ROW_VARS, out_name=basename, value_ranges=ranges[stat])
                before = numeric_contents(fig)
                format_posterior(fig, stat)
                self.save(fig, before, "posterior", f"posterior_{stat}_step{step}", step,
                          cfg["outdir"] / basename, basename.replace(".png", f"_t{step}.png"), inputs,
                          SOURCE_PATHS[1])

    def reuse_posterior(self):
        """Copy the eight verified posterior figures without re-rendering them."""
        previous = self.args.reference_handoff
        checksums = json.loads((previous / "checksums.json").read_text())
        previous_inputs = json.loads((previous / "input_checksums.json").read_text())
        details_path = "validation/scientific_details.json"
        assert sha256(previous / details_path) == checksums[details_path]
        self.details["posterior"] = json.loads((previous / details_path).read_text())["posterior"]
        for source in SOURCE_PATHS[:2]:
            name = "provenance/original_sources/" + source
            assert sha256(previous / name) == checksums[name]
            copy_new(previous / name, self.handoff / name)
        for old_entry in self.reference["figures"]:
            if "/posterior/" not in old_entry["canonical_export_path"]:
                continue
            if old_entry["source_step"] not in self.args.steps:
                continue
            entry = dict(old_entry)
            assert set(self.args.formats) == set(entry["outputs"]), "Reused posterior formats must match"
            names = [info["handoff_path"] for info in entry["outputs"].values()]
            names += [entry["compat_path"], entry["numeric_validation"],
                      str(Path(entry["numeric_validation"]).with_suffix(".npz"))]
            for name in names:
                assert sha256(previous / name) == checksums[name], name
                copy_new(previous / name, self.handoff / name)
            paths = {dataset.split("::")[0] for dataset in entry["input_dataset"]}
            paths.add(entry["source_path"])
            for name in paths:
                self.track(ROOT / name, previous_inputs[name]["role"])
                assert self.inputs[name]["sha256"] == previous_inputs[name]["sha256"], name
            entry["reused_from_handoff"] = str(previous)
            self.figures.append(entry)
            print(f"Reused byte-identical {entry['canonical_export_path']}", flush=True)

    def statistical(self):
        queue = subprocess.check_output(["squeue", "--me", "-h", "-o", "%i|%j|%T|%o"], text=True)
        (self.handoff / "provenance" / "squeue.txt").write_text(queue)
        if any("optim_inject" in line or "paired_posterior" in line for line in queue.splitlines()):
            raise RuntimeError("Active optimization jobs require sample-specific review; no rates were exported")
        for step in (2, 3, 4):
            if step not in self.args.steps:
                continue
            script = f"scripts/python_plots/posterior_stats/plot_step{step}_paired_posterior_stats.py"
            module = self.original(script, f"historical_statistical_step{step}")
            assert (module.B, module.CONF, module.NBINS, module.ECDF_PTS, module.SEED) == (5000, .95, 16, 1500, 42)
            csv_path = module.OUTDIR / "samplewise_plot_data.csv"
            self.track(csv_path, "historical samplewise plot data")
            self.track(module.OUTDIR / "summary.md", "historical statistical summary")
            if (module.OUTDIR / "no_final_samples_summary.md").exists():
                self.track(module.OUTDIR / "no_final_samples_summary.md", "historical exclusion evidence")
            with csv_path.open() as f:
                rows = {int(r["sample"]): r for r in csv.DictReader(f)}
            results, case_details, inputs = [], {}, []
            for col, spec in enumerate(module.SPECS):
                values, sample_ids, missing, endpoints = [], [], [], []
                for s in module.SAMPLES:
                    fp = module.ROOT / spec.dirname / f"sample={s}" / "final.jld2"
                    if not fp.is_file():
                        missing.append(s)
                        assert not rows[s][spec.slug + "_rate6"], (step, spec.key, s, "missing historical final")
                        continue
                    self.track(fp, "original completed optimization input")
                    inputs.append(rel(fp) + "::inj_rate_arr")
                    endpoint = module.last_nonzero_endpoint(fp)
                    q = module.rate6(endpoint, spec.inj_start)
                    assert endpoint == float(rows[s][spec.slug + "_endpoint"]), (step, spec.key, s)
                    assert q == float(rows[s][spec.slug + "_rate6"]), (step, spec.key, s)
                    sample_ids.append(s)
                    endpoints.append(endpoint)
                    values.append(q)
                assert missing == (EXPECTED_MISSING[step] if col == 0 else []), (step, spec.key, missing)
                x = np.array(values, dtype=float)
                boot = module.boot_quantile(x, module.THRESH, module.B, module.SEED)
                q01 = float(np.quantile(x, module.THRESH))
                qlo = float(np.quantile(boot, (1 - module.CONF) / 2))
                qhi = float(np.quantile(boot, 1 - (1 - module.CONF) / 2))
                grid, ecdf, clo, chi = module.boot_ecdf_ci(x, module.B, module.CONF, module.ECDF_PTS, module.SEED)
                crossings = [module.crossing(grid, curve, module.THRESH) for curve in [chi, ecdf, clo]]
                results.append((spec, x, q01, qlo, qhi, grid, ecdf, clo, chi))
                edges = np.linspace(x.min(), x.max(), module.NBINS + 1)
                if np.allclose(edges[0], edges[-1]):
                    edges = np.linspace(edges[0]-1e-6, edges[0]+1e-6, module.NBINS+1)
                case_details[spec.key] = {
                    "completed_samples": len(x), "sample_ids": sample_ids, "excluded_no_final": missing,
                    "active_samples": [], "inj_start": spec.inj_start, "endpoint_raw": endpoints,
                    "plotted_q_rate6": values, "histogram_counts": np.histogram(x, edges)[0].tolist(),
                    "bin_edges": edges.tolist(), "quantile_01": q01, "quantile_interval": [qlo, qhi],
                    "historical_crossings_upper_ecdf_lower": crossings, "marker_probability_percent": 1.0,
                    "csv_exactly_matches_final_inputs": True,
                }
            self.details[f"statistical_step{step}"] = {"B": module.B, "seed": module.SEED,
                "grid_points": module.ECDF_PTS, "confidence": module.CONF, "threshold": module.THRESH,
                "cases": case_details, "selection": "historical first grid point >= threshold"}
            fig = capture_plot(module.plot_grid, results, self.handoff / "unused.png")
            before = numeric_contents(fig)
            format_statistical(fig, results, step)
            self.save(fig, before, "statistical", f"injection_rate_hist_ecdf_step{step}", step,
                      module.OUTDIR / "summary_grid_hist_cdf.png", f"summary_grid_hist_cdf_t{step}.png", inputs, script)

    def finish(self):
        for path, info in self.inputs.items():
            assert sha256(ROOT / path) == info["sha256"], f"Input or original asset changed: {path}"
        write_json(self.handoff / "input_checksums.json", self.inputs)
        write_json(self.handoff / "validation" / "scientific_details.json", self.details)
        if self.reference:
            previous_details = json.loads((self.args.reference_handoff / "validation" / "scientific_details.json").read_text())
            # Normalize tuple values and integer dictionary keys in the same
            # way as the saved JSON before comparing scientific results.
            for key, detail in json.loads(json.dumps(self.details)).items():
                assert detail == previous_details[key], f"Scientific results changed: {key}"
        provenance = {"generating_commit": self.head, "historical_commit": BASELINE_COMMIT,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(), "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
            "python": sys.version, "numpy": np.__version__, "matplotlib": matplotlib.__version__, "h5py": h5py.__version__,
            "input_files_unchanged": True, "all_numeric_contents_unchanged": True,
            "title_policy": "Quantity/statistic and monitoring index k; header added above unchanged panel canvas",
            "histogram_quantile_interval_displayed": False,
            "presentation_change": "Omit histogram quantile-interval shading and its legend entry; retain ECDF uncertainty",
            "reference_handoff": str(self.args.reference_handoff) if self.reference else None,
            "canonical_files_published_at_render": not self.args.no_publish,
            "later_publication_receipt": "publication_receipt.json", "figures": self.figures}
        write_json(self.handoff / "manifest.json", provenance)
        fields = ["source_path", "source_step", "canonical_export_path", "paper_current_path", "input_dataset",
                  "generating_script", "historical_commit", "source_sha256", "output_sha256", "compat_sha256"]
        with (self.handoff / "manifest.csv").open("x", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            for entry in self.figures:
                writer.writerow({key: json.dumps(entry[key]) if key == "input_dataset" else entry[key] for key in fields})
        copy_new(ROOT / "docs/analysis/POSTERIOR_APPENDIX_E_REEXPORT_2026-09-08.md", self.handoff / "README.md")
        report = ["# Validation report", "", f"Exported {len(self.figures)} matched figures from original scripts and inputs.",
            "", "- Numeric contents before/after presentation edits: exact equality for every figure.",
            "- Posterior images: means/std arrays, row order, extents, colormaps and shared limits unchanged.",
            "- Statistical plots: histogram rectangles/bin edges, ECDF lines, confidence polygons, quantiles and marker coordinates unchanged.",
            "- Histogram quantile-interval spans are hidden and their legend entry is omitted; their historical coordinates remain in the numerical audit.",
            "- ECDF confidence intervals and sample 1% quantile lines/annotations remain visible and unchanged.",
            "- Samplewise rate CSVs agree exactly with the original completed final.jld2 inputs.",
            "- Historical bootstrap: 5,000 replicates, seed 42, 1,500 grid points; no direct-jump migration.",
            "- Input files and all 11 selected original PNGs: checksums unchanged after rendering.",
            "- Compatibility PNGs: byte-identical to their canonical handoff PNGs.",
            "- Concise global titles identify the quantity/statistic and monitoring step k.",
            "- Titles occupy an added 0.5-inch header above the unchanged panel canvas.",
            "- Visible text bounds: within the exported canvas; titles do not overlap the existing content.",
            "- PNG: 400 dpi; PDF/SVG (when requested): vector text and plot lines, raster field images.",
            "- Paper QMD and original manuscript image bytes are unavailable in this checkout; mapping uses the supplied paper paths.",
            "", "The strict PoF counts are 127, 124 and 122, with 1, 4 and 6 excluded no-final",
            "realizations. All other rate cases contain 128 completed samples. All posterior",
            "state cases contain 128 samples. No active optimization samples were included.",
            "", "See README.md for the meanings of 1% quantile, q-star, ECDF and Opt.; the latter",
            "is a lower-confidence-curve crossing, not a separate optimized schedule. The",
            "historical boundary crossings do not assert an upper-CDF bound below 1%.",
            "", "Independent visual review is recorded separately after export."]
        if self.reference:
            report += ["", "Compared with the supplied previous handoff: numerical snapshots and scientific details are identical."]
            if self.args.reference_change == "hide-quantile-interval":
                report += ["Only histogram interval shading and the shared legend change in statistical PNGs;",
                           "all pixels outside those regions, including every ECDF panel and title, are identical."]
            else:
                report += ["Every pixel in the previous PNG region is unchanged; only the global-title header is added."]
            if self.args.reuse_posterior_from_reference:
                report += ["The eight posterior figures and their PNG/PDF/SVG and compatibility files are byte-identical copies",
                           "from the reference handoff; their accompanying numerical audits are inherited unchanged."]
        (self.handoff / "VALIDATION.md").write_text("\n".join(report) + "\n")
        if not self.args.no_publish:
            for entry in self.figures:
                for ext, output in entry["outputs"].items():
                    target = (ROOT / entry["canonical_export_path"]).with_suffix("." + ext)
                    copy_new(self.handoff / output["handoff_path"], target)
        checksums = {str(p.relative_to(self.handoff)): sha256(p) for p in sorted(self.handoff.rglob("*")) if p.is_file()}
        write_json(self.handoff / "checksums.json", checksums)
        print(f"Handoff complete: {self.handoff}", flush=True)


def publish_handoff(handoff, replace_from_handoff=None):
    """Publish a reviewed handoff using verified byte copies, without re-rendering."""
    handoff = handoff.resolve()
    manifest = json.loads((handoff / "manifest.json").read_text())
    checksums = json.loads((handoff / "checksums.json").read_text())
    for name, digest in checksums.items():
        assert sha256(handoff / name) == digest, f"Handoff changed: {name}"
    targets = []
    previous_files = {}
    if replace_from_handoff:
        previous = json.loads((replace_from_handoff / "manifest.json").read_text())
        previous_files = {str(Path(e["canonical_export_path"]).with_suffix("." + ext)): info["sha256"]
                          for e in previous["figures"] for ext, info in e["outputs"].items()}
    for entry in manifest["figures"]:
        for ext, info in entry["outputs"].items():
            target = (ROOT / entry["canonical_export_path"]).with_suffix("." + ext)
            if target.exists():
                if not replace_from_handoff:
                    raise FileExistsError(f"Preserving existing canonical export: {target}")
                assert rel(target) in previous_files and sha256(target) == previous_files[rel(target)], target
            if target.exists() and sha256(target) == info["sha256"]:
                continue  # Already-identical posterior assets need no replacement.
            targets.append((handoff / info["handoff_path"], target, info["sha256"]))
    receipt = handoff / "publication_receipt.json"
    if receipt.exists():
        raise FileExistsError(receipt)
    backup = None
    if replace_from_handoff:
        backup = ROOT / "plots" / "paper_figures" / (handoff.name + "_previous_canonical")
        backup.mkdir(exist_ok=False)
        for _, target, _ in targets:
            if target.exists():
                copy_new(target, backup / target.relative_to(ROOT / "plots" / "paper_figures"))
        write_json(backup / "checksums.json", {rel(target): previous_files[rel(target)]
                                                for _, target, _ in targets if target.exists()})
    for source, target, digest in targets:
        assert sha256(source) == digest
        if target.exists():
            assert backup is not None and sha256(target) == previous_files[rel(target)]
            with source.open("rb") as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            assert sha256(target) == digest
        else:
            copy_new(source, target)
    write_json(receipt, {"published_at_utc": datetime.now(timezone.utc).isoformat(),
                         "canonical_files": {rel(target): digest for _, target, digest in targets},
                         "previous_canonical_backup": str(backup) if backup else None,
                         "compatibility_pngs_byte_identical": True})
    print(f"Published {len(targets)} canonical files from {handoff}")


def main(argv=None, family="all", steps=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--family", choices=["all", "posterior", "statistical"], default=family)
    parser.add_argument("--steps", type=int, nargs="+", choices=[1, 2, 3, 4], default=steps or [1, 2, 3, 4])
    parser.add_argument("--formats", nargs="+", choices=["png", "pdf", "svg"], default=["png"])
    parser.add_argument("--handoff-dir", type=Path, default=ROOT / "plots" / "paper_figures" /
                        ("posterior_appendix_e_handoff_" + datetime.now().strftime("%Y%m%d_%H%M%S") +
                         "_" + os.environ.get("SLURM_JOB_ID", "local")))
    parser.add_argument("--no-publish", action="store_true", help="Create a separate handoff without writing canonical paths")
    parser.add_argument("--publish-handoff", type=Path, help="Publish byte copies from an already validated handoff; no rendering")
    parser.add_argument("--reference-handoff", type=Path,
                        help="Verify that the original PNG region and numerics exactly match this previous handoff")
    parser.add_argument("--reference-change", choices=["title-header", "hide-quantile-interval"],
                        default="hide-quantile-interval", help="Expected presentation difference from the reference")
    parser.add_argument("--reuse-posterior-from-reference", action="store_true",
                        help="Reuse verified posterior exports byte-for-byte instead of rendering them again")
    parser.add_argument("--replace-from-handoff", type=Path,
                        help="With --publish-handoff, back up and replace only files matching this previous manifest")
    args = parser.parse_args(argv)
    if args.publish_handoff:
        publish_handoff(args.publish_handoff, args.replace_from_handoff)
        return
    if args.replace_from_handoff:
        parser.error("--replace-from-handoff requires --publish-handoff")
    if args.reuse_posterior_from_reference and not args.reference_handoff:
        parser.error("--reuse-posterior-from-reference requires --reference-handoff")
    if "png" not in args.formats:
        parser.error("PNG is required for the paper compatibility handoff")
    if not os.environ.get("SLURM_JOB_ID"):
        parser.error("This multi-file re-export must run through sbatch or salloc")
    # Refuse collisions before doing expensive work or writing any output.
    if not args.no_publish:
        stems = []
        if args.family in ("all", "posterior"):
            stems += [f"posterior/posterior_{stat}_step{k}" for k in args.steps for stat in ("mean", "std")]
        if args.family in ("all", "statistical"):
            stems += [f"statistical/injection_rate_hist_ecdf_step{k}" for k in args.steps if k > 1]
        for stem in stems:
            for ext in args.formats:
                target = ROOT / "plots" / "paper_figures" / f"{stem}.{ext}"
                if target.exists():
                    parser.error(f"Preserving existing export {target}; use --no-publish and a new handoff directory")
    matplotlib.rcParams.update({"pdf.fonttype": 42, "svg.fonttype": "none"})
    export = Export(args)
    if args.family in ("all", "posterior"):
        export.posterior()
    if args.family in ("all", "statistical"):
        export.statistical()
    export.finish()


if __name__ == "__main__":
    main()
