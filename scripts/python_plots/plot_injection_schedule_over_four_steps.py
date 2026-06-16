#!/usr/bin/env python3
"""Paper figure: injection rate and cumulative CO2 over the four monitoring steps."""

from __future__ import annotations

import csv
import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", str(Path(__file__).resolve().parents[2] / ".mplconfig"))

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import h5py
import numpy as np


BASE = Path(__file__).resolve().parents[2]
OUTDIR = BASE / "plots" / "paper_figures"
OUTDIR.mkdir(parents=True, exist_ok=True)
FORWARD_DATA = OUTDIR / "forward_sim_four_steps_base_data.jld2"
NO_CONTROL_SEVERE_DATA = OUTDIR / "no_control_delayed_ramp_10_periods.jld2"

PERIOD_DAYS = 80.0
PERIOD_SECONDS = PERIOD_DAYS * 24 * 60 * 60
RHO_CO2 = 700.0  # kg / m^3, consistent with other paper plotting scripts
N_PERIODS_PER_STEP = 6
TOTAL_STEPS = 4

CASE_SCHEDULES = {
    "PoF eps = 0.0 (= CVaR γ = 0.0)": [
        0.00010,
        0.00534,
        0.01058,
        0.01582,
        0.02106,
        0.02630,
        0.02630,
        0.03002,
        0.03373,
        0.03745,
        0.04117,
        0.04489,
        0.04489,
        0.04831,
        0.05174,
        0.05516,
        0.05859,
        0.06201,
        0.06201,
        0.06425,
        0.06650,
        0.06874,
        0.07099,
        0.07323,
    ],
    "PoF eps = 0.01": [
        0.00010,
        0.00914,
        0.01818,
        0.02722,
        0.03626,
        0.04530,
        0.04530,
        0.05087,
        0.05645,
        0.06203,
        0.06760,
        0.07317,
        0.07317,
        0.07458,
        0.07599,
        0.07741,
        0.07882,
        0.08023,
        0.08023,
        0.08041,
        0.08059,
        0.08078,
        0.08096,
        0.08114,
    ],
    "CVaR γ = 0.1, α = 0.01": [
        0.00010,
        0.01502,
        0.02994,
        0.04486,
        0.05978,
        0.07470,
        0.07470,
        0.08282,
        0.09094,
        0.09906,
        0.10717,
        0.11529,
        0.11529,
        0.11596,
        0.11664,
        0.11731,
        0.11798,
        0.11866,
        0.11866,
        0.11897,
        0.11928,
        0.11960,
        0.11991,
        0.12022,
    ],
}


def make_no_control_schedule() -> tuple[np.ndarray, float]:
    """Use a real uncontrolled ramp and stop injection at severe fracture."""
    rates = np.r_[np.linspace(0.0, 0.2, N_PERIODS_PER_STEP), np.full(N_PERIODS_PER_STEP * (TOTAL_STEPS - 1), 0.2)]
    frac_day = np.nan
    if NO_CONTROL_SEVERE_DATA.exists():
        with h5py.File(NO_CONTROL_SEVERE_DATA, "r") as f:
            saved_rates = np.asarray(f["full_rates"][:], dtype=float)
            if saved_rates.shape == rates.shape:
                rates = saved_rates
            frac_day = float(f["severe_day"][()])
            if np.isfinite(frac_day):
                rates[int(np.ceil(frac_day / PERIOD_DAYS)) :] = 0.0
    return rates, frac_day


def cumulative_mt(rates: np.ndarray, stop_day: float = np.nan) -> np.ndarray:
    durations_days = np.full(len(rates), PERIOD_DAYS)
    if np.isfinite(stop_day):
        starts = np.arange(len(rates), dtype=float) * PERIOD_DAYS
        durations_days = np.clip(stop_day - starts, 0.0, PERIOD_DAYS)
    volumes = rates * durations_days * 24 * 60 * 60
    mass_mt = np.cumsum(volumes * RHO_CO2) / 1e9
    return mass_mt


