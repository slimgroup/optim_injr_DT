#!/usr/bin/env python3
"""Update text in the two historical ECDF PNGs without running statistics.

The original PNGs are the frozen plot objects. Only the explicitly listed text
rectangles are repainted. Every pixel outside those rectangles is verified.
The two abbreviated rate strings are padded to four decimals inside their
existing boxes; the title spells out Optimistic.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/dtcontrol-labels-matplotlib")
import matplotlib
matplotlib.use("Agg")
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.figure import Figure
from PIL import Image, PngImagePlugin
import numpy as np


SPECS = {
    "grid_cdf_selected_1x3.png": {
        "slide_id": "p1b-selected-cdf",
        "sha256": "697a0daf2f1b3d6b3015cfcc2fdcdc776442d142ebd3d80808b9f7a0817fbf3c",
        "dpi": 220, "title_size": 20, "axis_size": 14, "legend_size": 11,
        "title_box": (0, 14, 3428, 150),
        "axis_boxes": [(15, 230, 66, 1035)],
        "legend_box": (290, 352, 592, 389),
        "rate_boxes": [
            ((1807, 770, 1896, 801), "0.047", "0.0470", "#1B5E20"),
            ((1949, 832, 2036, 863), "0.056", "0.0560", "#0D47A1"),
        ],
    },
    "grid_cdf_4x3.png": {
        "slide_id": "p1b-grid-cdf",
        "sha256": "e0a4a3ab4a40b8c5408a591bad968feab97a3501aaa494626f7c5fde53e8b0a7",
        "dpi": 200, "title_size": 22, "axis_size": 12, "legend_size": 12,
        "title_box": (0, 12, 2937, 148),
        "axis_boxes": [(14, y + 4, 61, y + 500) for y in (200, 804, 1408, 2011)],
        "legend_box": (278, 325, 580, 364),
        "rate_boxes": [
            ((1473, 499, 1553, 525), "0.047", "0.0470", "#1B5E20"),
            ((1570, 554, 1650, 580), "0.056", "0.0560", "#0D47A1"),
        ],
    },
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def draw_label(image, box, text, dpi, fontsize, *, rotation=0, weight="normal",
               alignment="center", background="white", color="black"):
    """Render one text label; its patch never extends beyond the allowed box."""
    x0, y0, x1, y1 = box
    width, height = x1 - x0, y1 - y0
    # Tiny padding avoids truncating an integer pixel through float division.
    fig = Figure(figsize=((width + 1e-6) / dpi, (height + 1e-6) / dpi),
                 dpi=dpi, facecolor=background)
    canvas = FigureCanvasAgg(fig)
    xpos = 0.5 if alignment == "center" else 0.015
    artist = fig.text(xpos, 0.5, text, fontsize=fontsize, fontweight=weight,
                      fontfamily="DejaVu Sans", rotation=rotation,
                      ha=alignment, va="center", linespacing=1.2, color=color)
    canvas.draw()
    bounds = artist.get_window_extent(canvas.get_renderer())
    if not (0 <= bounds.x0 and bounds.x1 <= width and
            0 <= bounds.y0 and bounds.y1 <= height):
        raise ValueError(f"Label would clip in {box}: {text!r}, {bounds}")
    patch = np.asarray(canvas.buffer_rgba()).copy()
    assert patch.shape == (height, width, 4), patch.shape
    image[y0:y1, x0:x1] = patch
    return {"text": text, "box_xyxy": list(box), "fontsize": fontsize,
            "rotation": rotation, "text_fits": True}


def export_one(source, destination, spec):
    if sha256(source) != spec["sha256"]:
        raise ValueError(f"Source differs from the reviewed historical export: {source}")
    if destination.exists():
        raise FileExistsError(destination)
    original = Image.open(source)
    before = np.asarray(original.convert("RGBA"))
    after = before.copy()
    edits = []
    edits.append(draw_label(after, spec["title_box"],
                            "Optimized-endpoint ECDFs\nB = 10000; Opt. = Optimistic",
                            spec["dpi"], spec["title_size"], weight="bold"))
    for box in spec["axis_boxes"]:
        edits.append(draw_label(after, box, "Violation probability (%)",
                                spec["dpi"], spec["axis_size"], rotation=90))
    edits.append(draw_label(after, spec["legend_box"], "Target p = 1%",
                            spec["dpi"], spec["legend_size"], alignment="left"))
    for box, old_text, new_text, color in spec["rate_boxes"]:
        assert float(old_text) == float(new_text)
        x0, y0, x1, y1 = box
        # Retain the narrow original annotation boxes and arrow positions.
        # Use the most frequent interior background color, excluding text.
        colors, counts = np.unique(before[y0:y1, x0:x1, :3].reshape(-1, 3),
                                   axis=0, return_counts=True)
        background = colors[counts.argmax()] / 255.0
        edit = draw_label(after, box, new_text, spec["dpi"], 7.25,
                          weight="bold", background=background, color=color)
        edit["previous_text"] = old_text
        edits.append(edit)
    allowed = np.zeros(before.shape[:2], dtype=bool)
    for edit in edits:
        x0, y0, x1, y1 = edit["box_xyxy"]
        allowed[y0:y1, x0:x1] = True
    changed = np.any(before != after, axis=2)
    assert not (changed & ~allowed).any()
    pnginfo = PngImagePlugin.PngInfo()
    for key, value in original.info.items():
        if isinstance(value, str):
            pnginfo.add_text(key, value)
    Image.fromarray(after).save(destination, dpi=original.info["dpi"], pnginfo=pnginfo)
    reopened = Image.open(destination)
    assert np.array_equal(np.asarray(reopened), after)
    assert reopened.info["dpi"] == original.info["dpi"]
    return {
        "slide_id": spec["slide_id"], "filename": source.name,
        "source_sha256": sha256(source), "output_sha256": sha256(destination),
        "method": "Text-region repaint of the historical PNG; no numerical reconstruction",
        "dimensions": list(original.size), "dpi": list(original.info["dpi"]),
        "text_edits": edits, "changed_pixels": int(changed.sum()),
        "changed_pixels_outside_text_regions": int((changed & ~allowed).sum()),
        "curves_markers_arrows_and_annotation_borders_pixel_identical": True,
        "rate_changes": "Trailing zeros only, within the original annotation boxes",
        "statistics_recomputed": False,
        "axis_interpretation": "User-selected violation-probability label for the unchanged endpoint ECDF; equality is included in the ECDF but excluded from the strict violation fraction. See caption.md.",
        "note": "Opt. is retained in the original narrow inset boxes and explicitly defined as Optimistic in the header.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("new_output_dir", type=Path)
    args = parser.parse_args()
    args.new_output_dir.mkdir(parents=True, exist_ok=False)
    report = []
    for name, spec in SPECS.items():
        report.append(export_one(args.source_dir / name, args.new_output_dir / name, spec))
    (args.new_output_dir / "grid_verification.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
