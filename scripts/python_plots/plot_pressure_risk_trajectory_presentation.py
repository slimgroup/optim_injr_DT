#!/usr/bin/env python3
"""Presentation-only re-export of the existing four-case pressure trajectories.

Read the same saved arrays as the original plot; never run a forward model.
Export PNG only, with a JSON audit sidecar. Existing exports are never overwritten.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import plot_pressure_risk_trajectory_over_four_steps as original
import h5py
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D
from matplotlib.ticker import StrMethodFormatter


DEFAULT_STEM = original.OUTDIR / "pressure_risk_trajectory_over_four_steps"
# Keep both event markers distinct at their unchanged dual-axis coordinates.
# scatter sizes are in points squared; the legend uses the matching point size.
SHUTDOWN_STAR_AREA = 300.0
SHUTDOWN_STAR_SCALE = float(np.sqrt(SHUTDOWN_STAR_AREA / 340))


def load_trajectories():
    """Preserve original source selection, arithmetic, initial point and times."""
    trajectories = {}
    with h5py.File(original.BASE_DATA, "r") as f:
        p_max = np.asarray(f["p_max"][:], dtype=float)
        load0 = original.initial_load(np.asarray(f["p0"][:], dtype=float), p_max)
        for key, label, color in original.CASES:
            pressure = np.asarray(f[f"{key}_pres_snaps"][:], dtype=float)
            load, cells = original.pressure_metrics(pressure, p_max)
            trajectories[key] = dict(
                label=label, color=color,
                times=np.r_[0.0, np.asarray(f[f"{key}_snap_idx"][:], dtype=float) * 8.0],
                load=np.r_[load0, load], cells=np.r_[0, cells],
            )

    with h5py.File(original.POF_SENSITIVITY_DATA, "r") as f:
        load = np.asarray(f["max_pressure_load_by_substep"][:], dtype=float)
        cells = np.asarray(f["fractured_cells_by_substep"][:], dtype=int)
        dt = float(f["dt_days"][()])
        trajectories["POF_eps0p01"].update(
            times=np.r_[0.0, np.arange(1, load.size + 1) * dt],
            load=np.r_[load0, load], cells=np.r_[0, cells],
        )

    with h5py.File(original.CVAR_SENSITIVITY_DATA, "r") as f:
        # Keep the original Float64 diagnostics. The pressure snapshots are
        # Float32 and recomputing from them would change a near-limit count.
        load = 1.0 - np.asarray(f["min_margin_by_substep"][:], dtype=float)
        cells = np.asarray(f["fractured_cells_by_substep"][:], dtype=int)
        trajectories["CVaR_g01_a001"].update(
            times=np.r_[0.0, np.arange(1, load.size + 1) * 8.0],
            load=np.r_[load0, load], cells=np.r_[0, cells],
        )

    with h5py.File(original.NO_CONTROL_DATA, "r") as f:
        p_max = np.asarray(f["p_max"][:], dtype=float)
        dt = float(f["dt_days"][()])
        shutdown_day = float(f["severe_day"][()])
        pressure = np.asarray(f["pres_all"][:], dtype=float)
        load, cells = original.pressure_metrics(pressure, p_max)
        times = np.arange(1, pressure.shape[0] + 1, dtype=float) * dt
        keep = times <= shutdown_day
        load0 = original.initial_load(np.asarray(f["p0"][:], dtype=float), p_max)
        trajectories["No_Control"] = dict(
            label=original.NO_CONTROL[0], color=original.NO_CONTROL[1],
            times=np.r_[0.0, times[keep]], load=np.r_[load0, load[keep]],
            cells=np.r_[0, cells[keep]],
        )
        margin = np.asarray(f["min_margin_by_substep"][:], dtype=float)
        threshold = float(f["severe_margin_threshold"][()])
        first = int(np.flatnonzero(margin <= threshold)[0])
        if times[first] != shutdown_day:
            raise ValueError("Recorded shutdown differs from the first threshold crossing")
        shutdown = dict(
            day=shutdown_day, ratio=float(load[first]), cells=int(cells[first]),
            first_saved_crossing_1based=first + 1,
            minimum_relative_margin=float(margin[first]),
            previous_saved_day=float(times[first - 1]),
            previous_minimum_relative_margin=float(margin[first - 1]),
            margin_threshold=threshold, stored_last_day=float(times[-1]),
        )
    return trajectories, shutdown


def draw_stacked_figure(trajectories, shutdown):
    plt.rcParams.update({
        "font.family": "serif", "mathtext.fontset": "dejavuserif",
        "axes.labelsize": 18, "xtick.labelsize": 16, "ytick.labelsize": 16,
        "legend.fontsize": 16,
    })
    fig, (ax_ratio, ax_cells) = plt.subplots(
        2, 1, figsize=(16, 9), sharex=True, gridspec_kw={"height_ratios": [1.1, 1]},
    )
    fig.subplots_adjust(left=0.115, right=0.98, bottom=0.145, top=0.845, hspace=0.11)
    fig.suptitle(
        "Reservoir pressure exceedance over four monitoring steps",
        fontsize=23, y=0.976,
    )
    handles = [Line2D([0], [0], color=c["color"], lw=3, label=c["label"])
               for c in trajectories.values()]
    fig.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.55, 0.936),
               ncol=4, frameon=False, handlelength=2.0, columnspacing=1.6)

    for ax in (ax_ratio, ax_cells):
        ax.set_xlim(0, original.TOTAL_DAYS)
        ax.grid(axis="y", linestyle="--", linewidth=0.6, alpha=0.3)
        ax.set_axisbelow(True)
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
        for boundary in original.STEP_BOUNDARIES:
            ax.axvline(boundary, color="#D1D5DB", lw=1.1, ls="--", zorder=0)
        ax.axvline(shutdown["day"], color=original.FRACTURE_COLOR, lw=1.5,
                   ls=":", alpha=0.9, zorder=2)

    for case in trajectories.values():
        ax_ratio.plot(case["times"], case["load"], color=case["color"], lw=3, zorder=4)
        ax_cells.plot(case["times"], case["cells"], color=case["color"], lw=2.2,
                      ls="--", alpha=0.78, zorder=3, clip_on=False)

    # Preserve the original ratio range; the separate count axis starts at zero.
    ax_ratio.set_ylim(0.77, max(1.13, shutdown["ratio"] * 1.035))
    ax_ratio.set_yticks(np.arange(0.8, 1.101, 0.05))
    ax_ratio.yaxis.set_major_formatter(StrMethodFormatter("{x:.2f}"))
    ax_ratio.set_ylabel("Maximum pressure-to-limit\nratio [-]", labelpad=12)
    ax_ratio.axhline(1.0, color="#111827", lw=1.6, ls="--", zorder=1)
    ax_ratio.text(1895, 1.008, "Model pressure limit (ratio = 1)",
                  ha="right", va="bottom", fontsize=15, color="#111827")
    for idx, center in enumerate(original.STEP_CENTERS, 1):
        ax_ratio.text(center, 1.028, f"Step {idx}", transform=ax_ratio.get_xaxis_transform(),
                      ha="center", va="bottom", fontsize=16, color="#4B5563")
    ax_ratio.tick_params(axis="x", labelbottom=False)

    max_cells = max(int(np.max(c["cells"])) for c in trajectories.values())
    ax_cells.set_ylim(0, max(2000, np.ceil(max_cells * 1.1 / 2000) * 2000))
    ax_cells.set_yticks(np.arange(0, ax_cells.get_ylim()[1] + 1, 2000))
    ax_cells.yaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))
    ax_cells.set_ylabel("Pressure-exceeding\ncells [-]", labelpad=12)
    ax_cells.set_xticks(np.arange(0, 1921, 240))
    ax_cells.set_xlabel("Time [days]", labelpad=8)

    # Each star has its own data coordinates: neither uses a twin-axis transform.
    for ax, value in ((ax_ratio, shutdown["ratio"]), (ax_cells, shutdown["cells"])):
        ax.scatter([shutdown["day"]], [value], color=original.FRACTURE_COLOR,
                   marker="*", s=340, edgecolor="white", linewidth=1, zorder=7)
    ax_ratio.annotate(
        f"No-control shutdown (day {shutdown['day']:.0f})\nPressure ratio: {shutdown['ratio']:.6f}",
        xy=(shutdown["day"], shutdown["ratio"]), xytext=(900, 1.094),
        fontsize=16, ha="left", va="center", color="#374151",
        arrowprops={"arrowstyle": "-", "color": original.NO_CONTROL[1], "lw": 1.3},
    )
    ax_cells.annotate(
        f"No-control shutdown\nPeak: {shutdown['cells']:,} cells",
        xy=(shutdown["day"], shutdown["cells"]), xytext=(900, 6450),
        fontsize=16, ha="left", va="center", color=original.NO_CONTROL[1],
        arrowprops={"arrowstyle": "-", "color": original.NO_CONTROL[1], "lw": 1.3},
    )
    for key, xytext in (("POF_eps0p01", (180, 1500)), ("CVaR_g01_a001", (515, 3300))):
        case = trajectories[key]
        idx = int(np.argmax(case["cells"]))
        ax_cells.annotate(
            f"Peak: {int(case['cells'][idx]):,} cells",
            xy=(case["times"][idx], case["cells"][idx]), xytext=xytext,
            fontsize=16, color=case["color"], fontweight="bold",
            arrowprops={"arrowstyle": "-", "color": case["color"], "lw": 1.3},
            bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.9, "pad": 1.5},
        )
    zero_case = trajectories["POF_eps0"]
    ax_cells.text(1880, 1100, rf"PoF $\varepsilon = 0.0$: peak {int(np.max(zero_case['cells']))} cells",
                  ha="right", color=zero_case["color"], fontsize=16)
    fig.text(
        0.55, 0.025,
        '“Severe fracture”: model shutdown criterion min(r) ≤ −0.1 ⇔ max(p/p_max) ≥ 1.1; '
        'no physical fracture is simulated.',
        ha="center", va="bottom", fontsize=12.5, color="#4B5563",
    )
    return fig, (ax_ratio, ax_cells)


def draw_figure(trajectories, shutdown, layout="dual"):
    """Keep the current dual-axis layout and mark both shutdown endpoints."""
    if layout == "stacked":
        return draw_stacked_figure(trajectories, shutdown)
    plt.rcParams.update({
        "font.family": "serif", "mathtext.fontset": "dejavuserif",
        "axes.labelsize": 21, "xtick.labelsize": 18, "ytick.labelsize": 18,
    })
    fig, ax_ratio = plt.subplots(figsize=(16, 9))
    ax_cells = ax_ratio.twinx()
    fig.subplots_adjust(left=0.095, right=0.905, bottom=0.105, top=0.765)
    ax_ratio.set_xlim(0, original.TOTAL_DAYS)
    # Preserve v2 limits: fixed ratio floor and 3.5% endpoint headroom;
    # zero-based counts with 10% headroom rounded up to a 2000-cell tick.
    # These are independent display ranges, not a conversion between metrics.
    ax_ratio.set_ylim(0.77, max(1.13, shutdown["ratio"] * 1.035))
    max_cells = max(int(np.max(c["cells"])) for c in trajectories.values())
    ax_cells.set_ylim(0, max(2000, np.ceil(max_cells * 1.1 / 2000) * 2000))
    ax_ratio.grid(axis="y", linestyle="--", linewidth=0.55, alpha=0.42)
    for boundary in original.STEP_BOUNDARIES:
        ax_ratio.axvline(boundary, color="#D1D5DB", lw=1.1, ls="--", zorder=0)
    ax_ratio.axvline(shutdown["day"], color=original.FRACTURE_COLOR, lw=1.5,
                     ls=":", alpha=0.9, zorder=2)
    for case in trajectories.values():
        ax_ratio.plot(case["times"], case["load"], color=case["color"], lw=3, zorder=4)
        ax_cells.plot(case["times"], case["cells"], color=case["color"], lw=2.2,
                      ls="--", alpha=0.78, zorder=3, clip_on=False)
    ax_ratio.scatter([shutdown["day"]], [shutdown["ratio"]],
                     color=original.FRACTURE_COLOR, edgecolor="white", linewidth=0.8,
                     marker="*", s=SHUTDOWN_STAR_AREA, zorder=7)
    # Each endpoint stays in its own axis's data coordinates. Only annotation
    # text is offset. Both stars share the same fill, size and white edge.
    ax_cells.scatter([shutdown["day"]], [shutdown["cells"]],
                     color=original.FRACTURE_COLOR, edgecolor="white", linewidth=0.8,
                     marker="*", s=SHUTDOWN_STAR_AREA, zorder=7)
    for ax, value, text, offset in (
        (ax_ratio, shutdown["ratio"],
         f"Pressure ratio: {shutdown['ratio']:.4f}", (55, 6)),
        (ax_cells, shutdown["cells"],
         f"Peak: {shutdown['cells']:,} cells", (55, -28)),
    ):
        ax.annotate(
            text, xy=(shutdown["day"], value), xycoords="data",
            xytext=offset, textcoords="offset points", ha="left", va="center",
            color=original.NO_CONTROL[1], fontsize=15, fontweight="bold",
            arrowprops=dict(arrowstyle="-", color=original.FRACTURE_COLOR,
                            linewidth=1.4),
            bbox=dict(boxstyle="round,pad=0.22", facecolor="white", alpha=0.95,
                      edgecolor=original.NO_CONTROL[1]), zorder=8,
        )
    ax_ratio.axhline(1.0, color="#111827", lw=1.6, ls="--", zorder=1)
    ax_ratio.text(1905, 1.006, "Fracture pressure limit (ratio = 1)",
                  ha="right", va="bottom", fontsize=16, color="#111827")
    ax_ratio.set_ylabel("Maximum pressure-to-limit ratio [-]", labelpad=10)
    ax_cells.set_ylabel("Pressure-exceeding cells [-]", labelpad=12)
    ax_ratio.set_xlabel("Time [days]", labelpad=8)
    ax_ratio.set_yticks(np.arange(0.8, 1.101, 0.05))
    ax_ratio.yaxis.set_major_formatter(StrMethodFormatter("{x:.2f}"))
    ax_cells.set_yticks(np.arange(0, ax_cells.get_ylim()[1] + 1, 1000))
    ax_cells.yaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))

    for key, xytext in (("POF_eps0p01", (470, 620)),
                        ("CVaR_g01_a001", (505, 2850))):
        case = trajectories[key]
        idx = int(np.argmax(case["cells"]))
        ax_cells.annotate(
            f"Peak: {int(case['cells'][idx]):,} cells",
            xy=(case["times"][idx], case["cells"][idx]), xytext=xytext,
            color=case["color"], fontsize=15, fontweight="bold",
            arrowprops=dict(arrowstyle="-", color=case["color"], linewidth=1.4),
            bbox=dict(boxstyle="round,pad=0.22", facecolor="white", alpha=0.88,
                      edgecolor=case["color"]), zorder=8,
        )
    zero_case = trajectories["POF_eps0"]
    ax_cells.text(
        1875, 520,
        rf"PoF $\varepsilon = 0.0$: {int(np.max(zero_case['cells']))} exceeding cells",
        ha="right", va="center", fontsize=15, color=zero_case["color"],
        bbox=dict(boxstyle="round,pad=0.22", facecolor="white", alpha=0.88,
                  edgecolor=zero_case["color"]), zorder=8,
    )
    for step, center in enumerate(original.STEP_CENTERS, 1):
        ax_ratio.text(center, ax_ratio.get_ylim()[1] - 0.008, f"Step {step}",
                      ha="center", va="top", fontsize=16.5, color="#4B5563",
                      bbox=dict(facecolor="white", edgecolor="none", pad=1.0))

    case_handles = [Line2D([0], [0], color=c["color"], lw=3.2, label=c["label"])
                    for c in trajectories.values()]
    style_handles = [
        Line2D([0], [0], color="#111827", lw=3,
               label="Maximum pressure-to-limit ratio (left axis)"),
        Line2D([0], [0], color="#111827", lw=2.2, ls="--",
               label="Pressure-exceeding cells (right axis)"),
        Line2D([0], [0], color=original.FRACTURE_COLOR, marker="*",
               markersize=np.sqrt(SHUTDOWN_STAR_AREA), markeredgecolor="white",
               markeredgewidth=0.8, lw=0,
               label=f"Severe pressure exceedance (day {shutdown['day']:.0f})"),
    ]
    fig.legend(handles=case_handles, loc="upper left", bbox_to_anchor=(0.055, 0.99),
               framealpha=0.96, title="Cases", title_fontsize=18, ncol=2,
               borderpad=0.45, labelspacing=0.35, handlelength=2.2,
               columnspacing=0.95, fontsize=15)
    fig.legend(handles=style_handles, loc="upper right", bbox_to_anchor=(0.955, 0.99),
               framealpha=0.96, title="Line and marker meaning", title_fontsize=18, ncol=1,
               borderpad=0.45, labelspacing=0.35, handlelength=2.2, fontsize=15)
    fig.suptitle("Reservoir pressure exceedance over four monitoring steps",
                 y=0.815, fontsize=24)
    return fig, (ax_ratio, ax_cells)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-stem", type=Path, default=DEFAULT_STEM)
    parser.add_argument("--layout", choices=("dual", "stacked"), default="dual")
    args = parser.parse_args()
    outputs = [args.output_stem.with_suffix(s) for s in (".png", ".json")]
    for output in outputs:
        if output.exists():
            raise FileExistsError(f"Preserving existing export; choose a new --output-stem: {output}")
    args.output_stem.parent.mkdir(parents=True, exist_ok=True)
    sources = [Path(__file__), Path(original.__file__), original.BASE_DATA,
               original.POF_SENSITIVITY_DATA, original.CVAR_SENSITIVITY_DATA, original.NO_CONTROL_DATA]
    fingerprints = {str(p.relative_to(original.BASE)): sha256(p) for p in sources}
    trajectories, shutdown = load_trajectories()
    fig, axes = draw_figure(trajectories, shutdown, layout=args.layout)
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    for text in fig.findobj(match=plt.Text):
        if text.get_visible() and text.get_text():
            box = text.get_window_extent(renderer)
            if box.x0 < 0 or box.y0 < 0 or box.x1 > fig.bbox.width or box.y1 > fig.bbox.height:
                raise ValueError(f"Text outside the export canvas: {text.get_text()!r}")
    fig.savefig(outputs[0], dpi=240, facecolor="white")
    print(f"Saved: {outputs[0]}")
    audit = dict(
        layout=args.layout,
        original_script=str(Path(original.__file__).relative_to(original.BASE)),
        source_sha256=fingerprints,
        metrics=dict(ratio="max_ij(p_res[i,j,h] / p_max[i,j])",
                     count="sum_ij(1[p_res[i,j,h] > p_max[i,j]])",
                     relative_margin="(p_max - p_res) / p_max"),
        shutdown=shutdown,
        original_ratio_limits=[0.77, max(1.13, shutdown["ratio"] * 1.035)],
        original_count_limits=[-180, shutdown["cells"] * 1.1],
        original_star_axis="ax_load, data coordinates (severe_day, severe_load)",
        new_ratio_limits=list(axes[0].get_ylim()), new_count_limits=list(axes[1].get_ylim()),
        axis_limit_selection=dict(
            ratio="[0.77, max(1.13, shutdown_ratio * 1.035)]",
            cells="[0, max(2000, ceil(max_plotted_cells * 1.1 / 2000) * 2000)]",
            interpretation="Independent display headroom; no endpoint alignment or metric conversion.",
        ),
        cases={key: dict(
            sample_count=len(case["times"]), first_day=float(case["times"][0]),
            last_day=float(case["times"][-1]), peak_cells=int(np.max(case["cells"])),
            peak_ratio=float(np.max(case["load"])),
            first_peak_count_day=float(case["times"][np.argmax(case["cells"])]),
            color=case["color"],
        ) for key, case in trajectories.items()},
    )
    if args.layout == "dual":
        audit["baseline_export"] = "pressure_risk_trajectory_over_four_steps_content_revision_v2_20260915.png"
        audit["shutdown_markers"] = dict(
            label=f"Severe pressure exceedance (day {shutdown['day']:.0f})",
            marker="*", color=original.FRACTURE_COLOR,
            size_points_squared=SHUTDOWN_STAR_AREA, linear_scale_from_v2=SHUTDOWN_STAR_SCALE,
            pressure_ratio=dict(axis="left", xy=[shutdown["day"], shutdown["ratio"]], fill="red"),
            exceeding_cells=dict(axis="right", xy=[shutdown["day"], shutdown["cells"]], fill="red"),
            callout_coordinates="Each anchor uses its own axis data coordinates; only text is offset in points.",
        )
    plt.close(fig)
    if fingerprints != {str(p.relative_to(original.BASE)): sha256(p) for p in sources}:
        raise RuntimeError("An input changed while rendering")
    outputs[-1].write_text(json.dumps(audit, indent=2) + "\n")
    print(json.dumps(audit["shutdown"], indent=2))
    print("All input hashes unchanged.")


if __name__ == "__main__":
    main()
