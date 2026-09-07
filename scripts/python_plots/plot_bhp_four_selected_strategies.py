#!/usr/bin/env python3
"""Export the four requested ground-truth BHP histories from completed audits."""
import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

CASES = [
    ("POF_eps0", r"PoF $\varepsilon=0$", "#0E7490"),
    ("POF_eps0p01", r"PoF $\varepsilon=0.01$", "#D97706"),
    ("CVaR_g01_a001", r"CVaR $\alpha=0.01,\ \gamma=0.1$", "#B91C1C"),
    ("No_Control_shutdown", "No control", "#6B7280"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audit_dir", type=Path)
    parser.add_argument("data_dir", type=Path)
    parser.add_argument("plot_dir", type=Path)
    parser.add_argument("--pdf", action="store_true", help="Also export PDF when explicitly requested")
    args = parser.parse_args()
    paths = [args.data_dir / name for name in (
        "bhp_four_strategies_summary.csv", "bhp_four_strategies_timeseries.csv",
        "bhp_four_strategies_well_nodes.csv", "bhp_four_strategies_table.tex")]
    paths.append(args.plot_dir / "bhp_four_strategies.png")
    if args.pdf:
        paths.append(args.plot_dir / "bhp_four_strategies.pdf")
    if any(p.exists() for p in paths):
        raise FileExistsError("Choose new output directories; existing artifacts are preserved")
    for case, _, _ in CASES:
        if not (args.audit_dir / f"{case}_complete.txt").exists():
            raise RuntimeError(f"Missing completed replay: {case}")
    allnodes = [pd.read_csv(args.audit_dir / f"{case}_pressures.csv") for case, _, _ in CASES]
    histories = [df[df.node == 1].copy() for df in allnodes]
    rows = []
    for (case, _, _), nodes, df in zip(CASES, allnodes, histories):
        expected = 91 if case == "No_Control_shutdown" else 240
        assert len(df) == expected and (nodes.groupby("substep").size() == 8).all()
        assert np.array_equal(df.time_days, np.arange(1, expected + 1) * 8)
        peak = df.loc[df.bhp_reference_pa.idxmax()]
        rows.append(dict(case=case, ground_truth_index=2000,
            reference_depth_m=float(peak.reference_depth_m), requested_output_interval_days=8,
            outputs=expected, end_day=float(df.time_days.max()),
            maximum_bhp_MPa=float(peak.bhp_reference_pa / 1e6),
            day_of_maximum=float(peak.time_days), physical_limit_status="not_calibrated"))
    args.data_dir.mkdir(parents=True, exist_ok=True)
    args.plot_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(paths[0], index=False)
    pd.concat(histories, ignore_index=True).to_csv(paths[1], index=False)
    pd.concat(allnodes, ignore_index=True).to_csv(paths[2], index=False)
    tex = [r"\begin{table}[t]", r"\centering",
        r"\caption{Maximum reference-depth BHP for the selected schedules on the ground-truth permeability realization. BHP is the simulator pressure at 1196.875 m, sampled every 8 days. Controlled cases cover 1920 days; no control covers the period through its day-728 shutdown. These values are diagnostics, not evidence of compliance with a calibrated operational BHP limit.}",
        r"\label{tab:ground_truth_bhp}", r"\begin{tabular}{lrrr}", r"\hline",
        r"Strategy & End day & Max. BHP (MPa) & Peak day \\", r"\hline"]
    for (_, label, _), row in zip(CASES, rows):
        tex.append(f"{label} & {row['end_day']:.0f} & {row['maximum_bhp_MPa']:.3f} & {row['day_of_maximum']:.0f} " + r"\\")
    tex += [r"\hline", r"\end{tabular}", r"\end{table}"]
    paths[3].write_text("\n".join(tex) + "\n")
    plt.rcParams.update({"font.family": "serif", "font.size": 14,
        "axes.labelsize": 16, "axes.titlesize": 17, "legend.fontsize": 12})
    fig, ax = plt.subplots(figsize=(10.8, 5.4), layout="constrained")
    for (case, label, color), df in zip(CASES, histories):
        is_baseline = case == "No_Control_shutdown"
        ax.plot(df.time_days, df.bhp_reference_pa / 1e6, color=color, lw=2.2,
                ls="--" if is_baseline else "-", label=label)
        peak = df.loc[df.bhp_reference_pa.idxmax()]
        ax.scatter(peak.time_days, peak.bhp_reference_pa / 1e6, color=color, s=32, zorder=4)
    for boundary in (480, 960, 1440):
        ax.axvline(boundary, color="0.8", ls=":", lw=1, zorder=0)
    ax.set(xlabel="Time [days]", ylabel="Reference-depth BHP [MPa]", xlim=(0, 1920),
           xticks=[0, 480, 960, 1440, 1920],
           title="Selected injection strategies on ground-truth permeability")
    ax.grid(alpha=0.15)
    ax.legend(loc="upper right", framealpha=0.95)
    fig.savefig(paths[4], dpi=300)
    if args.pdf:
        fig.savefig(paths[5])
    plt.close(fig)
    print(pd.DataFrame(rows).to_string(index=False))
    print("Saved four-strategy CSV files, LaTeX table and PNG" + (" and PDF." if args.pdf else "."))


if __name__ == "__main__":
    main()
