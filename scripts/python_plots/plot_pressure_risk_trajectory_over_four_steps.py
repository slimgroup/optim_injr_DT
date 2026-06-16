#!/usr/bin/env python3
"""Ground-truth pressure-risk trajectories across four monitoring steps."""

from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(__file__).resolve().parents[2] / ".mplconfig"))

import h5py
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D


BASE = Path(__file__).resolve().parents[2]
OUTDIR = BASE / "plots" / "paper_figures"
BASE_DATA = OUTDIR / "forward_sim_four_steps_base_data.jld2"
NO_CONTROL_DATA = OUTDIR / "no_control_delayed_ramp_10_periods.jld2"
POF_SENSITIVITY_DATA = OUTDIR / "pof_eps001_full_campaign_sensitivity_1p65x.jld2"
CVAR_SENSITIVITY_DATA = OUTDIR / "full_campaign_video_CVaR_g01_a001_sensitivity.jld2"
OUTFILE = OUTDIR / "pressure_risk_trajectory_over_four_steps.png"

TOTAL_DAYS = 1920.0
STEP_BOUNDARIES = (480.0, 960.0, 1440.0)
STEP_CENTERS = (240.0, 720.0, 1200.0, 1680.0)

CASES = [
    ("POF_eps0", r"PoF $\varepsilon = 0.0$", "#0E7490"),
    ("POF_eps0p01", r"PoF $\varepsilon = 0.01$", "#D97706"),
    ("CVaR_g01_a001", r"CVaR $\gamma = 0.1,\ \alpha = 0.01$", "#B91C1C"),
]
NO_CONTROL = ("No control", "#6B7280")
FRACTURE_COLOR = "#DC2626"


