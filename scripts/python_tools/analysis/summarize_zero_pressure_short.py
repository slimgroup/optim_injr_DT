#!/usr/bin/env python3
"""Summarize a separately labelled, one-member eight-day diagnostic."""
import argparse
import csv
import json
from pathlib import Path
import h5py
import numpy as np
from summarize_zero_pressure_audit import metric, write_csv, plt

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("root",type=Path);ap.add_argument("out",type=Path);ap.add_argument("plots",type=Path)
    a=ap.parse_args();a.out.mkdir(exist_ok=False);a.plots.mkdir(parents=True,exist_ok=False)
    fdir=a.root/"members/001"
    config=(fdir/"configuration.txt").read_text()
    profile="tighter_linear" if "solver_profile=tighter_linear" in config else "production"
    with h5py.File(fdir/"initial.jld2") as f:p0=f["p0_pa"][:];phi=f["porosity"][:]
    with h5py.File(fdir/"block_01.jld2") as f:
        p=f["pressure_pa"][:]; t=f["time_days"][:]
        mass=f["actual_mass_rate_kg_s"][:];sat=f["co2_saturation_max"][:]
        elapsed=float(f["elapsed_seconds"][()])
    assert p.shape==(1,256,512) and np.array_equal(t,[8.])
    assert np.all(mass==0) and np.all(sat==0)
    rows=[]
    for domain,mask in (("all_cells",np.ones_like(phi,bool)),("nonpadding",phi!=1e8),("modified_porosity_padding",phi==1e8)):
        for d in (3,4,5):
            r=dict(member=1,realization_id=741,window_days=8,domain=domain,limit_mpa=d,
                scope="separate eight-day diagnostic; not the 480/960-day pilot")
            r.update(metric(p,p0,t,d,mask));rows.append(r)
    write_csv(a.out/"per_member_8day.csv",rows)
    extrema=[]
    for day,field in ((0,p0),(8,p[0])):
        extrema.append(dict(member=1,realization_id=741,time_days=day,pressure_min_pa=float(field.min()),
            pressure_max_pa=float(field.max()),max_overpressure_pa=float((field-p0).max()),
            cells_at_pressure_floor=int(np.sum(field==101325)),initial_time_excluded_from_pof=day==0))
    write_csv(a.out/"pressure_timeseries_8day.csv",extrema)
    meta=dict(scope="Completed separate eight-day diagnostic only",member=1,realization_id=741,solver_profile=profile,
        solver_seconds=elapsed,initial_cells_below_pressure_floor=int(np.sum(p0<101325)),
        day8_cells_at_pressure_floor=int(np.sum(p[0]==101325)),
        non_top_max_overpressure_pa=float((p[0]-p0)[1:,:].max()),
        achieved_surface_mass_rate_kg_s=mass.tolist(),co2_saturation_max=sat.tolist(),
        primary_480_day_pass_count=None,primary_960_day_pass_count=None)
    (a.out/"diagnostic_summary.json").write_text(json.dumps(meta,indent=2)+"\n")
    plt.rcParams.update({"font.size":13,"axes.labelsize":14,"axes.titlesize":14})
    fig,axes=plt.subplots(1,2,figsize=(12,4.4),layout="constrained")
    for k,label in (("pressure_min_pa","Minimum pressure"),("pressure_max_pa","Maximum pressure")):
        axes[0].plot([0,8],[r[k]/1e6 for r in extrema],"o-",label=label)
    axes[0].set(ylabel="Absolute pressure (MPa)",xlabel="Saved time (days)",title="Reservoir pressure extrema")
    axes[0].legend()
    axes[1].plot([0,8],[r["max_overpressure_pa"]/1e6 for r in extrema],"o-",color="#9b2c2c")
    axes[1].set(ylabel="Maximum overpressure (MPa)",xlabel="Saved time (days)",title="Maximum saved overpressure")
    for ax in axes:ax.set_xticks([0,8]);ax.grid(alpha=.25)
    fig.suptitle(f"Eight-day diagnostic only • member 1 / realization 741 • {profile.replace('_',' ')} solver")
    fig.savefig(a.plots/"pressure_over_time_8day.png",dpi=180);plt.close(fig)
    fig,ax=plt.subplots(figsize=(11,4.7),layout="constrained")
    im=ax.imshow((p[0]-p0)/1e6,extent=(0,3200,1600,0),cmap="viridis",vmin=0,aspect="auto")
    ax.set(xlabel="Distance (m)",ylabel="Depth (m)",title="Day 8 pressure increase • member 1 / realization 741")
    cb=fig.colorbar(im,ax=ax,pad=.025);cb.set_label("p − p₀ (MPa)")
    fig.savefig(a.plots/"overpressure_field_8day.png",dpi=180);plt.close(fig)
    profile_description="Production solver defaults are retained." if profile=="production" else "Only linear relative tolerance is tightened from 1e-3 to 1e-6; all nonlinear tolerances, physical parameters, initial fields, mask and controls are unchanged."
    counts={r['limit_mpa']:r['exceeding_cell_times'] for r in rows if r['domain']=='all_cells'}
    text=["# Eight-day convergence diagnostic — completed","",
        f"This separate short run uses member 1 (BroadK realization 741), all-brine initialization and DisabledControl. {profile_description} Its single day-8 output is not a completed 480- or 960-day trajectory.","",
        f"Maximum overpressure is {rows[0]['max_overpressure_pa']:.9g} Pa ({rows[0]['max_overpressure_mpa']:.9g} MPa). Exceeding cell counts by limit in MPa: {counts}. Exact PoF, clean CVaR and the distinct logistic surrogate are exported separately.","",
        f"All 512 initial top-row cells start at 62500 Pa, below the 101325 Pa pressure-variable minimum. At day 8, {meta['day8_cells_at_pressure_floor']} cells are exactly at that minimum. The largest increase outside the top row is {meta['non_top_max_overpressure_pa']:.9g} Pa. Surface mass rate and CO2 saturation are exactly zero in the saved output. The initial pressure-floor gap is 38825 Pa; the role of hydrostatic and well/boundary flux imbalance also requires the solver records.","",
        f"The simulator call took {elapsed:.3f} s. Raw nonlinear/ministep reports are retained in block_01.jld2, with CSV exports alongside this report's parent directory. No per-threshold tuning, rerun, bootstrap, reoptimization or geomechanical calibration was performed.","",
        "No long-window manuscript conclusion is supported by this diagnostic alone. The original bounded three-member pilot continues separately and its failed/incomplete outcomes must remain visible."]
    (a.out/"report_8day.md").write_text("\n".join(text)+"\n")
    print(json.dumps(meta,indent=2))

if __name__=="__main__":main()
