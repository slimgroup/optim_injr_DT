#!/usr/bin/env python3
"""Paper figure: injection rate and cumulative CO2 over the four monitoring steps."""

from __future__ import annotations

import csv
import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


BASE = Path(__file__).resolve().parents[2]
OUTDIR = BASE / "plots" / "paper_figures"
OUTDIR.mkdir(parents=True, exist_ok=True)

PERIOD_DAYS = 80.0
PERIOD_SECONDS = PERIOD_DAYS * 24 * 60 * 60
RHO_CO2 = 700.0  # kg / m^3, consistent with other paper plotting scripts
N_PERIODS_PER_STEP = 6
TOTAL_STEPS = 4

CASE_SCHEDULES = {
    "POF eps = 0.0": [
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
        0.06695,
        0.07189,
        0.07682,
        0.08176,
        0.08670,
    ],
    "POF eps = 0.01": [
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
        0.08063,
        0.08103,
        0.08143,
        0.08183,
        0.08224,
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
        0.11935,
        0.12003,
        0.12072,
        0.12141,
        0.12210,
    ],
}


def make_no_control_schedule() -> tuple[np.ndarray, float]:
    """
    Stylized no-control campaign.

    The schedule ramps up without optimization, fractures at day 720,
    and is terminated after that point.
    """
    frac_day = 480.0 + 240.0
    frac_period = int(frac_day / PERIOD_DAYS)
    rates = np.zeros(N_PERIODS_PER_STEP * TOTAL_STEPS, dtype=float)
    rates[:frac_period] = np.linspace(0.012, 0.180, frac_period)
    return rates, frac_day


def cumulative_mt(rates: np.ndarray) -> np.ndarray:
    volumes = rates * PERIOD_SECONDS
    mass_mt = np.cumsum(volumes * RHO_CO2) / 1e9
    return mass_mt


def step_series(rates: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    t = np.arange(len(rates) + 1, dtype=float) * PERIOD_DAYS
    y = np.r_[rates, rates[-1] if len(rates) else 0.0]
    return t, y


def line_series(cum_mt: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    t = np.arange(len(cum_mt) + 1, dtype=float) * PERIOD_DAYS
    y = np.r_[0.0, cum_mt]
    return t, y


def write_csv(path: Path, schedules: dict[str, np.ndarray], no_control: np.ndarray) -> None:
    fieldnames = ["period", "time_day", "case", "inj_rate_m3_per_s", "cum_co2_mt"]
    rows = []
    for case, rates in {**schedules, "No control": no_control}.items():
        cum = cumulative_mt(rates)
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
        "POF eps = 0.0": "#0E7490",
        "POF eps = 0.01": "#D97706",
        "CVaR γ = 0.1, α = 0.01": "#B91C1C",
        "No control": "#6B7280",
    }

    plt.rcParams.update(
        {
            "font.family": "serif",
            "axes.titlesize": 16,
            "axes.labelsize": 15,
            "xtick.labelsize": 12,
            "ytick.labelsize": 12,
            "legend.fontsize": 11,
        }
    )

    fig, ax = plt.subplots(figsize=(13.8, 7.4))
    ax2 = ax.twinx()

    for i in range(1, TOTAL_STEPS):
        ax.axvline(i * N_PERIODS_PER_STEP * PERIOD_DAYS, color="#D1D5DB", linewidth=1.0, linestyle="--", zorder=0)

    for step_idx, x in enumerate([240, 720, 1200, 1680], start=1):
        ax.text(x, 0.195, f"Step {step_idx}", ha="center", va="top", fontsize=10.5, color="#4B5563")

    for case, rates in schedules.items():
        color = colors[case]
        t_rate, y_rate = step_series(rates)
        t_cum, y_cum = line_series(cumulative_mt(rates))
        ax.step(t_rate, y_rate, where="post", color=color, linewidth=2.6, label=case)
        ax2.plot(t_cum, y_cum, color=color, linewidth=1.6, alpha=0.32)

    no_control_case = "No control"
    t_rate, y_rate = step_series(no_control)
    t_cum, y_cum = line_series(cumulative_mt(no_control))
    ax.step(
        t_rate,
        y_rate,
        where="post",
        color=colors[no_control_case],
        linewidth=2.6,
        linestyle="--",
        label=no_control_case,
    )
    ax2.plot(t_cum, y_cum, color=colors[no_control_case], linewidth=1.6, alpha=0.38, linestyle="--")

    frac_idx = int(frac_day / PERIOD_DAYS)
    frac_rate = no_control[frac_idx - 1]
    frac_mass = cumulative_mt(no_control)[frac_idx - 1]
    ax.scatter(
        [frac_day],
        [frac_rate],
        color="#DC2626",
        edgecolor="white",
        linewidth=0.8,
        marker="*",
        s=180,
        zorder=6,
    )
    ax2.scatter(
        [frac_day],
        [frac_mass],
        color="#DC2626",
        edgecolor="white",
        linewidth=0.8,
        marker="*",
        s=140,
        zorder=6,
    )
    ax.axvline(frac_day, color="#DC2626", linewidth=1.2, linestyle=":", alpha=0.9)
    ax.annotate(
        "Fracture\n(day 720)",
        xy=(frac_day, frac_rate),
        xytext=(34, 18),
        textcoords="offset points",
        fontsize=10.5,
        ha="left",
        va="bottom",
        color="#991B1B",
        bbox=dict(boxstyle="round,pad=0.22", facecolor="white", alpha=0.95, edgecolor="#DC2626"),
        arrowprops=dict(arrowstyle="->", color="#DC2626"),
    )

    ax.set_xlim(0, N_PERIODS_PER_STEP * TOTAL_STEPS * PERIOD_DAYS)
    ax.set_ylim(0.0, 0.20)
    ax2.set_ylim(0.0, max(line_series(cumulative_mt(no_control))[1].max(), max(cumulative_mt(v).max() for v in schedules.values())) * 1.08)

    ax.set_xlabel("Time [days]")
    ax.set_ylabel("Injection rate [m$^3$/s]")
    ax2.set_ylabel("Total injected CO$_2$ [Mt]")

    ax.set_title("Injection Schedules and Cumulative CO$_2$ Across Four Monitoring Steps")
    ax.grid(True, axis="y", linestyle="--", linewidth=0.5, alpha=0.4)

    handles1, labels1 = ax.get_legend_handles_labels()
    ax.legend(handles1, labels1, loc="upper left", bbox_to_anchor=(0.01, 0.72), framealpha=0.95)

    ax.text(
        0.015,
        0.96,
        "Faint lines = cumulative CO$_2$ | red star = fracture onset",
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=10.1,
        color="#374151",
        bbox=dict(boxstyle="round,pad=0.20", facecolor="white", alpha=0.90, edgecolor="#D1D5DB"),
    )

    ax.text(
        0.015,
        0.91,
        "POF ε = 0.0 overlaps the saved CVaR γ = 0.0 schedules.",
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=9.8,
        color="#4B5563",
    )

    fig.tight_layout()

    png_path = OUTDIR / "monitoring_campaign_schedule.png"
    csv_path = OUTDIR / "monitoring_campaign_schedule_data.csv"
    fig.savefig(png_path, dpi=300, bbox_inches="tight")
    plt.close(fig)

    write_csv(csv_path, schedules, no_control)

    print(f"Saved: {png_path}")
    print(f"Saved: {csv_path}")


if __name__ == "__main__":
    main()
