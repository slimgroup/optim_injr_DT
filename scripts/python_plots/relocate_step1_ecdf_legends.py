#!/usr/bin/env python3
"""Move two saved ECDF-grid legends with explicitly accepted raster recovery.

The old translucent legend obscures the first panel's curve and CI. The
historical paper figure identifies PoF epsilon=0 and CVaR gamma=0 as identical
distributions. Reuse the unoccluded second-row first panel from the original
full grid, registering pixels to the old legend region. This is image-level
recovery, not a lossless export from saved numerical plotting objects.

No samples, bootstrap calculations, crossings, or numerical caches are read.
Only the old/new legend rectangles change; all other pixels remain identical
to v6. The selected grid needs affine raster resampling because its axes have
different dimensions. Keep the originals and obtain acceptance of this
limitation before passing --accept-raster-recovery.
"""
import argparse
import json
import shutil
from pathlib import Path

from relabel_step1_ecdf_exports import (
    Figure, FigureCanvasAgg, Image, np, sha256,
)
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from refine_step1_statistical_exports import save_png


DONOR_SHA256 = "e0a4a3ab4a40b8c5408a591bad968feab97a3501aaa494626f7c5fde53e8b0a7"
SPECS = {
    "grid_cdf_4x3.png": {
        "sha256": "1c4fade1bd1b9a65a3533f105b1eeb325d8c6d71bb2a384d9db7e6dc17c17564",
        "slide_id": "p1b-grid-cdf",
        "old_box": (171, 160, 594, 324),
        "legend_right": 992, "fontsize": 12, "dpi": 200,
    },
    "grid_cdf_selected_1x3.png": {
        "sha256": "06fbc1bfe55e4a1c29051bdf609b404301b823af5f839238f4653d6a22f44f92",
        "slide_id": "p1b-selected-cdf",
        "old_box": (183, 166, 606, 334),
        "legend_right": 1138, "fontsize": 11, "dpi": 220,
    },
}
LEGEND_LABELS = [
    "95% Bootstrap CI (B=10000)", "Empirical CDF", "Target p = 1%",
]


def legend_image(dpi, fontsize):
    fig = Figure(figsize=(4, 1), dpi=dpi, facecolor=(1, 1, 1, 0))
    canvas = FigureCanvasAgg(fig)
    handles = [
        Patch(facecolor="#BBDEFB", edgecolor="#BBDEFB", alpha=0.5),
        Line2D([], [], color="#1565C0", lw=1.8),
        Line2D([], [], color="#D62728", lw=1.2, ls="--"),
    ]
    artist = fig.legend(
        handles, LEGEND_LABELS, loc="upper left", bbox_to_anchor=(0, 1),
        borderaxespad=0, fontsize=fontsize, framealpha=0.9,
    )
    canvas.draw()
    bbox = artist.get_window_extent(canvas.get_renderer())
    width, height = np.ceil([bbox.width, bbox.height]).astype(int)
    fig.set_size_inches((width + 2) / dpi, (height + 2) / dpi)
    canvas.draw()
    result = Image.fromarray(np.asarray(canvas.buffer_rgba()).copy())
    for label in artist.get_texts():
        bounds = label.get_window_extent(canvas.get_renderer())
        assert 0 <= bounds.x0 <= bounds.x1 <= result.width
        assert 0 <= bounds.y0 <= bounds.y1 <= result.height
    return result


def recovery_patch(donor, box, selected):
    x0, y0, x1, y1 = box
    if not selected:
        # Original row stride rounded to 604 pixels + v6's 55-pixel header cut.
        donor_box = (x0, y0 + 659, x1, y1 + 659)
        return donor.crop(donor_box), {
            "method": "integer pixel translation",
            "donor_box_xyxy": donor_box,
        }
    # Registration from visible tick centers in historical PNGs, not from
    # sample endpoints or statistical calculations. Map output to donor pixels.
    xf = np.polyfit([0, .2, .4, .6, .8, 1], [162, 312, 462, 612, 763, 913], 1)
    xs = np.polyfit([.2, .4, .6, .8], [388, 610, 832, 1053], 1)
    yf = np.polyfit([100, 80, 60, 40, 20, 0], [805, 906, 1006, 1107, 1208, 1308], 1)
    ys = np.polyfit([100, 80, 60, 40, 20, 0], [227, 390, 552, 714, 877, 1039], 1)
    sx, sy = xf[0] / xs[0], yf[0] / ys[0]
    tx = xf[1] - sx * xs[1]
    ty = yf[1] - sy * ys[1] + sy * 75  # v6 selected header cut
    coefficients = (sx, 0, tx + sx * x0, 0, sy, ty + sy * y0)
    patch = donor.transform(
        (x1 - x0, y1 - y0), Image.Transform.AFFINE, coefficients,
        resample=Image.Resampling.BICUBIC,
    )
    return patch, {
        "method": "affine registration from axis ticks; bicubic raster resampling",
        "output_patch_to_donor_coefficients": coefficients,
    }


