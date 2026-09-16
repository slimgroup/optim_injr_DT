#!/usr/bin/env python3
"""Assemble reviewed step-1 PNGs without recalculating any statistics.

The single ECDF comes from reexport_p1_select_labels.jl and its saved cache.
Other plots use guarded historical PNGs: edit text or remove blank spacing.
All output paths must be new. Pixel comparisons protect the plotted objects.
"""
import argparse
import json
from pathlib import Path
import shutil

from relabel_step1_ecdf_exports import (
    Image, PngImagePlugin, SPECS, draw_label, export_one, np, sha256,
)


def read_original(path, expected_hash):
    if sha256(path) != expected_hash:
        raise ValueError(f"Historical source hash differs: {path}")
    original = Image.open(path)
    return original, np.asarray(original.convert("RGBA"))


def save_png(destination, pixels, original):
    if destination.exists():
        raise FileExistsError(destination)
    metadata = PngImagePlugin.PngInfo()
    for key, value in original.info.items():
        if isinstance(value, str):
            metadata.add_text(key, value)
    Image.fromarray(pixels).save(destination, dpi=original.info["dpi"], pnginfo=metadata)
    reopened = Image.open(destination)
    assert np.array_equal(np.asarray(reopened), pixels)
    assert reopened.info["dpi"] == original.info["dpi"]


def single_histogram(source, destination):
    original, before = read_original(
        source, "91b839992601742314891a28db0a23b55fed4d13f596ecb9c091655470318c1a")
    after = before.copy()
    edits = [
        draw_label(after, (110, 8, 1580, 63),
                   "Injection Rate Distribution (PoF eps = 0.01)",
                   200, 16, weight="bold"),
        draw_label(after, (1136, 150, 1530, 191),
                   "1% quantile: 0.0483", 200, 13, alignment="left"),
    ]
    allowed = np.zeros(before.shape[:2], dtype=bool)
    for edit in edits:
        x0, y0, x1, y1 = edit["box_xyxy"]
        allowed[y0:y1, x0:x1] = True
    changed = np.any(before != after, axis=2)
    assert not (changed & ~allowed).any()
    save_png(destination, after, original)
    return dict(filename=source.name, source_sha256=sha256(source),
                output_sha256=sha256(destination), text_edits=edits,
                changed_pixels_outside_text_regions=0,
                histogram_bars_bins_and_selection_lines_pixel_identical=True,
                statistics_recomputed=False, dpi=original.info["dpi"],
                dimensions=list(original.size))


def selected_histogram(source, destination):
    original, before = read_original(
        source, "138ab8e3e23e49751a7a365cc0360e67f635af7726dde3c07f4fefb0fa23f9db")
    # Remove 50 blank rows between the supertitle and panel headings, and
    # 50 blank columns in each panel gap. Keep panel pixels at their native size.
    blank_rows = (90, 140)
    gaps = [(1144, 1194), (2269, 2319)]
    assert np.all(before[blank_rows[0]:blank_rows[1], :, :3] == 255)
    body = before[blank_rows[1]:]
    keep = np.ones(body.shape[1], dtype=bool)
    for left, right in gaps:
        assert np.all(body[:, left:right, :3] == 255)
        keep[left:right] = False
    shifted_body = body[:, keep]
    after = np.full((before.shape[0] - 50, before.shape[1] - 100, 4),
                    255, dtype=np.uint8)
    after[90:] = shifted_body
    title = draw_label(after, (0, 6, after.shape[1], 90),
                       "Distribution of Optimized Injectivities: Histogram (M=128)",
                       220, 20, weight="bold")
    assert np.array_equal(after[90:], shifted_body)
    save_png(destination, after, original)
    return dict(filename=source.name, source_sha256=sha256(source),
                output_sha256=sha256(destination), text_edits=[title],
                removed_blank_rows=list(blank_rows),
                removed_blank_columns_below_title=[list(g) for g in gaps],
                panel_pixels_identical_after_translation=True,
                panel_rescaling=False, statistics_recomputed=False,
                original_dimensions=list(original.size),
                dimensions=[after.shape[1], after.shape[0]], dpi=original.info["dpi"],
                rate_formatting="Existing quantile, selected rate and summary values already have four decimals")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("single_ecdf_export_dir", type=Path)
    parser.add_argument("new_output_dir", type=Path)
    args = parser.parse_args()
    out = args.new_output_dir
    out.mkdir(parents=True, exist_ok=False)
    reports = []
    for name, spec in SPECS.items():
        reports.append(export_one(args.source_dir / name, out / name, spec))
    for name, export in [("hist_POF_eps0.01.png", single_histogram),
                         ("grid_histogram_selected_1x3.png", selected_histogram)]:
        reports.append(export(args.source_dir / name, out / name))
    for name in ["cdf_POF_eps0.01.png", "cache_provenance.toml"]:
        source = args.single_ecdf_export_dir / name
        shutil.copyfile(source, out / name)
        assert sha256(source) == sha256(out / name)
    (out / "png_verification.json").write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
