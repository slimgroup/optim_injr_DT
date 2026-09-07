#!/usr/bin/env python3
"""Capture input provenance without modifying experiments (small metadata reads)."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[3]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def plain(v):
    if isinstance(v, bytes):
        return v.decode()
    if isinstance(v, np.ndarray):
        return v.tolist()
    if isinstance(v, np.generic):
        return v.item()
    return str(v)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("outdir", type=Path)
    args = parser.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    dest = args.outdir / "input_inventory.json"
    if dest.exists():
        raise FileExistsError(dest)
    result = {"commit": git("rev-parse", "HEAD"), "git_status": git("status", "--short"),
              "pressure_limit_status": "No calibrated formation or equipment BHP bound found",
              "optimization_final_examples": [], "indices": [], "paper_assets": [], "source_hashes": {}}
    perm = ROOT / "data/geo/wise_perm_models_2000_new.jld2"
    with h5py.File(perm) as f:
        truth = f["BroadK"][:, :, 1999]
        stored_k = f["K"][:]
        # Any differing entry proves unequal fields; fully compare the candidates
        # that agree at a discriminating injector-cell entry.
        candidates = np.flatnonzero(f["BroadK"][191,249,:] == truth[191,249])
        equal_fields = [int(i+1) for i in candidates if np.array_equal(f["BroadK"][:,:,i],truth)]
        result["ground_truth"] = {
            "path": str(perm), "resolved_path": str(perm.resolve()),
            "file_size": perm.stat().st_size, "file_mtime_ns": perm.stat().st_mtime_ns,
            "dataset": "BroadK", "julia_index": 2000, "h5py_index": 1999,
            "h5py_dataset_shape": f["BroadK"].shape, "julia_dataset_shape": list(reversed(f["BroadK"].shape)),
            "h5py_slice_axes": ["z", "x"], "julia_slice_axes": ["x", "z"],
            "dtype": str(truth.dtype), "units": "mD", "mD_to_m2": 9.86923266716013e-16,
            "sha256_float32_le_z_x_C_bytes": hashlib.sha256(truth.tobytes(order="C")).hexdigest(),
            "same_as_stored_K": bool(np.array_equal(truth, stored_k)),
            "max_difference_from_stored_K_mD": float(np.max(np.abs(truth-stored_k))),
            "injector_z_index": int(191+np.argmax(truth[190:200,249])),
            "all_numerically_equal_BroadK_indices": equal_fields,
            "duplicate_check": "Compare (x=250,z=192) for all 2000 arrays, then compare all entries of every candidate",
        }
    for path in sorted((ROOT / "data/state").rglob("*.jld2")):
        with h5py.File(path) as f:
            for key in f:
                if key.startswith("idx_"):
                    idx = f[key][:]
                    result["indices"].append({"path": str(path.relative_to(ROOT)), "key": key,
                        "indices": idx.tolist(), "count": len(idx), "unique": len(np.unique(idx)),
                        "truth_count": int(np.count_nonzero(idx == 2000))})
    for step in range(1, 5):
        for path in sorted((ROOT / f"data/DT_control/exp_name=step{step}").glob("*/sample=1/final.jld2")):
            tag = path.parts[-3]
            if not any(k in tag for k in ("eps=0.0__", "eps=0.01__", "alpha=0.01__gamma=0.1__")):
                continue
            with h5py.File(path) as f:
                record = {"step": step, "path": str(path.relative_to(ROOT)), "keys": list(f)}
                for k in ("gitcommit", "script"):
                    if k in f:
                        record[k] = plain(f[k][()])
                if "gitcommit" in record:
                    revision = record["gitcommit"].removesuffix("-dirty")
                    manifest = git("show", revision + ":Manifest.toml")
                    record["historical_manifest_packages"] = {}
                    for name in ("Jutul", "JutulDarcy", "JutulDarcyRules"):
                        block = re.search(r"\[\[deps\."+name+r"\]\]([\s\S]*?)(?=\n\[\[|\Z)", manifest).group(1)
                        record["historical_manifest_packages"][name] = {
                            k: re.search(k+r' = "([^"]+)"', block).group(1)
                            for k in ("version", "git-tree-sha1")}
                result["optimization_final_examples"].append(record)
    names = ["forward_sim_four_steps_base_data.jld2", "controlled_day728_POF_eps0.jld2",
             "cvar_day728_sensitivity_1p22x.jld2", "no_control_delayed_ramp_10_periods.jld2",
             "pof_eps001_full_campaign_sensitivity_1p65x.jld2", "full_campaign_video_CVaR_g01_a001_sensitivity.jld2"]
    for name in names:
        path = ROOT / "plots/paper_figures" / name
        record = {"path": str(path.relative_to(ROOT)), "sha256": sha(path),
                  "size": path.stat().st_size, "mtime_ns": path.stat().st_mtime_ns, "fields": {}}
        with h5py.File(path) as f:
            for k in f:
                if k.startswith("_") or not isinstance(f[k], h5py.Dataset):
                    continue
                ds = f[k]
                record["fields"][k] = {"shape_h5py": ds.shape, "dtype": str(ds.dtype)}
                if ds.size <= 240 and ds.dtype.kind not in ("V", "O"):
                    record["fields"][k]["value"] = plain(ds[()])
        result["paper_assets"].append(record)
    paths = [ROOT / "Manifest.toml", ROOT / "Project.toml", ROOT / "src/optim_inject.jl",
             ROOT / "src/optim_prior_state.jl", ROOT / "docs/reference/PAPER_FIGURE_MANIFEST.md"]
    paths += list((ROOT / "scripts/julia_scripts/data_collection/forward_exports").glob("*.jl"))
    paths += list((ROOT / "scripts/python_plots").glob("*four_steps*.py"))
    for pkg in ("Jutul", "JutulDarcy", "JutulDarcyRules"):
        paths += list((Path.home() / "julia-depot/packages" / pkg).glob("*/src/**/*.jl"))
    for path in paths:
        result["source_hashes"][str(path)] = sha(path)
    dest.write_text(json.dumps(result, indent=2, allow_nan=True) + "\n")
    print(dest)


if __name__ == "__main__":
    main()