def pressure_metrics(pressure: np.ndarray, p_max: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return maximum normalized pressure load and fractured-cell count."""
    load = np.max(pressure / p_max, axis=(1, 2))
    fractured = np.count_nonzero(pressure > p_max, axis=(1, 2))
    return load, fractured


def initial_load(p0: np.ndarray, p_max: np.ndarray) -> float:
    """Compute the initial maximum pressure load, accounting for JLD2 orientation."""
    if p0.shape != p_max.shape:
        p0 = p0.T
    return float(np.max(p0 / p_max))


def main() -> None:
    OUTDIR.mkdir(parents=True, exist_ok=True)
    trajectories: dict[str, dict[str, np.ndarray | str]] = {}

    with h5py.File(BASE_DATA, "r") as f:
        p_max = np.asarray(f["p_max"][:], dtype=float)
        load0 = initial_load(np.asarray(f["p0"][:], dtype=float), p_max)
        for key, label, color in CASES:
            pressure = np.asarray(f[f"{key}_pres_snaps"][:], dtype=float)
            load, fractured = pressure_metrics(pressure, p_max)
            times = np.r_[0.0, np.asarray(f[f"{key}_snap_idx"][:], dtype=float) * 8.0]
            trajectories[key] = {
                "label": label,
                "color": color,
                "times": times,
                "load": np.r_[load0, load],
                "fractured": np.r_[0, fractured],
            }

    with h5py.File(POF_SENSITIVITY_DATA, "r") as f:
        dt_days = float(f["dt_days"][()])
        load = np.asarray(f["max_pressure_load_by_substep"][:], dtype=float)
        fractured = np.asarray(f["fractured_cells_by_substep"][:], dtype=int)
        trajectories["POF_eps0p01"]["times"] = np.r_[0.0, np.arange(1, load.size + 1) * dt_days]
        trajectories["POF_eps0p01"]["load"] = np.r_[load0, load]
        trajectories["POF_eps0p01"]["fractured"] = np.r_[0, fractured]

    with h5py.File(CVAR_SENSITIVITY_DATA, "r") as f:
        load = 1.0 - np.asarray(f["min_margin_by_substep"][:], dtype=float)
        fractured = np.asarray(f["fractured_cells_by_substep"][:], dtype=int)
        trajectories["CVaR_g01_a001"]["times"] = np.r_[0.0, np.arange(1, load.size + 1) * 8.0]
        trajectories["CVaR_g01_a001"]["load"] = np.r_[load0, load]
        trajectories["CVaR_g01_a001"]["fractured"] = np.r_[0, fractured]

    with h5py.File(NO_CONTROL_DATA, "r") as f:
        p_max = np.asarray(f["p_max"][:], dtype=float)
        dt_days = float(f["dt_days"][()])
        severe_day = float(f["severe_day"][()])
        pressure = np.asarray(f["pres_all"][:], dtype=float)
        load, fractured = pressure_metrics(pressure, p_max)
        times = np.arange(1, pressure.shape[0] + 1, dtype=float) * dt_days
        keep = times <= severe_day
        load0 = initial_load(np.asarray(f["p0"][:], dtype=float), p_max)
        trajectories["No_Control"] = {
            "label": NO_CONTROL[0],
            "color": NO_CONTROL[1],
            "times": np.r_[0.0, times[keep]],
            "load": np.r_[load0, load[keep]],
            "fractured": np.r_[0, fractured[keep]],
        }

    plt.rcParams.update(
        {
            "font.family": "serif",
            "axes.titlesize": 18,
            "axes.labelsize": 18,
            "xtick.labelsize": 15,
            "ytick.labelsize": 15,
            "legend.fontsize": 14,
        }
    )

    fig, ax_load = plt.subplots(figsize=(15.2, 8.8))
    ax_cells = ax_load.twinx()

    for boundary in STEP_BOUNDARIES:
        ax_load.axvline(boundary, color="#D1D5DB", linewidth=1.1, linestyle="--", zorder=0)
    ax_load.axvline(severe_day, color=FRACTURE_COLOR, linewidth=1.5, linestyle=":", alpha=0.9, zorder=2)
    ax_load.set_xlim(0.0, TOTAL_DAYS)
    ax_load.grid(True, axis="y", linestyle="--", linewidth=0.55, alpha=0.42)

    for case in trajectories.values():
        ax_load.plot(
            case["times"],
            case["load"],
            color=case["color"],
            linewidth=3.0,
            label=case["label"],
            zorder=4,
        )
        ax_cells.plot(
            case["times"],
            case["fractured"],
            color=case["color"],
            linewidth=2.2,
            alpha=0.78,
            linestyle="--",
            label=case["label"],
            zorder=3,
        )

    no_control = trajectories["No_Control"]
    severe_load = float(no_control["load"][-1])
    severe_cells = int(no_control["fractured"][-1])
    ax_load.scatter(
        [severe_day],
        [severe_load],
        color=FRACTURE_COLOR,
        edgecolor="white",
        linewidth=1.2,
        marker="*",
        s=520,
        zorder=7,
    )

    ax_load.axhline(1.0, color="#111827", linewidth=1.6, linestyle="--", zorder=1)
    ax_load.text(
        1905,
        1.006,
        "Fracture-pressure threshold",
        ha="right",
        va="bottom",
        fontsize=13,
        color="#111827",
    )
    ax_load.set_ylim(0.77, max(1.13, severe_load * 1.035))
    ax_load.set_ylabel("Maximum normalized pressure load [-]")

    ax_cells.axhline(0.0, color="#111827", linewidth=1.2, zorder=1)
    ax_cells.set_ylim(-180, severe_cells * 1.10)
    ax_cells.set_ylabel("Fractured cells [-]")
    ax_load.set_xlabel("Time [days]")

    peak_annotations = [
        ("POF_eps0p01", "#D97706", "Peak: 8 cells", (408, 8), (470, 620)),
        ("CVaR_g01_a001", "#B91C1C", "Peak: 2,285 cells", (408, 2285), (505, 2850)),
        ("No_Control", "#6B7280", "Peak: 6,953 cells", (728, severe_cells), (810, 6600)),
    ]
    for _, color, text, xy, xytext in peak_annotations:
        ax_cells.annotate(
            text,
            xy=xy,
            xytext=xytext,
            color=color,
            fontsize=12.5,
            fontweight="bold",
            arrowprops=dict(arrowstyle="-", color=color, linewidth=1.4),
            bbox=dict(boxstyle="round,pad=0.22", facecolor="white", alpha=0.88, edgecolor=color),
            zorder=8,
        )

    for step_idx, center in enumerate(STEP_CENTERS, start=1):
        ax_load.text(
            center,
            ax_load.get_ylim()[1] - 0.008,
            f"Step {step_idx}",
            ha="center",
            va="top",
            fontsize=13.5,
            color="#4B5563",
        )

    case_handles = [
        Line2D([0], [0], color=color, linewidth=3.2, label=label)
        for _, label, color in CASES
    ]
    case_handles.append(Line2D([0], [0], color=NO_CONTROL[1], linewidth=3.2, label=NO_CONTROL[0]))
    style_handles = [
        Line2D([0], [0], color="#111827", linewidth=3.0, linestyle="-", label="Maximum pressure load (left axis)"),
        Line2D([0], [0], color="#111827", linewidth=2.2, linestyle="--", label="Fractured cells (right axis)"),
        Line2D(
            [0],
            [0],
            color=FRACTURE_COLOR,
            marker="*",
            markersize=18,
            linewidth=0,
            label="No-control severe fracture",
        ),
    ]
    fig.legend(
        handles=case_handles,
        loc="upper left",
        bbox_to_anchor=(0.055, 0.988),
        framealpha=0.96,
        title="Cases",
        title_fontsize=15,
        ncol=2,
        borderpad=0.45,
        labelspacing=0.35,
        handlelength=2.2,
        columnspacing=0.95,
        fontsize=11.5,
    )
    fig.legend(
        handles=style_handles,
        loc="upper right",
        bbox_to_anchor=(0.975, 0.988),
        framealpha=0.96,
        title="Line meaning",
        title_fontsize=15,
        ncol=1,
        borderpad=0.45,
        labelspacing=0.35,
        handlelength=2.2,
        columnspacing=0.9,
        fontsize=11.5,
    )

    fig.suptitle("Ground-Truth Pressure Risk Across Four Monitoring Steps", y=0.855, fontsize=20)
    fig.tight_layout(rect=[0.02, 0.035, 0.98, 0.87])
    fig.savefig(OUTFILE, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {OUTFILE}")
    print(f"No-control severe fracture: day={severe_day:.0f}, max load={severe_load:.6f}, cells={severe_cells:,}")


if __name__ == "__main__":
    main()
