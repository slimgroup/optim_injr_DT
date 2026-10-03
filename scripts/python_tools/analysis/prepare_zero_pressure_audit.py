#!/usr/bin/env python3
"""Freeze the first-step ensemble and prospective protocol before simulations."""
import argparse
import csv
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
PILOT = (1, 64, 128)  # Fixed positions, no pressure outcomes used.

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(8*1024*1024), b""):
            h.update(b)
    return h.hexdigest()

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("out",type=Path); a=ap.parse_args()
    a.out.mkdir(parents=True,exist_ok=False)
    (a.out/"inputs").mkdir()
    indices=ROOT/"data/state/new/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2"
    old=ROOT/"data/state/old/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2"
    perm=ROOT/"data/geo/wise_perm_models_2000_new.jld2"
    with h5py.File(indices) as f: ids=f["idx_t1"][:].ravel().astype(int)
    with h5py.File(old) as f: old_ids=f["idx_t1"][:].ravel().astype(int)
    assert len(ids)==128 and np.array_equal(ids,old_ids)
    # Read each contiguous z slab once: ~1 GiB read, 64 MiB retained.
    selected=np.empty((128,256,512),dtype="<f4")
    with h5py.File(perm) as f:
        ds=f["BroadK"]; assert ds.shape==(256,512,2000)
        for z in range(256):
            selected[:,z,:]=ds[z,:,:][:,ids-1].T
    rows=[]
    for m,idx in enumerate(ids,1):
        p=a.out/"inputs"/f"member_{m:03}.bin"
        raw=selected[m-1].tobytes(order="C")
        p.write_bytes(raw)
        rows.append([m,int(idx),int(m in PILOT),int(np.count_nonzero(ids==idx)),hashlib.sha256(raw).hexdigest()])
    with (a.out/"members.csv").open("w") as f:
        w=csv.writer(f); w.writerow(["member","realization_id","pilot","ensemble_multiplicity","permeability_sha256"]); w.writerows(rows)
    paths=[indices,old,perm,ROOT/"Project.toml",ROOT/"Manifest.toml",ROOT/"src/optim_inject.jl",ROOT/"src/optim_prior_state.jl",ROOT/"src/optim_case_config.jl"]
    for pkg in ("Jutul/zUgxK","JutulDarcy/L8Awk","JutulDarcyRules/2hBBA"):
        paths.extend(sorted((Path.home()/"julia-depot/packages"/pkg/"src").rglob("*.jl")))
    paths.extend(sorted((ROOT/"scripts").rglob("*zero*pressure*.*")))
    inventory=json.loads((ROOT/"data/diagnostics/bhp_audit_20260907_12902263/input_inventory.json").read_text())
    protocol={
        "created_utc":datetime.now(timezone.utc).isoformat(), "repo_commit":git("rev-parse","HEAD"),"git_status":git("status","--short"),
        "purpose":"Prospective reproducibility and sensitivity audit, not historical evidence for choosing 4 MPa",
        "historical_manual_saturation":"unknown; no numerical records supplied", "historical_manual_duration_days":None,
        "manual_confirmed_by_user":["hydrostatic initial pressure","no prior CO2 injection","zero injection throughout","first-step 128-member ensemble"],
        "pilot_selection":{"rule":"fixed ensemble positions first, midpoint, last before viewing outcomes","members":list(PILOT),"realization_ids":[int(ids[i-1]) for i in PILOT]},
        "ensemble":{"members":128,"unique_realization_ids":len(set(ids)),"dataset":"BroadK","julia_shape":[2000,512,256],"julia_slice_axes":["x","z"],"mD_to_m2":9.86923266716013e-16,"new_old_idx_t1_identical":True,"truth_index_2000_included":False},
        "input_encoding":"Float32 little endian; Julia (512,256) x,z column-major; h5py (256,512) z,x C order",
        "new_baseline":{"label":"all_brine_disabled_zero","s_co2":0,"s_brine":1,"prior_injection":0,"requested_rate_m3_s":0,"well_control":"DisabledControl; explicitly differs from native zero-target InjectorControl with positive mass-rate floor","n":[512,1,256],"d_m":[6.25,100,6.25],"top_depth_m":0,"interior_porosity":0.25,"kv_kh":0.36,"padding":"production pad=true; x sides and bottom porosity 1e8; top overwritten to 0.25 at h=0; no extra cells","initial_pressure_pa":"1000*10*(iz*6.25), no atmospheric offset","solver_gravity_m_s2":9.80665,"pressure_convention":"production simulator absolute-pressure numerical convention; inherited datum inconsistency retained","rho_co2_brine_kg_m3":[700,1000],"mu_co2_brine_pa_s":[1e-4,1e-3],"pvt_reference_pa":15e6,"compressibility_per_pa":[1e-9,1e-11],"relative_permeability":"BrooksCorey exponents [2,2], residual saturations [0.1,0.1], endpoint 1","external_boundaries":"no prescribed external source or boundary forces; finite-volume closed external faces, high-storage padding retained"},
        "comparison":{"limits_mpa":[3,4,5],"windows_days":[480,960],"output_interval_days":8,"block_days":80,"initial_time_in_denominator":False,"primary_mask":"all 512*256 reservoir cells, including modified-porosity padding","weighting":"production dx*1*dz*dt normalized; every saved cell-time has equal weight; not pore-volume weighting","secondary_domains":["modified_porosity_padding","nonpadding"],"pressure_tolerance_pa":0,"tolerance_reason":"solver CNV/MB/linear residual tolerances are not pressure error bounds; no defensible nonzero Pa tolerance assigned","cvar_alpha":0.01,"cvar_rounding":"production clean weighted tail: exact alpha mass with a fractional final cell; no integer ceiling","logistic_tau":0.05,"threshold_stopping":False,"threshold_used_in_solver":False},
        "solver":{"tol_cnv":1e-3,"tol_mb":1e-7,"tol_cnv_well":1e-2,"tol_mb_well":1e-3,"linear":"CPR/BiCGStab default rtol 1e-3","initial_internal_dt_days":1,"max_timestep_cuts":1000,"internal_time_stepping":"adaptive production defaults; no per-threshold changes"},
        "reuse_decision":"No existing verified all-brine zero-controlled trajectories identified. Production optimization uses seeded nonzero saturation; later posterior forecasts and high-rate no-control/BHP outputs excluded.",
        "historical_optimization_examples":[v for v in inventory["optimization_final_examples"] if v["step"]==1],
        "historical_versions_caveat":"Representative saved commits/manifests, not certification of every historical member; dirty stamps retained",
        "input_and_source_sha256":{str(p):sha(p) for p in paths},
        "full_batch":"NOT APPROVED OR SUBMITTED; estimate after three-member pilot; require user approval; bounded concurrency and wall time",
        "epsilon_zero_audit":"separate task remains deferred; this does not audit q_1,start",
    }
    (a.out/"provenance_manifest.json").write_text(json.dumps(protocol,indent=2)+"\n")
    print(json.dumps({"out":str(a.out),"pilot":protocol["pilot_selection"],"members":128,"unique":len(set(ids))},indent=2))

if __name__=="__main__": main()
