#!/usr/bin/env python3
"""Restyle frozen Appendix E plot geometry; never load samples or run statistics.

Run with sbatch via submit_statistical_grid_readability.sh. Every output directory
must be new. The historical SVG supplies printed statistics and tick labels; its
checksum-matched NPZ supplies all data geometry, including the confidence paths.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET

os.environ.setdefault("MPLBACKEND", "Agg")
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from matplotlib.text import Annotation, Text
from matplotlib.ticker import FixedLocator, FixedFormatter
import numpy as np
from PIL import Image

from export_posterior_appendix_e import verify_numeric_contents

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909"
NS = {"s": "http://www.w3.org/2000/svg"}
COLORS = ["#D35400", "#117A65", "#5B2C6F"]
BACKGROUNDS = ["#FEF5E7", "#E8F5E9", "#F4ECF7"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    with path.open("x") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


def svg_contents(path):
    root = ET.parse(path).getroot()
    groups = {g.get("id"): g for g in root.findall(".//s:g", NS)}
    axes = []
    for i in range(1, 10):
        group = groups[f"axes_{i}"]
        axis_groups = [g for g in group.findall("s:g", NS)
                       if g.get("id", "").startswith("matplotlib.axis_")]
        ticks = []
        for axis in axis_groups:
            labels = []
            for tick in axis.findall("s:g", NS):
                if not tick.get("id", "").startswith(("xtick_", "ytick_")):
                    continue
                labels += ["".join(t.itertext()).strip() for t in tick.findall(".//s:text", NS)]
            ticks.append(labels)
        text = ["".join(t.itertext()).strip() for t in group.findall(".//s:text", NS)]
        stats = [t for t in text if t.startswith(("mean=", "median=", "1% quantile="))]
        axes.append({"ticks": ticks, "stats": stats, "text": text})
    return axes


def set_ticks(ax, source):
    for axis, labels in zip((ax.xaxis, ax.yaxis), source["ticks"]):
        axis.set_major_locator(FixedLocator([float(t) for t in labels]))
        axis.set_major_formatter(FixedFormatter(labels))


def set_limits(ax, data, index):
    ax.set_xlim(data[f"axes{index}_xlim"])
    ax.set_ylim(data[f"axes{index}_ylim"])


def draw_cdf(ax, data, index, inset=False):
    prefix = f"axes{index}"
    # closed=False retains the exact cached vertex array (already closed).
    band = PolyCollection([data[prefix + "_collection0_path0"]], closed=False,
                          facecolor="#AED6F1", edgecolor="#AED6F1", alpha=.55,
                          linewidth=.3)
    ax.add_collection(band)
    for j in range(5):
        x, y = data[f"{prefix}_line{j}_x"], data[f"{prefix}_line{j}_y"]
        if j == 0:
            ax.plot(x, y, color="#1F618D", linewidth=.8 if inset else 1.0)
        elif j == 1:
            ax.plot(x, y, transform=ax.get_yaxis_transform(), color="#C0392B",
                    linewidth=.6, linestyle="--")
        else:
            ax.plot(x, y, color=COLORS[j-2], marker="*", markersize=5,
                    linestyle="None", zorder=5)
    set_limits(ax, data, index)


def visible_text(fig):
    hidden = set()
    for ax in fig.axes:
        for a in (ax, *ax.child_axes):
            for axis in (a.xaxis, a.yaxis):
                lo, hi = sorted(axis.get_view_interval())
                for tick in axis.get_major_ticks():
                    if not lo <= tick.get_loc() <= hi:
                        hidden.update([id(tick.label1), id(tick.label2)])
    return [t for t in fig.findobj(Text) if t.get_visible() and t.get_text()
            and id(t) not in hidden]


def check_layout(fig):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    texts = visible_text(fig)
    problems = []
    for text in texts:
        box = (text.get_bbox_patch().get_window_extent(renderer)
               if text.get_bbox_patch() else text.get_window_extent(renderer))
        if box.x0 < -1 or box.y0 < -1 or box.x1 > fig.bbox.x1+1 or box.y1 > fig.bbox.y1+1:
            problems.append("Outside canvas: " + text.get_text())
    boxes = [(t, t.get_bbox_patch().get_window_extent(renderer)
              if t.get_bbox_patch() else t.get_window_extent(renderer)) for t in texts]
    for i, (first, a) in enumerate(boxes):
        for second, b in boxes[i+1:]:
            if a.overlaps(b):
                problems.append(f"Text overlap: {first.get_text()!r} {a.extents.tolist()} / "
                                f"{second.get_text()!r} {b.extents.tolist()}")
    for parent in fig.axes:
        if parent.child_axes:
            band = parent.collections[0]
            band_path = band.get_paths()[0].transformed(band.get_transform())
            for inset in parent.child_axes:
                # The zoom label sits outside its clipped plotting rectangle.
                if inset.yaxis.label.get_window_extent(renderer).overlaps(inset.get_window_extent(renderer)):
                    problems.append("Zoom label overlaps its plotting rectangle")
                obstacles = [inset.get_window_extent(renderer)]
                obstacles += [t.get_bbox_patch().get_window_extent(renderer)
                              for t in inset.texts if isinstance(t, Annotation)]
                for j, box in enumerate(obstacles):
                    if band_path.intersects_bbox(box, filled=True):
                        problems.append(f"Obstacle {j} obscures main CDF band on {parent.get_label()}")
        for ax in (parent, *parent.child_axes):
            for axis in (ax.xaxis, ax.yaxis):
                lo, hi = sorted(axis.get_view_interval())
                boxes = [t.label1.get_window_extent(renderer) for t in axis.get_major_ticks()
                         if lo <= t.get_loc() <= hi and t.label1.get_visible()]
                if any(a.overlaps(b) for a, b in zip(boxes, boxes[1:])):
                    problems.append(f"Overlapping {axis.axis_name} ticks on {ax.get_label()}")
            boxes = [t.get_bbox_patch().get_window_extent(renderer) for t in ax.texts
                     if isinstance(t, Annotation)]
            if any(a.overlaps(b) for i, a in enumerate(boxes) for b in boxes[i+1:]):
                problems.append("Overlapping crossing annotations")
    if problems:
        raise ValueError("; ".join(problems))
    sizes = [t.get_fontsize() for t in texts]
    assert min(sizes) >= 8 and max(sizes) <= 10, (min(sizes), max(sizes))
    return {"all_text_inside_canvas": True, "tick_labels_do_not_overlap": True,
            "crossing_boxes_do_not_overlap": True, "minimum_font_pt": min(sizes),
            "maximum_font_pt": max(sizes)}


def render(step, reference, output, checksums, details, source_manifest):
    stem = f"injection_rate_hist_ecdf_step{step}"
    entry = next(e for e in source_manifest["figures"]
                 if e["canonical_export_path"].endswith(stem + ".png"))
    names = [f"validation/{stem}.npz", f"statistical/{stem}.svg",
             f"statistical/{stem}.png", entry["compat_path"],
             "validation/scientific_details.json", "manifest.json"]
    inputs = {}
    for name in names:
        path = reference / name
        actual = digest(path)
        assert actual == checksums[name], f"Reference checksum mismatch: {name}"
        inputs[str(path.relative_to(ROOT))] = actual
    # Confirm that the chosen manuscript mapping is still the canonical artwork.
    for ext in ("png", "svg"):
        canonical = ROOT / "plots/paper_figures/statistical" / f"{stem}.{ext}"
        assert digest(canonical) == digest(reference / "statistical" / f"{stem}.{ext}")
        inputs[str(canonical.relative_to(ROOT))] = digest(canonical)
    with np.load(reference / f"validation/{stem}.npz", allow_pickle=False) as cache:
        data = {k: cache[k].copy() for k in cache.files}
    svg = svg_contents(reference / f"statistical/{stem}.svg")
    case_details = list(details[f"statistical_step{step}"]["cases"].values())
    matplotlib.rcParams.update({
        "font.family": "DejaVu Serif", "font.size": 8.5, "axes.labelsize": 9,
        "xtick.labelsize": 8, "ytick.labelsize": 8, "axes.titlesize": 9,
        "legend.fontsize": 8, "svg.fonttype": "none", "axes.linewidth": .5,
        "mathtext.fontset": "dejavuserif", "path.simplify": False,
    })
    fig, axes = plt.subplots(2, 3, figsize=(150/25.4, 148/25.4), dpi=400,
                             gridspec_kw={"height_ratios": [.82, 1.18],
                                          "width_ratios": [1.10, 1, 1]})
    fig.subplots_adjust(left=.095, right=.985, bottom=.14, top=.81,
                        wspace=.20, hspace=.15)
    fig.suptitle("Injection-rate endpoint histogram and ECDF\n"
                 rf"at monitoring step $k={step}$", fontsize=10, weight="bold", y=.985)
    fig.text(.54, .905, "Paired posterior · optimized schedule element 6/12",
             ha="center", fontsize=8)
    titles = [r"(a) PoF $\varepsilon=0.0$", r"(b) PoF $\varepsilon=0.01$",
              "(c) CVaR\n" + r"$\gamma=0.1$, $\alpha=0.01$"]
    for col in range(3):
        hist, cdf = axes[0, col], axes[1, col]
        hist.set_label(f"histogram_{col}")
        cdf.set_label(f"cdf_{col}")
        original_bounds = hist.get_position()
        hist.set_position([original_bounds.x0, original_bounds.y0,
                           original_bounds.width, original_bounds.height-.073])
        for j in range(17):
            x, y, width, height = data[f"axes{col}_patch{j}"]
            hist.add_patch(Rectangle((x, y), width, height,
                facecolor="#7FB3D5" if j < 16 else "#D7BDE2", edgecolor="#1F618D",
                linewidth=.45, alpha=.8, visible=j < 16,
                transform=hist.transData if j < 16 else hist.get_xaxis_transform()))
        hist.plot(data[f"axes{col}_line0_x"], data[f"axes{col}_line0_y"],
                  transform=hist.get_xaxis_transform(), color="#1E8449", linewidth=1)
        set_limits(hist, data, col)
        set_ticks(hist, svg[col])
        count = case_details[col]["completed_samples"]
        qualification = (f"{count} feasible completed;\n{128-count} excluded" if col == 0
                         else f"{count} completed\nsamples" if col == 1
                         else f"{count} completed samples")
        fig.text(original_bounds.x0+original_bounds.width/2, original_bounds.y1+.014,
                 titles[col] + "\n" + qualification, fontsize=8.5, ha="center", va="bottom")
        hist.text(.50, 1.075, "\n".join(svg[col]["stats"]), transform=hist.transAxes,
                  ha="center", va="bottom", fontsize=8,
                  bbox=dict(boxstyle="round,pad=.22", fc="white", ec="#9E9E9E", lw=.5, alpha=.95))
        if col == 0:
            hist.set_ylabel("Count", labelpad=3)
            cdf.set_ylabel("Cumulative probability (%)", labelpad=3)
        index = 3 + 2*col
        draw_cdf(cdf, data, index)
        set_ticks(cdf, svg[index])
        zoom_bounds = [.28, .11, .65, .33] if col == 2 else [.30, .11, .63, .33]
        inset = cdf.inset_axes(zoom_bounds, label=f"zoom_{col}")
        draw_cdf(inset, data, index+1, inset=True)
        set_ticks(inset, svg[index+1])
        inset.set_ylabel("Left-tail zoom", fontsize=8, labelpad=3, y=.445)
        inset.yaxis.set_label_position("right")
        # Keep the parent frame from running through the enlarged zoom label.
        inset.yaxis.label.set_bbox(dict(facecolor="white", edgecolor="none", pad=0))
        for j, (label, position) in enumerate(zip([r"$q_k^*$", "ECDF", "Opt."],
                                                 [(.82, .83), (.82, .675), (.82, .52)])):
            xy = data[f"axes{index+1}_annotation{j}_xy"]
            number = f"{xy[0]:.5f}"
            assert number in svg[index+1]["text"], "Changed printed crossing value"
            inset.annotate(label + "\n" + number, xy=xy, xytext=position,
                textcoords=cdf.transAxes, ha="center", va="center", fontsize=8,
                color=COLORS[j], weight="bold", zorder=6,
                bbox=dict(boxstyle="round,pad=.12", fc=BACKGROUNDS[j], ec=COLORS[j], lw=.5, alpha=.98),
                arrowprops=dict(arrowstyle="->", color=COLORS[j], lw=.65,
                                shrinkA=2, shrinkB=2,
                                connectionstyle="angle,angleA=180,angleB=90,rad=2"))
        for ax in (hist, cdf, inset):
            ax.tick_params(axis="both", length=2, width=.5, pad=2, labelsize=8)
            ax.tick_params(axis="x", pad=4)
            ax.grid(True, linestyle="--", linewidth=.25, alpha=.35)
            ax.set_axisbelow(True)
    fig.text(.54, .079, r"Injection-rate endpoint $q$ (m$^3$/s)", ha="center", fontsize=9)
    handles = [Line2D([], [], color="#1E8449", lw=1, label="Sample 1% quantile"),
               Line2D([], [], color="#1F618D", lw=1, label="Empirical CDF"),
               Patch(fc="#AED6F1", alpha=.55, label="Pointwise 95% bootstrap confidence interval"),
               Line2D([], [], color="#C0392B", lw=.6, ls="--", label="1% threshold")]
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(.51, -.005),
               ncol=2, fontsize=8, frameon=False, columnspacing=1.2,
               handlelength=1.5, handletextpad=.5)
    # Exact equality includes every bin rectangle, line point, confidence-path
    # vertex, hidden historical quantile interval, marker, annotation and limit.
    numeric_audit = verify_numeric_contents(data, fig)
    fig.savefig(output / f"review_t{step}.png", dpi=160, facecolor="white")
    layout = check_layout(fig)
    outputs = {}
    for ext in ("svg", "png"):
        path = output / f"summary_grid_hist_cdf_t{step}.{ext}"
        assert not path.exists()
        fig.savefig(path, dpi=400, facecolor="white")
        outputs[path.name] = digest(path)
    with Image.open(output / f"summary_grid_hist_cdf_t{step}.png") as im:
        assert abs(im.info["dpi"][0]-400) < .02
        raster = {"pixels": list(im.size), "dpi": list(im.info["dpi"])}
    tree = ET.parse(output / f"summary_grid_hist_cdf_t{step}.svg")
    assert tree.findall(".//s:text", NS) and not tree.findall(".//s:image", NS)
    for path, checksum in inputs.items():
        assert digest(ROOT / path) == checksum
    plt.close(fig)
    return {"step": step, "paper_path": entry["paper_current_path"],
            "inputs_unchanged": inputs, "outputs": outputs,
            "exact_numeric_equality": True, "numeric_arrays": numeric_audit,
            "sample_selection_inherited": case_details,
            "statistics_text_verbatim": [s["stats"] for s in svg[:3]],
            "dimensions_mm": [150, 148], "layout": layout, "png": raster,
            "svg_contains_vector_text_and_geometry_no_raster_images": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference", type=Path, default=REFERENCE)
    parser.add_argument("--steps", type=int, nargs="+", choices=(2, 3, 4), default=[2, 3, 4])
    args = parser.parse_args()
    if not os.environ.get("SLURM_JOB_ID"):
        parser.error("Run on a Slurm compute node using the companion submission script.")
    args.output.mkdir(parents=True, exist_ok=False)
    checksums = json.loads((args.reference / "checksums.json").read_text())
    details = json.loads((args.reference / "validation/scientific_details.json").read_text())
    source_manifest = json.loads((args.reference / "manifest.json").read_text())
    manifest = {"method": "Frozen plot geometry and printed SVG text only; no statistics recomputed",
                "slurm_job_id": os.environ["SLURM_JOB_ID"],
                "script_sha256": digest(__file__), "figures": []}
    for step in args.steps:
        result = render(step, args.reference, args.output, checksums, details, source_manifest)
        manifest["figures"].append(result)
        write_json(args.output / f"verification_t{step}.json", result)
        print(f"Completed step {step}: exact numerical equality; vector SVG and 400-dpi PNG", flush=True)
    write_json(args.output / "manifest.json", manifest)


if __name__ == "__main__":
    main()
