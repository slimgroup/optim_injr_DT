#!/usr/bin/env python3
"""Read-only, fixed-trajectory pressure comparisons; write a new report snapshot."""
import argparse
import csv
import hashlib
import json
import math
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import h5py
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

LIMITS=(3,4,5)
WINDOWS=(480,960)
ALPHA=0.01

def write_csv(path, rows):
    with path.open("x", newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]) if rows else ["no_completed_data"])
        w.writeheader(); w.writerows(rows)

def metric(p, p0, times, delta, mask):
    """Input axes time,z,x. Exact >; no tolerance inferred from balance residuals."""
    over=p-p0[None,:,:]
    v=over[:,mask]
    selected=p[:,mask]
    threshold=p0[mask]+delta*1e6
    r=(threshold[None,:]-selected)/threshold[None,:]
    fail=selected>threshold[None,:]
    spatial=np.argwhere(mask)
    ti,ci=np.unravel_index(np.argmax(v),v.shape)
    zi,xi=spatial[ci]
    pmax_t,pmax_c=np.unravel_index(np.argmax(selected),selected.shape)
    pmin_t,pmin_c=np.unravel_index(np.argmin(selected),selected.shape)
    first=np.flatnonzero(np.any(fail,axis=1))
    # Exact weighted alpha tail. Zero losses need not be sorted or stored.
    losses=np.sort((-r[r<0]).ravel())[::-1]
    target=ALPHA*r.size
    whole=int(math.floor(target)); remainder=target-whole
    tail_sum=losses[:whole].sum()
    if remainder and len(losses)>whole: tail_sum+=remainder*losses[whole]
    cvar=float(tail_sum/target)
    dp=float(v[ti,ci]); count=int(fail.sum())
    return dict(max_overpressure_pa=dp,max_overpressure_mpa=dp/1e6,
        min_pressure_margin_pa=delta*1e6-dp,min_pressure_margin_mpa=delta-dp/1e6,
        max_pressure_excess_pa=dp-delta*1e6,max_pressure_excess_mpa=dp/1e6-delta,
        exceeding_cell_times=count,cell_time_denominator=int(v.size),exact_cell_time_pof=count/v.size,
        any_exceedance_exact=bool(count),comparison_tolerance_pa=0.0,
        any_exceedance_tolerance_adjusted=bool(count),first_exceedance_day=float(times[first[0]]) if len(first) else "",
        max_overpressure_day=float(times[ti]),max_overpressure_x_index=int(xi+1),max_overpressure_z_index=int(zi+1),
        max_overpressure_x_center_m=(xi+0.5)*6.25,max_overpressure_z_center_m=(zi+0.5)*6.25,
        max_overpressure_tied_entries=int(np.count_nonzero(v==dp)),
        pressure_min_pa=float(selected.min()),pressure_max_pa=float(selected.max()),
        pressure_min_day=float(times[pmin_t]),pressure_max_day=float(times[pmax_t]),
        pressure_min_x_index=int(spatial[pmin_c,1]+1),pressure_min_z_index=int(spatial[pmin_c,0]+1),
        pressure_max_x_index=int(spatial[pmax_c,1]+1),pressure_max_z_index=int(spatial[pmax_c,0]+1),
        clean_cvar_alpha001=cvar,logistic_pof_tau005=float(np.mean(1/(1+np.exp(r/0.05)))))

def empty_metric():
    fields=metric(np.zeros((1,1,1)),np.zeros((1,1)),np.array([8]),3,np.ones((1,1),bool))
    return {k:"" for k in fields}

