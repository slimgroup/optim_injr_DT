#!/usr/bin/env python3
"""Summarize completed BHP replays; no physical bound or pass/fail is invented."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

CASES = ["POF_eps0", "POF_eps0p01", "CVaR_g01_a001", "No_Control_shutdown",
         "POF_eps0p01_1p65x", "CVaR_g01_a001_1p22x", "CVaR_g01_a001_1p22x_Figure1"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("data_dir", type=Path)
    parser.add_argument("plot_dir", type=Path)
    parser.add_argument("--plot-only", action="store_true", help="Reuse existing summaries and write figures to a new plot directory")
    parser.add_argument("--pdf", action="store_true", help="Also export PDF when explicitly requested")
    args = parser.parse_args()
    for case in CASES:
        if not (args.data_dir / f"{case}_complete.txt").exists():
            raise RuntimeError(f"Incomplete replay: {case}; do not imply full coverage")
    args.plot_dir.mkdir(parents=True, exist_ok=True)
    outputs = [args.data_dir / n for n in ("bhp_summary.csv", "bhp_timeseries.csv", "well_geometry.csv", "validation_summary.json")]
    outputs.append(args.plot_dir / "bhp_selected_schedules.png")
    if args.pdf:
        outputs.append(args.plot_dir / "bhp_selected_schedules.pdf")
    if any(p.exists() for p in outputs[4:]) or (not args.plot_only and any(p.exists() for p in outputs[:4])):
        raise FileExistsError("Summary output already exists; select a new output directory")
    frames = {case: pd.read_csv(args.data_dir / f"{case}_pressures.csv") for case in CASES}
    first = {case: df[df.node == 1].copy() for case, df in frames.items()}
    summaries = []
    validation = {}
    for case, df in first.items():
        expected = 91 if case in ("No_Control_shutdown", "CVaR_g01_a001_1p22x_Figure1") else 240
        assert len(df) == expected and np.array_equal(df.substep, np.arange(1, expected+1))
        allnodes = frames[case]
        assert (allnodes.groupby("substep").size() == 8).all()
        assert np.isfinite(allnodes.node_pressure_pa).all()
        for step, sub in [("all", df), *list(df.groupby("monitoring_step"))]:
            peak = sub.loc[sub.bhp_reference_pa.idxmax()]
            summaries.append(dict(case=case, monitoring_step=step, outputs=len(sub),
                first_output_day=float(sub.time_days.min()), last_output_day=float(sub.time_days.max()),
                minimum_bhp_MPa=float(sub.bhp_reference_pa.min()/1e6),
                maximum_bhp_MPa=float(peak.bhp_reference_pa/1e6), day_of_maximum=float(peak.time_days),
                reference_depth_m=float(peak.reference_depth_m), physical_bound="unresolved",
                minimum_physical_margin_MPa=np.nan, physical_exceedance_count=np.nan,
                physical_exceedance_duration_days=np.nan, coverage="ground_truth_replay_only"))
        check = pd.read_csv(args.data_dir / f"{case}_validation.csv")
        err = (check.max_load-check.saved_max_load).abs()
        saved_rows = check.saved_fractured_cells.notna()
        validation[case] = dict(outputs=len(df), configured_control_targets=list(df.configured_control_target.unique()),
            max_rate_error_m3_s=float((df.rate_actual_m3_s-df.rate_target_m3_s).abs().max()),
            canonical_bhp_max_error_pa=float(check.canonical_bhp_minus_node1_pa.abs().max()),
            saved_field_comparisons=int(check.max_reservoir_error_pa.notna().sum()),
            max_reservoir_error_pa=float(check.max_reservoir_error_pa.max()),
            max_saturation_error=float(check.max_saturation_error.max()),
            max_load_error=float(err.max()),
            saved_fracture_count_mismatches=int((check.loc[saved_rows,"fractured_cells"] != check.loc[saved_rows,"saved_fractured_cells"]).sum()),
            maximum_reservoir_load=float(check.max_load.max()), maximum_fractured_cells=int(check.fractured_cells.max()),
            first_reservoir_exceedance_day=float(check.loc[check.fractured_cells>0,"time_days"].min()))
        figcheck = args.data_dir / f"{case}_figure1_validation.csv"
        if figcheck.exists():
            validation[case]["Figure_1_day728_comparison"] = pd.read_csv(figcheck).to_dict("records")[0]
    summary = pd.DataFrame(summaries)
    geometry = frames[CASES[0]].query("substep == 1")[["node","node_depth_m","perforation","reservoir_cell","x_index","z_index","reservoir_depth_m"]]
    if not args.plot_only:
        summary.to_csv(outputs[0], index=False)
        pd.concat(first.values(), ignore_index=True).to_csv(outputs[1], index=False)
        geometry.to_csv(outputs[2], index=False)
        outputs[3].write_text(json.dumps(validation, indent=2)+"\n")
    plt.rcParams.update({"font.family":"serif", "font.size":13, "axes.labelsize":15, "axes.titlesize":16})
    fig, axes = plt.subplots(1,2,figsize=(15,5.6),sharey=True,layout="constrained")
    specs = [("Original selected schedules", [("POF_eps0",r"PoF $\varepsilon=0$","#0E7490"),
        ("POF_eps0p01",r"PoF $\varepsilon=0.01$","#D97706"),("CVaR_g01_a001",r"CVaR $\alpha=0.01,\ \gamma=0.1$","#B91C1C")]),
        ("Schedules used in the pressure-risk figure", [("POF_eps0",r"PoF $\varepsilon=0$ (base)","#0E7490"),
        ("POF_eps0p01_1p65x",r"PoF $\varepsilon=0.01$ ($1.65\times$)","#D97706"),
        ("CVaR_g01_a001_1p22x",r"CVaR $\alpha=0.01,\ \gamma=0.1$ ($1.22\times$)","#B91C1C")])]
    for ax,(title,lines) in zip(axes,specs):
        for case,label,color in lines:
            df=first[case]
            ax.plot(df.time_days,df.bhp_reference_pa/1e6,label=label,color=color,lw=2)
        df=first["No_Control_shutdown"]
        ax.plot(df.time_days,df.bhp_reference_pa/1e6,label="No control (through day 728)",color="#6B7280",ls="--",lw=1.8)
        ax.scatter(df.time_days.iloc[-1],df.bhp_reference_pa.iloc[-1]/1e6,color="#6B7280",s=30,zorder=4)
        for boundary in [480,960,1440]: ax.axvline(boundary,color="0.82",ls=":",lw=1,zorder=0)
        ax.set(xlim=(0,1920),xticks=[0,480,960,1440,1920],xlabel="Time [days]",title=title)
        ax.grid(alpha=0.15)
        ax.legend(fontsize=10.5,loc="best",framealpha=0.94)
    fig1=first["CVaR_g01_a001_1p22x_Figure1"].iloc[-1]
    axes[1].scatter(fig1.time_days,fig1.bhp_reference_pa/1e6,marker="D",s=40,
                    facecolors="white",edgecolors="#B91C1C",zorder=5,label="Figure 1 CVaR (day 728)")
    axes[1].legend(fontsize=10.5,loc="best",framealpha=0.94)
    axes[0].set_ylabel("Reference-depth BHP [MPa]")
    depth=first[CASES[0]].reference_depth_m.iloc[0]
    fig.suptitle(f"Ground-truth BHP at z = {depth:.3f} m\nSimulator absolute pressure | No calibrated physical BHP bound",fontsize=17)
    fig.savefig(outputs[4],dpi=220)
    if args.pdf:
        fig.savefig(outputs[5])
    plt.close(fig)
    print(summary.query("monitoring_step == 'all'").to_string(index=False))
    print(json.dumps(validation,indent=2))


if __name__ == "__main__":
    main()
