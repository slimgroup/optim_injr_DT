#!/usr/bin/env python3
"""Read-only input audit for slide p1-perm-movie; never runs a simulator.

Writes a new audit directory, refusing to replace an existing one. Historical
files are opened read-only with locking disabled (PACE HDF5 read-lock stalls).
Seed amplitudes must be generated with Julia 1.11.3's Random implementation,
not with NumPy's different random-number generator. See the audit README.
"""

import argparse
import csv
import hashlib
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
CASE = "POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
RATES = np.array([0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530])
CACHE = ROOT / "data/diagnostics/zero_pressure_2026-09-09"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def array_sha(a):
    """Numeric hash: little endian, z,x C order = Julia x,z column major."""
    return sha(np.asarray(a, dtype="<f8").tobytes(order="C"))


def write_json(path, value):
    with path.open("x") as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write("\n")


def write_csv(path, rows):
    with path.open("x", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def blob(value, well_z):
    a = np.zeros((256, 512), dtype="<f8")
    for offset, lo, hi in [(-4, 249, 251), (-3, 248, 252), (-2, 247, 253),
                           (-1, 246, 254), (0, 246, 254), (1, 246, 254),
                           (2, 247, 253), (3, 248, 252), (4, 249, 251)]:
        a[well_z + offset - 1, lo - 1:hi] = value
    return a


def file_metadata(path):
    result = {"path": str(path.relative_to(ROOT)), "size_bytes": path.stat().st_size}
    with h5py.File(path, "r", locking=False) as f:
        result["datasets"] = {
            k: {"hdf5_shape": list(f[k].shape), "dtype": str(f[k].dtype)}
            for k in f if not k.startswith("_") and isinstance(f[k], h5py.Dataset)
        }
        result["small_values"] = {}
        for k in result["datasets"]:
            d = f[k]
            if d.size <= 240 and d.dtype.kind in "iuf":
                v = d[()].tolist()
                # Some historical first-exceedance dates are NaN when absent.
                if np.all(np.isfinite(d[()])):
                    result["small_values"][k] = v
            elif d.shape == () and d.dtype.kind in "OS":
                value = d[()]
                if isinstance(value, bytes):
                    result["small_values"][k] = value.decode()
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seed-amplitudes", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    amplitudes = dict((int(m), float(v)) for m, v in csv.reader(args.seed_amplitudes.open()))
    assert set(amplitudes) == set(range(1, 129))
    (args.output / "julia_seed_amplitudes.csv").write_bytes(args.seed_amplitudes.read_bytes())
    idx_paths = [ROOT / f"data/state/{kind}/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2"
                 for kind in ("new", "old")]
    ids = []
    for path in idx_paths:
        with h5py.File(path, "r", locking=False) as f:
            ids.append(f["idx_t1"][:].astype(int))
    assert len(ids[0]) == 128 and np.array_equal(*ids)
    ids = ids[0]
    multiplicities = Counter(ids.tolist())
    cached_rows = {int(r["member"]): r for r in csv.DictReader((CACHE / "members.csv").open())}
    # These binaries contain permeability only. The zero-injection states and
    # trajectories in the same diagnostics directory are NOT used for the movie.
    fields, k_hashes, well_depths = [], [], []
    for m, idx in enumerate(ids, 1):
        raw = (CACHE / "inputs" / f"member_{m:03}.bin").read_bytes()
        assert sha(raw) == cached_rows[m]["permeability_sha256"]
        assert int(cached_rows[m]["realization_id"]) == idx
        k = np.frombuffer(raw, dtype="<f4").reshape(256, 512)
        fields.append(k)
        k_hashes.append(sha(raw))
        well_depths.append(191 + int(np.argmax(k[190:200, 249])))
    p0 = np.broadcast_to(np.arange(1, 257, dtype=float)[:, None] * 62500, (256, 512)).copy()
    pmax = p0 + 4e6
    porosity = np.full((256, 512), 0.25)
    porosity[:, [0, -1]] = 1e8
    porosity[0, :] = 0.25
    porosity[-1, :] = 1e8
    proposed_s0 = blob(amplitudes[1], well_depths[0])
    selected = (np.rint(np.linspace(1, 128, 32)).astype(int)).tolist()
    pilot = [selected[0], selected[15], selected[-1]]
    rows = []
    for m, idx in enumerate(ids, 1):
        final = ROOT / "data/DT_control/exp_name=step1" / CASE / f"sample={m}/final.jld2"
        stamp, has_fields, q6 = "", False, None
        if final.exists():
            with h5py.File(final, "r", locking=False) as f:
                stamp = f["gitcommit"][()].decode() if "gitcommit" in f else "unrecorded"
                has_fields = any("pres" in k.lower() or "sat" in k.lower() for k in f)
                endpoints = np.asarray(f["inj_rate_arr"][()]).ravel()
                last = endpoints[np.flatnonzero(endpoints)[-1]]
                q6 = float(np.linspace(0.0001, last, 12)[5])
        historical_s0 = blob(amplitudes[m], well_depths[m - 1])
        rows.append({
            "ensemble_position": m, "permeability_realization_id": int(idx),
            "multiplicity": multiplicities[int(idx)], "permeability_sha256_f32": k_hashes[m - 1],
            "permeability_source": str((CACHE / "inputs" / f"member_{m:03}.bin").relative_to(ROOT)),
            "selected_talk_subset": m in selected, "selected_pilot": m in pilot,
            "target_day": 480, "schedule_source": "docs/injection_rate_arrays.md, Step 1 Case 2",
            "target_rates_m3_s": json.dumps(RATES.tolist()),
            "historical_optimization_final": str(final.relative_to(ROOT)) if final.exists() else "",
            "historical_gitcommit": stamp, "historical_final_has_pressure_or_saturation": has_fields,
            "historical_optimized_schedule_element_6_of_12_m3_s": q6,
            "historical_seed": 2024 + m, "reconstructed_historical_s0_value": amplitudes[m],
            "reconstructed_historical_well_z_index": well_depths[m - 1],
            "reconstructed_historical_s0_sha256_f64": array_sha(historical_s0),
            "historical_initial_state_saved_hash": "not available in final.jld2",
            "proposed_common_p0_sha256_f64": array_sha(p0),
            "proposed_common_s0_sha256_f64": array_sha(proposed_s0),
            "proposed_common_well_z_index": well_depths[0],
            "pressure_day480_source": "MISSING", "saturation_day480_source": "MISSING",
            "pressure_units": "Pa stored; MPa displayed", "saturation_units": "dimensionless",
            "permeability_units": "mD displayed; m2 in solver",
            "color_limits": "K: common positive log limits; p: global extrema after approved runs; S: [0,1]",
            "status": "missing_matched_forward; no new run submitted",
        })
    write_csv(args.output / "members.csv", rows)
    forwards = [file_metadata(p) for p in sorted((ROOT / "plots/paper_figures").glob("*.jld2"))]
    states = [file_metadata(p) for p in idx_paths]
    base = ROOT / "plots/paper_figures/forward_sim_four_steps_base_data.jld2"
    movie = ROOT / "plots/paper_figures/full_campaign_video_POF_eps001.jld2"
    with h5py.File(base, "r", locking=False) as f:
        assert np.array_equal(f["POF_eps0p01_rates"][:6], RATES)
        assert int(f["ground_truth_idx"][()]) == 2000
        assert int(f["POF_eps0p01_snap_idx"][5]) == 60
        assert float(f["period_days"][()]) == 80
        bp, bs = f["POF_eps0p01_pres_snaps"][5], f["POF_eps0p01_sat_snaps"][5]
        assert np.array_equal(f["p0"][:].T, p0)
        assert np.array_equal(f["p_max"][:], pmax)
    with h5py.File(movie, "r", locking=False) as f:
        assert np.array_equal(f["rate_by_substep"][:60], np.repeat(RATES, 10))
        assert float(f["dt_days"][()]) * 60 == 480
        mp, ms = f["pres_all"][59], f["sat_all"][59]
    truth = {
        "realization_id": 2000, "in_requested_ensemble": False, "day": 480,
        "base_source": str(base.relative_to(ROOT)), "base_pressure_dataset": "POF_eps0p01_pres_snaps",
        "base_saturation_dataset": "POF_eps0p01_sat_snaps", "base_python_snapshot_index": 5,
        "video_source": str(movie.relative_to(ROOT)), "video_python_snapshot_index": 59,
        "initial_saturation_from_generator": "0.5 blob at z index 192; differs from seeded step-1 states",
        "initial_state_stored_in_forward_exports": False,
        "base_pressure_sha256_f64": array_sha(bp), "base_saturation_sha256_f64": array_sha(bs),
        "base_pressure_mpa_range": [float(bp.min()/1e6), float(bp.max()/1e6)],
        "base_saturation_range": [float(bs.min()), float(bs.max())],
        "base_pressure_limit_exceedance_cells": int(np.count_nonzero(bp > pmax)),
        "two_exports_max_pressure_difference_pa": float(np.max(np.abs(bp-mp))),
        "two_exports_max_saturation_difference": float(np.max(np.abs(bs-ms))),
        "reuse_for_movie": False,
    }
    files = []
    for root in ("data", "plots", "archive"):
        files.extend(str(p.relative_to(ROOT)) for p in (ROOT / root).rglob("*.jld2"))
    (args.output / "historical_jld2_paths.txt").write_text("\n".join(sorted(files)) + "\n")
    scratch = Path.home() / "scratch/optim_injr_DT"
    scratch_files = sorted(str(p) for p in scratch.rglob("*.jld2"))
    (args.output / "scratch_jld2_paths.txt").write_text("\n".join(scratch_files))
    prior_manifest = json.loads((CACHE / "provenance_manifest.json").read_text())
    source_paths = [ROOT / "src/optim_inject.jl", ROOT / "src/optim_prior_state.jl",
                    ROOT / "docs/injection_rate_arrays.md", ROOT / "Manifest.toml", Path(__file__),
                    ROOT / "scripts/julia_scripts/data_collection/forward_exports/run_forward_four_steps_base_export.jl",
                    ROOT / "scripts/julia_scripts/data_collection/forward_exports/run_full_campaign_video_cases.jl"]
    rules = Path.home() / "julia-depot/packages/JutulDarcyRules/2hBBA/src/FlowRules/Types"
    source_paths.extend(rules / p for p in ("jutulModel.jl", "jutulState.jl", "type_utils.jl"))
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(), "slide_id": "p1-perm-movie",
        "repo_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "status": "APPROVAL REQUIRED FOR ADDITIONAL FORWARDS; no MP4 or poster produced",
        "historical_jld2_counts": dict(Counter(p.split('/')[0] for p in files)),
        "scratch_jld2_count": len(scratch_files), "ensemble_members": 128,
        "unique_realization_ids": len(multiplicities), "old_new_indices_equal": True,
        "duplicate_positions": {str(k): (np.flatnonzero(ids == k)+1).tolist()
                                for k, count in multiplicities.items() if count > 1},
        "matched_ensemble_forward_count": 0,
        "historical_final_count": sum(bool(r["historical_optimization_final"]) for r in rows),
        "historical_finals_with_pressure_or_saturation_keys": sum(r["historical_final_has_pressure_or_saturation"] for r in rows),
        "historical_initial_s0_unique_reconstructed_hashes": len(set(r["reconstructed_historical_s0_sha256_f64"] for r in rows)),
        "historical_well_z_indices": sorted(set(well_depths)),
        "historical_optimization_commits": dict(Counter(r["historical_gitcommit"] for r in rows)),
        "truth_day480_audit": truth, "state_metadata": states, "forward_export_metadata": forwards,
        "permeability_cache": {"source": str(CACHE.relative_to(ROOT)), "all_128_binary_hashes_rechecked": True,
            "original_BroadK_file_hash_recorded_20260909_not_recomputed": prior_manifest["input_and_source_sha256"][str(ROOT / 'data/geo/wise_perm_models_2000_new.jld2')],
            "caveat": "Cache identity verified against previous export hashes and current index arrays; original 2GB file not rehashed in this lightweight audit."},
        "current_source_hashes": {str(p): sha(p.read_bytes()) for p in source_paths},
    }
    write_json(args.output / "audit.json", manifest)
    protocol = {
        "approval_status": "PROPOSED ONLY; do not submit without user approval",
        "purpose": "Fixed physical time; permeability-only forward comparison, not posterior-state uncertainty",
        "state_choice_requiring_approval": "Freeze reconstructed first-step ensemble position 1 state and well for every member. This is a new controlled experiment; it is not the original randomized-state ensemble.",
        "initial_seed": 2025, "initial_saturation_blob_value": amplitudes[1],
        "initial_saturation_sha256_f64": array_sha(proposed_s0),
        "initial_pressure_sha256_f64": array_sha(p0), "p_max_sha256_f64": array_sha(pmax),
        "porosity_sha256_f64": array_sha(porosity),
        "hash_encoding": "Float64 little endian, z,x C order = Julia x,z column major",
        "well_grid_indices_julia": [250, 1, well_depths[0]],
        "well_nominal_start_xyz_m": [1562.5, 100, well_depths[0]*6.25],
        "well_nominal_end_z_m": (well_depths[0]+6)*6.25,
        "grid": [512, 1, 256], "cell_size_m": [6.25, 100, 6.25], "extent_x_z_m": [0, 3200, 0, 1600],
        "depth_positive_down": True, "interior_porosity": 0.25,
        "boundary_setup": prior_manifest["new_baseline"]["padding"],
        "external_boundaries": prior_manifest["new_baseline"]["external_boundaries"],
        "rho_co2_brine_kg_m3": [700, 1000], "mu_co2_brine_pa_s": [1e-4, 1e-3],
        "compressibility_per_pa": [1e-9, 1e-11], "pvt_reference_pa": 15e6,
        "relative_permeability": "BrooksCorey: exponent [2,2], residual [0.1,0.1], endpoint 1",
        "kv_over_kh": 0.36, "mD_to_m2": 9.86923266716013e-16,
        "initial_pressure_pa": "1000*10*(iz*6.25), iz=1:256, h=0; retain inherited initialization",
        "solver_gravity_m_s2": 9.80665,
        "schedule_source": "docs/injection_rate_arrays.md, historical Step-1 Case 2, also saved base forward export",
        "rates_m3_s": RATES.tolist(), "period_days": 80, "rate_multiplier": 1,
        "comparison_day": 480, "requested_output_interval_days": 8,
        "movie_uses_only_final_output": True,
        "pressure_limit": "Evaluate p_res[z,x] > p0[z,x]+4e6 for each cell in Pa",
        "pressure_limit_label": "Pressure-limit exceedance",
        "subset_rule": "rint(linspace(1,128,32)); positions selected before viewing new forward outcomes",
        "subset_positions": selected, "subset_realization_ids": ids[np.array(selected)-1].tolist(),
        "subset_unique_ids": len(set(ids[np.array(selected)-1].tolist())),
        "pilot_positions": pilot, "pilot_ids": ids[np.array(pilot)-1].tolist(),
        "subset_video_seconds": 24, "seconds_per_member": 0.75,
        "full_video_seconds": 96, "full_video_members": 128, "full_video_unique_ids": 125,
        "duplicate_reuse": "Reuse identical completed forward only if K and all fixed-input hashes agree; retain repeated ensemble positions explicitly in the movie provenance.",
        "export": {"resolution": [1920,1080], "format": "MP4", "codec": "H.264", "pixel_format": "yuv420p", "fps": 24,
                   "frames_per_member": 18, "poster_format": "PNG", "interpolation_between_members": False},
        "color_limits": {"permeability_mD": "Fixed positive log limits covering approved selected ensemble, determined before rendering",
                         "pressure_MPa": "Fixed global min/max over all completed approved members, determined after forwards",
                         "co2_saturation": [0,1]},
        "job_budget": {"forward_task_cpus": 4, "forward_task_memory_GiB": 16,
            "forward_task_walltime_hours": 1, "maximum_concurrent_tasks": 4,
            "pilot_tasks": 3, "pilot_allocated_core_hours_cap": 12,
            "talk_32_total_allocated_core_hours_cap_including_pilot": 128,
            "full_125_unique_allocated_core_hours_cap_including_pilot": 500,
            "render_cpus": 2, "render_memory_GiB": 8, "render_wall_minutes": 15,
            "render_allocated_core_hours_cap": 0.5,
            "runtime_evidence": "Ground-truth 1920-day PoF export: Slurm 9820154_0 / 9820157, 26m39s, peak RSS ~3.9GiB; 1920-day replay 12902263_1 / 12902267, 18m02s, ~2.2GiB. Different permeability/state may be much slower. These are allocation caps, not measured ensemble runtimes.",
            "pilot_gate": "Only continue within the approved total budget after all three pilot forwards reach Day 480 with finite fields and identical fixed-input hashes. On timeout/failure stop and report; do not silently extend allocations or replace members.",
            "concurrency_wall_envelope_excluding_queue": "32 members: <=9h with separate pilot gate; 125 unique: <=32h; not a runtime prediction",
            "estimated_endpoint_field_storage": "Float64 p+S: 2MiB/unique member; 64MiB/32, 250MiB/125, excluding inputs/checkpoints/frames"},
        "proposed_caption": "Permeability-driven variability in reservoir pressure and CO2 saturation at Day 480 under the selected PoF epsilon=0.01 injection schedule. Initial pressure and saturation, injection schedule, well geometry and all other model settings are held fixed. Outlines identify cells above the model pressure limit p0(x,z)+4 MPa. 32 positions selected uniformly from the 128-member first-step ensemble; frames compare realizations, not successive times.",
    }
    write_json(args.output / "proposed_protocol.json", protocol)
    print(json.dumps({"output": str(args.output), "members": 128, "unique_ids": len(multiplicities),
                      "missing_matched_members": 128, "subset": selected, "subset_unique_ids": protocol["subset_unique_ids"],
                      "pilot": pilot, "s0": amplitudes[1], "well_z": well_depths[0],
                      "initial_hashes": [array_sha(p0), array_sha(proposed_s0)],
                      "finals_with_fields": manifest["historical_finals_with_pressure_or_saturation_keys"]}, indent=2))


if __name__ == "__main__":
    main()