def resource_estimate(root,completed):
    resources=[]
    for path in sorted((root/"resources").glob("*.txt")):
        t=path.read_text()
        def value(label):
            m=re.search(re.escape(label)+r":\s*([^\n]+)",t)
            return m.group(1).strip() if m else None
        def num(label):
            v=value(label); return float(v) if v else None
        member=int(path.stem.split("_")[-1])
        wall=value("Elapsed (wall clock) time (h:mm:ss or m:ss)")
        seconds=0
        if wall:
            for part in wall.split(":"): seconds=60*seconds+float(part)
        resources.append(dict(file=str(path),member=member,user_seconds=num("User time (seconds)"),
            system_seconds=num("System time (seconds)"),elapsed_seconds=seconds or None,
            maximum_rss_kib=num("Maximum resident set size (kbytes)"),exit_status=num("Exit status")))
    good=[x for x in resources if x["member"] in completed and x["exit_status"]==0 and x["elapsed_seconds"]]
    estimate={"task_measurements":resources,"basis":"completed pilot measurements required, including Julia startup; 128 ensemble positions, duplicates retained"}
    if len(good)==3:
        wall=max(x["elapsed_seconds"] for x in good)
        cpu=np.mean([x["user_seconds"]+x["system_seconds"] for x in good])
        rss=max(x["maximum_rss_kib"] for x in good)*1024
        sizes=[sum(p.stat().st_size for p in (root/"members"/f"{m:03}").rglob("*") if p.is_file()) for m in completed]
        minutes=max(10,int(math.ceil(2*wall/60/5)*5))
        estimate.update(estimated_cpu_hours_all128=float(cpu*128/3600),
            measured_max_wall_seconds=wall,measured_max_rss_gib=rss/2**30,
            recommended_wall_minutes_per_member=minutes,recommended_cpus_per_member=4,
            recommended_memory_gib_per_member=max(8,math.ceil(1.5*rss/2**30/4)*4),
            estimated_member_outputs_gib_all128=max(sizes)*128/2**30,
            requested_allocation_core_hours_remaining125=125*4*minutes/60,
            recommended_concurrency=4,
            estimated_wall_hours_remaining125_at_concurrency4=math.ceil(125/4)*wall/3600,
            full_batch_status="AWAITING USER APPROVAL; not submitted")
    else:
        estimate["full_batch_status"]="No reliable complete-pilot estimate; do not launch full campaign"
    return estimate

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("root",type=Path); ap.add_argument("out",type=Path); ap.add_argument("plots",type=Path)
    a=ap.parse_args(); a.out.mkdir(parents=True,exist_ok=False); a.plots.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((a.root/"provenance_manifest.json").read_text())
    # Scheduler failures (including killed processes with no Python/Julia exception)
    # are failures, never unrun members. Preserve the scheduler evidence verbatim.
    jobstates={}
    receipts=sorted((a.root/"submissions").glob("*.json"))
    jobids=[str(json.loads(p.read_text())["job_id"]) for p in receipts]
    if jobids:
        cp=subprocess.run(["sacct","-j",",".join(jobids),"--format=JobID,State,ElapsedRaw,AllocCPUS,TotalCPU,MaxRSS,ExitCode","-P"],text=True,capture_output=True)
        (a.out/"slurm_accounting.psv").write_text(cp.stdout)
        (a.out/"slurm_accounting_stderr.txt").write_text(cp.stderr)
        for line in csv.DictReader(cp.stdout.splitlines(),delimiter="|"):
            match=re.fullmatch(r"\d+_(\d+)",line["JobID"])
            if match: jobstates[int(match.group(1))]=line["State"]
    members=list(csv.DictReader((a.root/"members.csv").open()))
    rows=[]; series=[]; initial=[]; statuses=[]; completed=[]; checks=[]; hashes={}; partial=[]; runtimes=[]
    for entry in members:
        m=int(entry["member"]); idx=int(entry["realization_id"]); folder=a.root/"members"/f"{m:03}"
        pieces=[]; times=[]; valid=True; errors=[]; p0=None; masks={}
        rates=[]; sat=[]; density=[]
        if (folder/"initial.jld2").is_file():
            with h5py.File(folder/"initial.jld2") as f:
                p0=f["p0_pa"][:]; phi=f["porosity"][:]
                assert p0.shape==(256,512)
                masks={"all_cells":np.ones_like(p0,bool),"nonpadding":phi!=1e8,"modified_porosity_padding":phi==1e8}
                s0=f["initial_co2_saturation"][:]
                expected=np.broadcast_to(np.arange(1,257)[:,None]*6.25*1000*10,p0.shape)
                valid=bool(np.array_equal(p0,expected) and np.all(s0==0))
                for delta in LIMITS:
                    initial.append(dict(member=m,realization_id=idx,limit_mpa=delta,initial_time_days=0,
                        formula_max_abs_error_pa=float(np.max(np.abs(p0-expected))),co2_saturation_max=float(s0.max()),
                        initial_max_excess_pa=-delta*1e6,initial_exceeding_cells=0,initial_excluded_from_pof_denominator=True,
                        initial_pressure_min_pa=float(p0.min()),initial_pressure_max_pa=float(p0.max())))
            for block in range(1,13):
                path=folder/f"block_{block:02}.jld2"
                if not path.exists(): break
                try:
                    with h5py.File(path) as f:
                        P=f["pressure_pa"][:]; t=f["time_days"][:]
                        assert bool(f["complete_block"][()])
                        assert P.shape==(10,256,512) and np.all(np.isfinite(P))
                        assert np.array_equal(t,(block-1)*80+np.arange(1,11)*8)
                        mass=f["actual_mass_rate_kg_s"][:]
                        sx=f["co2_saturation_max"][:]; sn=f["co2_saturation_min"][:]
                        assert np.all(mass==0) and np.all(sx==0) and np.all(sn==0)
                        rates.extend(mass); sat.extend(sx)
                        density.append((float(f["brine_density_min_kg_m3"][:].min()),float(f["brine_density_max_kg_m3"][:].max())))
                        runtimes.append(dict(member=m,realization_id=idx,block=block,available_block_days=len(t)*8,
                            block_solver_seconds=float(f["elapsed_seconds"][()])))
                        pieces.append(P); times.extend(t)
                except Exception as ex:
                    errors.append(f"{path}: {type(ex).__name__}: {ex}"); break
        failures=sorted(str(p) for p in folder.glob("failure_*.txt"))
        nt=len(times)
        jobstate=jobstates.get(m,"")
        active=jobstate in ("RUNNING","PENDING","COMPLETING","CONFIGURING","REQUEUED")
        scheduler_failure=bool(jobstate and not active and jobstate!="COMPLETED")
        def member_state(done):
            if done: return "completed"
            if active: return "partial_or_running"
            if failures or errors or scheduler_failure or (jobstate=="COMPLETED" and nt<120): return "failed"
            return "partial_or_running" if nt else "missing"
        statuses.append(dict(member=m,realization_id=idx,pilot=entry["pilot"],saved_outputs=nt,
            complete_480=bool(nt>=60 and valid),complete_960=bool(nt>=120 and valid),
            status=member_state(nt==120 and valid),scheduler_state=jobstate,
            retained_failure_logs=";".join(failures),validation_errors=";".join(errors)))
        if nt==120 and valid: completed.append(m)
        if pieces:
            P=np.concatenate(pieces); ts=np.asarray(times)
            checks.append(dict(member=m,realization_id=idx,max_abs_surface_mass_rate_kg_s=float(np.max(np.abs(rates))),
                max_co2_saturation=float(max(sat)),brine_density_min_kg_m3=min(d[0] for d in density),brine_density_max_kg_m3=max(d[1] for d in density)))
            for domain,mask in masks.items():
                if nt<120:
                    for delta in LIMITS:
                        pr=dict(member=m,realization_id=idx,available_window_days=int(ts[-1]),limit_mpa=delta,
                            domain=domain,scope="partial trajectory only; not a completed 480/960-day result")
                        pr.update(metric(P,p0,ts,delta,mask)); partial.append(pr)
                for k,t in enumerate(ts):
                    pp=P[k][mask]; dp=(P[k]-p0)[mask]
                    series.append(dict(member=m,realization_id=idx,domain=domain,time_days=float(t),
                        pressure_min_pa=float(pp.min()),pressure_max_pa=float(pp.max()),
                        overpressure_min_pa=float(dp.min()),overpressure_max_pa=float(dp.max())))
            for path in [folder/"initial.jld2",*sorted(folder.glob("block_*.jld2"))]:
                h=hashlib.sha256()
                with path.open("rb") as f:
                    for b in iter(lambda:f.read(8*1024*1024),b""): h.update(b)
                hashes[str(path)]=h.hexdigest()
        for window in WINDOWS:
            done=nt>=window//8 and valid
            state=member_state(done)
            for delta in LIMITS:
                for domain in ("all_cells","nonpadding","modified_porosity_padding"):
                    r=dict(member=m,realization_id=idx,window_days=window,limit_mpa=delta,domain=domain,
                        status=state,available_outputs=nt,expected_outputs=window//8)
                    r.update(metric(P[:window//8],p0,ts[:window//8],delta,masks[domain]) if done else empty_metric())
                    rows.append(r)
    aggregate=[]
    for window in WINDOWS:
        for delta in LIMITS:
            for domain in ("all_cells","nonpadding","modified_porosity_padding"):
                selected=[r for r in rows if r["window_days"]==window and r["limit_mpa"]==delta and r["domain"]==domain]
                done=[r for r in selected if r["status"]=="completed"]
                failing=sum(r["any_exceedance_exact"] for r in done)
                aggregate.append(dict(window_days=window,limit_mpa=delta,domain=domain,total_members=128,
                    completed_members=len(done),passing_members=len(done)-failing,exceeding_members=failing,
                    failed_members=sum(r["status"]=="failed" for r in selected),
                    missing_members=sum(r["status"]=="missing" for r in selected),
                    partial_or_running_members=sum(r["status"]=="partial_or_running" for r in selected),
                    ensemble_fraction_exceeding=failing/len(done) if done else "",
                    worst_member_overpressure_pa=max((r["max_overpressure_pa"] for r in done),default=""),
                    worst_member_cell_time_pof=max((r["exact_cell_time_pof"] for r in done),default="")))
    write_csv(a.out/"per_member.csv",rows); write_csv(a.out/"aggregate.csv",aggregate)
    write_csv(a.out/"member_status.csv",statuses); write_csv(a.out/"initial_consistency.csv",initial)
    write_csv(a.out/"pressure_timeseries.csv",series); write_csv(a.out/"zero_control_checks.csv",checks)
    write_csv(a.out/"partial_trajectory_diagnostics.csv",partial); write_csv(a.out/"block_runtime.csv",runtimes)
    estimate=resource_estimate(a.root,completed)
    (a.out/"resource_estimate.json").write_text(json.dumps(estimate,indent=2)+"\n")
    (a.out/"trajectory_hashes.json").write_text(json.dumps(hashes,indent=2)+"\n")
    plt.rcParams.update({"font.size":13,"axes.labelsize":14,"axes.titlesize":15,"savefig.dpi":180})
    fig,ax=plt.subplots(1,2,figsize=(14,4.8),layout="constrained")
    plotted=sorted({r["member"] for r in series})
    for m in plotted:
        ss=[r for r in series if r["member"]==m and r["domain"]=="all_cells"]
        t=[r["time_days"] for r in ss]
        label=f"Member {m}"+(" (partial)" if m not in completed else "")
        line,=ax[0].plot(t,[r["pressure_max_pa"]/1e6 for r in ss],label=label)
        ax[0].plot(t,[r["pressure_min_pa"]/1e6 for r in ss],ls=":",color=line.get_color())
        ax[1].plot(t,[r["overpressure_max_pa"]/1e6 for r in ss],label=label)
    for delta in LIMITS: ax[1].axhline(delta,color="0.4",ls="--",lw=0.8); ax[1].text(970,delta,f"{delta} MPa",ha="left",va="center",fontsize=11)
    ax[0].set(title="Absolute pressure extrema (solid max, dotted min)",ylabel="Pressure (MPa)")
    ax[1].set(title="Maximum cell overpressure",ylabel=r"$\max_{x,z}(p-p_0)$ (MPa)",xlim=(0,1090))
    for axis in ax:
        axis.set_xlabel("Days since zero-injection baseline start"); axis.grid(alpha=.25)
        axis.axvline(480,color="0.4",ls=":",lw=1)
        if plotted: axis.legend(fontsize=11)
        else:
            title=axis.get_title()
            axis.clear()
            axis.set_title(title)
            axis.set_axis_off()
            status_note=f"{sum(s['status']=='failed' for s in statuses)} failed; {sum(s['status']=='missing' for s in statuses)} missing/unrun members"
            axis.text(.5,.5,"No saved pressure trajectories\n"+status_note,
                transform=axis.transAxes,ha="center",va="center",fontsize=12)
    fig.suptitle(f"First-monitoring-step ensemble • new all-brine, disabled-well pilot • {len(completed)}/128 completed")
    fig.savefig(a.plots/"pressure_over_time.png"); plt.close(fig)
    primary=[r for r in rows if r["status"]=="completed" and r["limit_mpa"]==3 and r["domain"]=="all_cells"]
    fig,axes=plt.subplots(1,2,figsize=(12,4.6),layout="constrained")
    for axis,window in zip(axes,WINDOWS):
        rr=[r for r in primary if r["window_days"]==window]
        axis.bar([str(r["member"]) for r in rr],[r["max_overpressure_mpa"] for r in rr])
        axis.set(title=f"0–{window} days; {len(rr)} completed",xlabel="Ensemble member",ylabel="Maximum overpressure (MPa)")
        if not rr:
            axis.set_axis_off()
            axis.text(.5,.5,"No completed trajectories for this window\nPressure pass/fail cannot be assessed",
                transform=axis.transAxes,ha="center",va="center",fontsize=12)
        axis.grid(axis="y",alpha=.25)
    fig.suptitle("Overpressure summary • all production reservoir cells, including padding")
    fig.savefig(a.plots/"overpressure_summary.png"); plt.close(fig)
    lines=["# Prospective zero-injection pressure-limit audit — 9 September 2026","",
        "This is a new all-brine, zero-surface-injection consistency test, not a reconstruction of the historical manual checks. Their numerical records, initial saturation and duration remain unavailable. No result establishes that 4 MPa is optimal, physically calibrated, or the historical reason for that choice.","",
        f"Three pilot positions were fixed before outcomes: 1, 64, 128 (BroadK IDs 741, 180, 1542). The original 128 positions contain 125 distinct IDs; repetitions are retained. Completed 960-day members: {len(completed)}/128. The full batch has not been launched.","",
        "| Window (days) | Limit (MPa above p0) | Completed | Pass | Exceed | Failed | Missing | Partial/running |",
        "|---|---|---|---|---|---|---|---|"]
    for r in aggregate:
        if r["domain"]=="all_cells": lines.append("| "+" | ".join(str(r[k]) for k in ("window_days","limit_mpa","completed_members","passing_members","exceeding_members","failed_members","missing_members","partial_or_running_members"))+" |")
    lines += ["","## Definitions and reproducibility","",
        "Each member is checked before any ensemble summary. Limits 3, 4 and 5 MPa are diagnostics on the same Float64 pressure outputs. Initial time is reported separately; denominators use 60 saved outputs through day 480 and 120 through day 960, both at eight-day spacing. The primary domain is all 131072 reservoir cells, including production padding. Production uses dx×1×dz×dt weights, normalized to unity: equal weights here despite the 100 m model thickness and large padding porosity. No pore-volume weighting or interior-only substitution is used. Padding and nonpadding summaries are secondary; manuscript mask wording is not independently available.","",
        "Raw p−p0 overpressure is independent of the limit. Minimum pressure margin equals Δ−max(p−p0), and maximum pressure excess is its negative; these are mathematically redundant quantities exported for traceability. Exact PoF is a member's fraction of saved cell-time entries with p>p0+Δ. The fraction of ensemble members with any exceedance is a separate quantity. r=(p0+Δ−p)/(p0+Δ) is recomputed for every limit. Clean CVaR uses α=0.01 and production's fractional last tail weight (no integer ceiling); logistic PoF uses τ=0.05 and is never classified as exact exceedance.","",
        "No nonzero pressure tolerance is justified by production's dimensionless CNV/MB or linear residual tolerances. The stated comparison tolerance is 0 Pa; separately exported adjusted flags therefore equal exact flags. No claim of a solver pressure-error bound is made. No bootstrap or optimization was performed.","",
        "The zero schedule and native TotalRateTarget(0) constructors are checked explicitly. Native active InjectorControl imposes a positive mass-rate floor, so the tested control is explicitly DisabledControl. It disconnects surface flow, while well/reservoir internal crossflow remains possible. All-brine saturation and exactly zero achieved surface mass rate are checked at every saved output. This is a declared new baseline variant, not evidence that the unchanged active-injector production route achieves exact zero.","",
        "The simulator retains production grid, porosity padding, anisotropy, PVT, eight-day outputs, 80-day call boundaries and solver defaults. The lower-level equivalent of the production wrapper is used to retain nonlinear reports and restart states. Limits never enter the simulator; there is no threshold-triggered stopping. Failures and incomplete blocks remain in their logs, rather than becoming zero observations.","",
        "## Baseline balance investigation","",
        "Production initializes p0=1000×10×iz×6.25 Pa without atmospheric offset, in the simulator's absolute-pressure numerical convention. Initial pressures range from 62500 to 16000000 Pa. Initialization and the limit reference agree exactly, but geometry uses cell centers and gravitational potential uses g=9.80665. Pressure-dependent brine density follows a compressibility of 1e−11 Pa−1 about 15 MPa. Consequently this linear initialization is not an exact discrete hydrostatic equilibrium. The default reservoir pressure variable has a 101325 Pa minimum, above the initial top-row pressure. These inherited discrepancies must be considered before interpreting baseline pressure drift. External faces have no prescribed flux; the x-side/bottom high-storage cells are retained. Disabled wells can still exchange brine with reservoir cells.","",
        "Actual pressures, saturation/rate checks, raw nonlinear reports and configuration snapshots are retained. Further tighter-tolerance or finer-time comparisons, if necessary, must use separate output directories and shared settings across all limits. Such tests have not been silently substituted for this pilot.","",
        "## Allocation and scope","", "```json",json.dumps(estimate,indent=2),"```","",
        "Full 128-member execution requires approval of the estimated allocation; the resumable bounded script skips complete members and complete blocks. Failed attempts remain visible. Existing historical optimization runs, selected schedules, figures and BHP audit are preserved.","",
        "A separate post-hoc threshold sensitivity analysis could evaluate unchanged saved injection trajectories with a prespecified criterion (per-member/window any exceedance, exact cell-time PoF and clean CVaR at all three limits). It would not be reoptimization. Fresh matched optimizations need a separate scope and compute budget. The focused epsilon-zero/q1,start implementation audit remains deferred."]
    if primary:
        lo=min(r["max_overpressure_mpa"] for r in primary); hi=max(r["max_overpressure_mpa"] for r in primary)
        lines += ["",f"Observed completed-member maximum overpressure range across reported windows: {lo:.9g}–{hi:.9g} MPa."]
        observed=[r for r in aggregate if r["domain"]=="all_cells" and r["completed_members"]>0]
        allpass=all(r["exceeding_members"]==0 for r in observed)
        if allpass:
            counts="; ".join(f"{r['completed_members']} completed members through {r['window_days']} days"
                for r in observed if r["limit_mpa"]==3)
            lines += ["",f"All three limits pass for the completed windows ({counts}). This test does not distinguish 3, 4 and 5 MPa over those completed trajectories. Missing or incomplete windows have no pass/fail conclusion. Numerical balance and convergence must be reviewed before manuscript use."]
        else:
            lines += ["","At least one completed trajectory exceeds a tested limit. Report the table directly; investigate baseline imbalance before interpreting a larger pressure margin as a remedy. No favorable threshold-selection paragraph is supplied."]
    else: lines += ["","No completed reproducible trajectory findings are available; no manuscript-ready experimental conclusion is supplied."]
    (a.out/"report.md").write_text("\n".join(lines)+"\n")
    (a.out/"summary_manifest.json").write_text(json.dumps(dict(created_utc=datetime.now(timezone.utc).isoformat(),
        protocol_manifest=str(a.root/"provenance_manifest.json"),plots=str(a.plots),completed_members=completed,
        analysis_script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()),indent=2)+"\n")
    print(json.dumps({"completed_members":completed,"out":str(a.out),"resource_estimate":estimate},indent=2))

if __name__=="__main__": main()