def step_series(rates: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    t = np.arange(len(rates) + 1, dtype=float) * PERIOD_DAYS
    y = np.r_[rates, rates[-1] if len(rates) else 0.0]
    return t, y


def stopped_step_series(rates: np.ndarray, stop_day: float) -> tuple[np.ndarray, np.ndarray]:
    t, y = step_series(rates)
    if not np.isfinite(stop_day) or stop_day in t:
        return t, y
    insert_at = int(np.searchsorted(t, stop_day))
    return np.insert(t, insert_at, stop_day), np.insert(y, insert_at, 0.0)


def line_series(cum_mt: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    t = np.arange(len(cum_mt) + 1, dtype=float) * PERIOD_DAYS
    y = np.r_[0.0, cum_mt]
    return t, y


def stopped_cumulative_series(rates: np.ndarray, stop_day: float) -> tuple[np.ndarray, np.ndarray]:
    if not np.isfinite(stop_day):
        return line_series(cumulative_mt(rates))
    t = np.arange(len(rates) + 1, dtype=float) * PERIOD_DAYS
    if np.isfinite(stop_day) and stop_day not in t:
        t = np.insert(t, int(np.searchsorted(t, stop_day)), stop_day)
    starts = np.arange(len(rates), dtype=float) * PERIOD_DAYS
    mass = []
    for day in t:
        durations = np.clip(min(day, stop_day) - starts, 0.0, PERIOD_DAYS)
        mass.append(np.sum(rates * durations * 24 * 60 * 60) * RHO_CO2 / 1e9)
    return t, np.asarray(mass)


def write_csv(path: Path, schedules: dict[str, np.ndarray], no_control: np.ndarray, frac_day: float) -> None:
    fieldnames = ["period", "time_day", "case", "inj_rate_m3_per_s", "cum_co2_mt"]
    rows = []
    for case, rates in {**schedules, "No control (severe fracture)": no_control}.items():
        cum = cumulative_mt(rates, frac_day if case == "No control (severe fracture)" else np.nan)
        for idx, rate in enumerate(rates, start=1):
            rows.append(
                {
                    "period": idx,
                    "time_day": idx * PERIOD_DAYS,
                    "case": case,
                    "inj_rate_m3_per_s": f"{rate:.8f}",
                    "cum_co2_mt": f"{cum[idx - 1]:.8f}",
                }
            )
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    schedules = {k: np.asarray(v, dtype=float) for k, v in CASE_SCHEDULES.items()}
    no_control, frac_day = make_no_control_schedule()

    colors = {
        "PoF eps = 0.0 (= CVaR γ = 0.0)": "#0E7490",
        "PoF eps = 0.01": "#D97706",
        "CVaR γ = 0.1, α = 0.01": "#B91C1C",
        "No control (severe fracture)": "#6B7280",
    }

    plt.rcParams.update(
        {
            "font.family": "serif",
            "axes.titlesize": 22,
            "axes.labelsize": 19,
            "xtick.labelsize": 16,
            "ytick.labelsize": 16,
            "legend.fontsize": 14,
        }
    )

    fig, ax = plt.subplots(figsize=(15.2, 8.8))
    ax2 = ax.twinx()

    for i in range(1, TOTAL_STEPS):
        ax.axvline(i * N_PERIODS_PER_STEP * PERIOD_DAYS, color="#D1D5DB", linewidth=1.0, linestyle="--", zorder=0)

    for step_idx, x in enumerate([240, 720, 1200, 1680], start=1):
        ax.text(x, 0.221, f"Step {step_idx}", ha="center", va="top", fontsize=13.5, color="#4B5563")

    for case, rates in schedules.items():
        color = colors[case]
        t_rate, y_rate = step_series(rates)
        t_cum, y_cum = line_series(cumulative_mt(rates))
        ax.step(t_rate, y_rate, where="post", color=color, linewidth=3.0, label=case, zorder=4)
        ax2.plot(t_cum, y_cum, color=color, linewidth=2.2, alpha=0.78, linestyle="--", zorder=2)

    no_control_case = "No control (severe fracture)"
    t_rate, y_rate = stopped_step_series(no_control, frac_day)
    t_cum, y_cum = stopped_cumulative_series(no_control, frac_day)
    ax.step(
        t_rate,
        y_rate,
        where="post",
        color=colors[no_control_case],
        linewidth=3.2,
        label=no_control_case,
        zorder=4,
    )
    ax2.plot(t_cum, y_cum, color=colors[no_control_case], linewidth=2.2, alpha=0.82, linestyle="--", zorder=2)

    if np.isfinite(frac_day):
        frac_idx = max(1, int(np.ceil(frac_day / PERIOD_DAYS)))
        frac_rate = no_control[frac_idx - 1]
        frac_mass = stopped_cumulative_series(no_control, frac_day)[1][
            np.where(stopped_cumulative_series(no_control, frac_day)[0] == frac_day)[0][0]
        ]
        ax.scatter(
            [frac_day],
            [frac_rate],
            color="#DC2626",
            edgecolor="white",
            linewidth=1.1,
            marker="*",
            s=560,
            zorder=6,
        )
        ax2.scatter(
            [frac_day],
            [frac_mass],
            color="#DC2626",
            edgecolor="white",
            linewidth=1.1,
            marker="*",
            s=560,
            zorder=6,
        )
        ax.axvline(frac_day, color="#DC2626", linewidth=1.2, linestyle=":", alpha=0.9)

    ax.set_xlim(0, N_PERIODS_PER_STEP * TOTAL_STEPS * PERIOD_DAYS)
    ax.set_ylim(0.0, 0.225)
    ax2.set_ylim(0.0, max(y_cum.max(), max(cumulative_mt(v).max() for v in schedules.values())) * 1.08)

    ax.set_xlabel("Time [days]")
    ax.set_ylabel("Injection rate [m$^3$/s]")
    ax2.set_ylabel("Total injected CO$_2$ [Mt]")

    ax.grid(True, axis="y", linestyle="--", linewidth=0.5, alpha=0.4)

    case_handles = [
        Line2D([0], [0], color=colors[name], linewidth=3.2, label=name)
        for name in ["PoF eps = 0.0 (= CVaR γ = 0.0)", "PoF eps = 0.01", "CVaR γ = 0.1, α = 0.01", "No control (severe fracture)"]
    ]
    style_handles = [
        Line2D([0], [0], color="#111827", linewidth=3.0, linestyle="-", label="Injection rate (left axis)"),
        Line2D([0], [0], color="#111827", linewidth=2.2, linestyle="--", label="Total injected CO$_2$ (right axis)"),
        Line2D([0], [0], color="#DC2626", marker="*", markersize=19, linewidth=0, label="Severe fracture"),
    ]

    legend_cases = fig.legend(
        handles=case_handles,
        loc="upper left",
        bbox_to_anchor=(0.055, 0.988),
        framealpha=0.96,
        title="Cases",
        title_fontsize=15,
        borderpad=0.45,
        labelspacing=0.35,
        handlelength=2.2,
        ncol=2,
        columnspacing=0.95,
    )

    fig.legend(
        handles=style_handles,
        loc="upper right",
        bbox_to_anchor=(0.975, 0.988),
        framealpha=0.96,
        title="Line meaning",
        title_fontsize=15,
        borderpad=0.45,
        labelspacing=0.35,
        handlelength=2.2,
        ncol=2,
        columnspacing=0.9,
    )

    fig.suptitle("Injection Schedules and Cumulative CO$_2$ Across Four Monitoring Steps", y=0.855, fontsize=20)
    fig.tight_layout(rect=[0.02, 0.03, 0.98, 0.87])

    png_path = OUTDIR / "injection_schedule_over_four_steps.png"
    csv_path = OUTDIR / "injection_schedule_over_four_steps_data.csv"
    fig.savefig(png_path, dpi=300, bbox_inches="tight")
    plt.close(fig)

    write_csv(csv_path, schedules, no_control, frac_day)

    print(f"Saved: {png_path}")
    print(f"Saved: {csv_path}")


if __name__ == "__main__":
    main()