def export_one(source, destination, donor, spec):
    if sha256(source) != spec["sha256"]:
        raise ValueError(f"Input differs from the reviewed v6 export: {source}")
    original = Image.open(source)
    before = np.asarray(original.convert("RGBA"))
    after = original.convert("RGBA")
    box = spec["old_box"]
    patch, registration = recovery_patch(donor, box, "selected" in source.name)
    after.paste(patch, box[:2])
    legend = legend_image(spec["dpi"], spec["fontsize"])
    position = (spec["legend_right"] - legend.width, box[1])
    new_box = (*position, position[0] + legend.width, position[1] + legend.height)
    after.alpha_composite(legend, position)
    pixels = np.asarray(after)
    allowed = np.zeros(before.shape[:2], dtype=bool)
    for x0, y0, x1, y1 in (box, new_box):
        allowed[y0:y1, x0:x1] = True
    changed = np.any(before != pixels, axis=2)
    assert not (changed & ~allowed).any()
    # Both edits end above the first inset; all insets, markers, rate boxes,
    # titles, axis labels, and subsequent panels remain pixel-identical.
    protected_from_y = max(box[3], new_box[3])
    assert np.array_equal(before[protected_from_y:], pixels[protected_from_y:])
    assert np.array_equal(before[:box[1]], pixels[:box[1]])
    save_png(destination, pixels, original)
    reopened = Image.open(destination)
    assert reopened.size == original.size
    assert reopened.info["dpi"] == original.info["dpi"]
    assert np.array_equal(np.asarray(reopened), pixels)
    assert sha256(source) == spec["sha256"]
    return {
        "filename": source.name, "slide_id": spec["slide_id"],
        "source_sha256": spec["sha256"], "output_sha256": sha256(destination),
        "dimensions": original.size, "dpi": original.info["dpi"],
        "old_legend_box_xyxy": box, "new_legend_box_xyxy": new_box,
        "legend_labels": LEGEND_LABELS,
        "registration": registration,
        "changed_pixels": int(changed.sum()),
        "changed_pixels_outside_legend_regions": 0,
        "insets_annotations_markers_and_titles_pixel_identical": True,
        "statistics_recomputed": False,
        "lossless_recovery_of_obscured_original_curve_verified": False,
        "limitation": "Old legend region reuses historical duplicate-panel raster; not recovered numerical plotting objects.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reviewed_v6_dir", type=Path)
    parser.add_argument("new_output_dir", type=Path)
    parser.add_argument("--accept-raster-recovery", action="store_true")
    args = parser.parse_args()
    if not args.accept_raster_recovery:
        parser.error("Explicit acceptance of image-level recovery is required.")
    donor_path = args.reviewed_v6_dir.parent / "grid_cdf_4x3.png"
    if sha256(donor_path) != DONOR_SHA256:
        raise ValueError("Historical full-grid donor has changed")
    for name, spec in SPECS.items():
        if sha256(args.reviewed_v6_dir / name) != spec["sha256"]:
            raise ValueError(f"Reviewed v6 input has changed: {name}")
    args.new_output_dir.mkdir(parents=True, exist_ok=False)
    donor = Image.open(donor_path).convert("RGBA")
    reports = [
        export_one(args.reviewed_v6_dir / name, args.new_output_dir / name, donor, spec)
        for name, spec in SPECS.items()
    ]
    assert sha256(donor_path) == DONOR_SHA256
    shutil.copyfile(args.reviewed_v6_dir / "caption.md", args.new_output_dir / "caption.md")
    report = {
        "method": "Explicitly accepted image-level legend relocation",
        "donor": str(donor_path), "donor_sha256": DONOR_SHA256,
        "donor_panel": "row 2, column 1: CVaR gamma=0, alpha=0",
        "historical_identity_reference": "ad0696e:plots/paper_figures/statistical/grid_cdf_selected_1x3.png",
        "historical_identity_label": "PoF epsilon=0.0 (identical to CVaR gamma=0.0)",
        "figures": reports,
    }
    (args.new_output_dir / "legend_relocation_verification.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print("Saved two ECDF grids; all pixels outside the old/new legend regions are unchanged.")


if __name__ == "__main__":
    main()
