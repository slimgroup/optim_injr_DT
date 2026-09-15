#!/usr/bin/env python3
"""Audit and render saved, unscaled ground-truth campaigns; never simulate.

The sparse mode uses the intersection of actual saved times. All outputs are
exclusive-create in a new directory. Run via submit_selected_control_movies.sh.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess

os.environ.setdefault("HDF5_USE_FILE_LOCKING", "FALSE")
os.environ.setdefault("MPLCONFIGDIR", "/tmp/mpl_selected_control_movies")
import h5py
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize, TwoSlopeNorm, ListedColormap
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

BASE = Path(__file__).resolve().parents[2]
SOURCES = BASE / "plots/paper_figures"
CASE_KEYS = ["POF_eps0", "POF_eps0p01", "CVaR_g01_a001"]
TITLES = [r"PoF $\varepsilon=0$", r"PoF $\varepsilon=0.01$", r"CVaR $\alpha=0.01,\ \gamma=0.1$"]
STEMS = ["pof_eps0", "pof_eps001", "cvar_alpha001_gamma01"]
EXPECTED_MT = [4.93, 6.95, 10.71]
EXPECTED_PEAK = [0, 8, 2285]
FPS, DURATION = 30, 40
NX, NZ, DX = 512, 256, 6.25
# Preserve the reference figure's axis convention (all 512 x 256 cells shown).
EXTENT = (0, (NX - 1) * DX, (NZ - 1) * DX, 0)


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path, data):
    with path.open("x") as f:
        json.dump(data, f, indent=2, allow_nan=False)
        f.write("\n")


class SavedCampaigns:
    def __init__(self):
        self.files = {}
        self.refs = {key: {} for key in CASE_KEYS}
        self.duplicates = []
        self.base = self.open("forward_sim_four_steps_base_data.jld2")
        self.p0 = self.base["p0"][:].T.astype(float)
        self.pmax = self.base["p_max"][:].astype(float)
        assert self.p0.shape == self.pmax.shape == (NZ, NX)
        np.testing.assert_array_equal(self.pmax, self.p0 + 4e6)
        np.testing.assert_array_equal(self.p0[:, 0], np.arange(1, NZ + 1) * DX * 1000 * 10)
        assert float(self.base["rate_multiplier"][()]) == 1
        self.rates = {key: self.base[key + "_rates"][:].astype(float) for key in CASE_KEYS}
        assert all(len(v) == 24 for v in self.rates.values())
        period = float(self.base["period_days"][()])
        assert period == 80
        for key in [CASE_KEYS[0], CASE_KEYS[2]]:
            first = self.open(f"first_step_substeps_{key}.jld2")
            np.testing.assert_array_equal(first["rates"][:], self.rates[key][:6])
            dt = float(first["dt_days"][()])
            assert dt == 8 and first["pres_all"].shape == first["sat_all"].shape
            for idx in range(first["pres_all"].shape[0]):
                self.refs[key][int((idx + 1) * dt)] = (Path(first.filename).name, "pres_all", "sat_all", idx)
            snap_indices = self.base[key + "_snap_idx"][:]
            assert np.array_equal(snap_indices, np.arange(10, 241, 10))
            for idx, substep in enumerate(snap_indices):
                day = int(substep * period / 10)
                if day in self.refs[key]:
                    p, s = self.fields(key, day)
                    p2, s2 = self.base[key + "_pres_snaps"][idx], self.base[key + "_sat_snaps"][idx]
                    np.testing.assert_array_equal(p, p2)
                    np.testing.assert_array_equal(s, s2)
                    self.duplicates.append({"case": key, "day": day, "pressure_max_abs_difference_Pa": 0, "saturation_max_abs_difference": 0})
                else:
                    self.refs[key][day] = (Path(self.base.filename).name, key + "_pres_snaps", key + "_sat_snaps", idx)
            extra = self.open(f"controlled_day728_{key}.jld2")
            np.testing.assert_array_equal(extra["rates"][:], self.rates[key])
            day = int(extra["day"][()])
            assert day == 728
            self.refs[key][day] = (Path(extra.filename).name, "pres", "sat", None)
        full = self.open("full_campaign_video_POF_eps001.jld2")
        assert float(full["cvar_sensitivity_multiplier"][()]) == 1
        np.testing.assert_array_equal(full["rate_by_substep"][:], np.repeat(self.rates[CASE_KEYS[1]], 10))
        dt = float(full["dt_days"][()])
        assert dt == 8 and full["pres_all"].shape == full["sat_all"].shape
        for idx in range(full["pres_all"].shape[0]):
            self.refs[CASE_KEYS[1]][int((idx + 1) * dt)] = (Path(full.filename).name, "pres_all", "sat_all", idx)
        self.times = sorted(set.intersection(*(set(v) for v in self.refs.values())))
        assert self.times[0] == 8 and self.times[-1] == 1920 and 728 in self.times
        for f in self.files.values():
            assert int(f["ground_truth_idx"][()]) == 2000
            np.testing.assert_array_equal(f["p0"][:].T, self.p0)
            np.testing.assert_array_equal(f["p_max"][:], self.pmax)

    def open(self, name):
        if name not in self.files:
            self.files[name] = h5py.File(SOURCES / name, "r", locking=False)
        return self.files[name]

    def fields(self, key, day):
        name, pk, sk, idx = self.refs[key][day]
        f = self.files[name]
        if idx is None:
            return f[pk][:].astype(float), f[sk][:].astype(float)
        return f[pk][idx].astype(float), f[sk][idx].astype(float)

    def metrics(self, key, day):
        p, s = self.fields(key, day)
        assert p.shape == s.shape == (NZ, NX)
        assert np.isfinite(p).all() and np.isfinite(s).all()
        r = (self.pmax - p) / self.pmax
        dp = (p - self.p0) / 1e6
        # End-of-output convention: rate that produced this saved state.
        period_idx = min(int(np.ceil(day / 80)) - 1, 23)
        durations = np.clip(day - np.arange(24) * 80, 0, 80)
        return {"day": day, "step": int(np.ceil(day / 480)),
                "rate_m3_s": float(self.rates[key][period_idx]),
                "cumulative_Mt": float(np.sum(self.rates[key] * durations) * 86400 * 700 / 1e9),
                "min_r": float(r.min()), "max_r": float(r.max()),
                "exceeding_cells": int(np.count_nonzero(r < 0)),
                "min_dp_MPa": float(dp.min()), "max_dp_MPa": float(dp.max()),
                "min_saturation": float(s.min()), "max_saturation": float(s.max())}

    def audit(self, out):
        all_metrics = {k: [self.metrics(k, d) for d in sorted(self.refs[k])] for k in CASE_KEYS}
        extrema = {}
        for field, low, high in [("margin", "min_r", "max_r"), ("pressure_increase_MPa", "min_dp_MPa", "max_dp_MPa"), ("saturation", "min_saturation", "max_saturation")]:
            values = [m for ms in all_metrics.values() for m in ms]
            extrema[field] = [min(m[low] for m in values), max(m[high] for m in values)]
        margin_max = max(1., np.ceil(max(abs(v) for v in extrema["margin"]) * 10) / 10)
        limits = {"margin": [-margin_max, margin_max],
                  "pressure_increase_MPa": [min(0., np.floor(extrema["pressure_increase_MPa"][0] * 10) / 10), np.ceil(extrema["pressure_increase_MPa"][1] * 10) / 10],
                  "saturation": [min(0., extrema["saturation"][0]), max(1., extrema["saturation"][1])]}
        self.metrics_by_day = {k: {m["day"]: m for m in ms} for k, ms in all_metrics.items()}
        rows = []
        for key, ms in all_metrics.items():
            for m in ms:
                ref = self.refs[key][m["day"]]
                rows.append({"case": key, **m, "in_synchronized_movie": m["day"] in self.times,
                             "source_file": ref[0], "pressure_dataset": ref[1], "saturation_dataset": ref[2], "python_index": ref[3]})
        with (out / "saved_time_validation.csv").open("x", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
        checks = []
        for i, key in enumerate(CASE_KEYS):
            ms = all_metrics[key]
            peak = max(m["exceeding_cells"] for m in ms)
            missing = sorted(set(range(8, 1921, 8)) - set(self.refs[key]))
            checks.append({"case": key, "saved_times": sorted(self.refs[key]), "missing_eight_day_outputs": missing,
                           "saved_output_count": len(ms), "mass_day1920_Mt": ms[-1]["cumulative_Mt"],
                           "manuscript_rounded_mass_Mt": EXPECTED_MT[i], "mass_rounding_matches": round(ms[-1]["cumulative_Mt"], 2) == EXPECTED_MT[i],
                           "peak_cells_over_available_fields": peak, "manuscript_peak_cells": EXPECTED_PEAK[i],
                           "peak_matches": peak == EXPECTED_PEAK[i], "day728": self.metrics_by_day[key][728]})
        # Quantitative day-728 comparison with the actual reference CVaR source.
        with h5py.File(SOURCES / "cvar_day728_sensitivity_1p22x.jld2", "r", locking=False) as f:
            p, s = self.fields(CASE_KEYS[2], 728)
            pref, sref = f["pres"][:], f["sat"][:]
            day728_difference = {"CVaR_reference_source": "cvar_day728_sensitivity_1p22x.jld2",
                "reference_multiplier": 1.22, "max_abs_pressure_difference_Pa": float(np.abs(p - pref).max()),
                "max_abs_saturation_difference": float(np.abs(s - sref).max()),
                "reference_exceeding_cells": int(np.count_nonzero(pref > self.pmax)),
                "movie_exceeding_cells": self.metrics_by_day[CASE_KEYS[2]][728]["exceeding_cells"],
                "strict_PoF_reference": "identical source field: controlled_day728_POF_eps0.jld2"}
        # Truth-slice read only, without loading the full 2000-member ensemble.
        with h5py.File(BASE / "data/geo/wise_perm_models_2000_new.jld2", "r", locking=False) as f:
            broad = f["BroadK"]
            assert broad.shape == (NZ, NX, 2000)
            truth = broad[:, :, 1999]
            z_index = 191 + int(np.argmax(truth[190:200, 249]))
            assert z_index == 192
            truth_hash = hashlib.sha256(truth.tobytes()).hexdigest()
        input_paths = set(Path(f.filename) for f in self.files.values())
        input_paths.add(SOURCES / "cvar_day728_sensitivity_1p22x.jld2")
        input_paths.add(SOURCES / "fracture_comparison_3x3_four_steps.png")
        inventory = [{"path": str(p.relative_to(BASE)), "bytes": p.stat().st_size, "sha256": sha256(p)} for p in sorted(input_paths)]
        result = {"mode": "existing_saved_times_only", "render_job_id": os.environ.get("SLURM_JOB_ID"),
                  "common_saved_times_days": self.times, "common_count": len(self.times),
                  "time_array_basis": "dt_days and dataset length; base snap_idx times period_days/10; day728 explicit day. No saved t=0.",
                  "duplicates_verified_and_deduplicated": self.duplicates,
                  "checks": checks, "day728_reference_check": day728_difference,
                  "global_field_extrema_all_available_times": extrema, "shared_color_limits": limits,
                  "truth": {"file": "data/geo/wise_perm_models_2000_new.jld2", "julia_slice": 2000, "python_shape_z_x": list(truth.shape), "sha256_z_x_native_bytes": truth_hash, "well_grid_1based": [250, 1, z_index]},
                  "inputs": inventory,
                  "unresolved": ["No saved t=0 spatial state.", "161 eight-day pressure/saturation fields per strict PoF and base CVaR are absent after day480.", "Historical forward exports have no embedded commit/dependency manifest.", "79-frame source coverage cannot establish an unsampled full-campaign peak."]}
        write_json(out / "validation.json", result)
        self.limits = limits
        return result


def make_policy_figure(data, key, title, day):
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 12, "axes.labelsize": 12, "xtick.labelsize": 11, "ytick.labelsize": 11})
    fig = plt.figure(figsize=(6.4, 10.8), dpi=200, facecolor="white")
    m = data.metrics_by_day[key][day]
    fig.text(.5, .974, "DTControl | Ground-truth campaign", ha="center", fontsize=16, weight="bold")
    fig.text(.5, .945, f"Day {day:04d} / 1920  |  Monitoring step {m['step']} / 4", ha="center", fontsize=14)
    fig.text(.5, .908, title, ha="center", fontsize=19, weight="bold")
    fig.text(.5, .877, f"Injection: {m['rate_m3_s']:.5f} m³/s   |   CO₂ injected: {m['cumulative_Mt']:.2f} Mt", ha="center", fontsize=12)
    fig.text(.5, .853, f"Minimum r: {m['min_r']:.5f}   |   Exceeding cells: {m['exceeding_cells']:,}", ha="center", fontsize=12)
    p, s = data.fields(key, day)
    fields = [(data.pmax - p) / data.pmax, (p - data.p0) / 1e6, s]
    titles = ["Relative safety margin  r = (pmax − pres) / pmax", "Pressure increase  pres − p₀", "CO₂ saturation"]
    cmaps = ["RdBu", "inferno", "viridis"]
    norms = [TwoSlopeNorm(vcenter=0, vmin=data.limits["margin"][0], vmax=data.limits["margin"][1]), Normalize(*data.limits["pressure_increase_MPa"]), Normalize(*data.limits["saturation"])]
    for row, bottom in enumerate([.605, .359, .113]):
        ax = fig.add_axes([.13, bottom, .72, .205])
        # HDF5 gives (z,x), already the orientation rendered in day728 reference.
        im = ax.imshow(fields[row], extent=EXTENT, origin="upper", interpolation="nearest", cmap=cmaps[row], norm=norms[row], aspect="auto")
        ax.set_title(titles[row], fontsize=12, pad=7)
        ax.set_ylabel("Depth [m]")
        ax.set_xticks([0, 1000, 2000, 3000]); ax.set_yticks([0, 500, 1000, 1500])
        if row < 2:
            ax.tick_params(labelbottom=False)
        else:
            ax.set_xlabel("X [m]")
        if row == 0:
            # Preserve the true continuous scale; categorical overlay keeps tiny
            # negative margins visible, including the nine-cell base CVaR event.
            mask = np.ma.masked_where(fields[0] >= 0, np.ones_like(fields[0]))
            ax.imshow(mask, extent=EXTENT, origin="upper", interpolation="nearest", cmap=ListedColormap(["#d00000"]), vmin=0, vmax=1, aspect="auto")
        ax.plot([1562.5, 1562.5], [1200, 1237.5], color="white", linewidth=3.2)
        ax.plot([1562.5, 1562.5], [1200, 1237.5], color="black", linewidth=1.1)
        cax = fig.add_axes([.865, bottom, .020, .205])
        cb = fig.colorbar(im, cax=cax)
        cb.set_label(["r [−]", "MPa", "SCO₂ [−]"][row], fontsize=10, labelpad=4)
        cb.ax.tick_params(labelsize=10)
        if row == 0:
            cb.set_ticks([-1, -.5, 0, .5, 1])
            cb.ax.axhline(0, color="black", lw=.8)
    fig.text(.5, .040, "Red cells: pressure-limit exceedance (r < 0)   |   Black line: injector", ha="center", fontsize=10)
    fig.text(.5, .022, "Saved states only: 8-day spacing to day 480; then 80 days + day 728", ha="center", fontsize=10)
    fig.text(.5, .005, "Cell counts describe this saved state; they are not ensemble PoF.", ha="center", fontsize=10)
    return fig


def render(data, out):
    frames = out / "frames"
    frames.mkdir()
    fontpath = matplotlib.font_manager.findfont("DejaVu Sans")
    titlefont = ImageFont.truetype(fontpath, 58)
    clockfont = ImageFont.truetype(fontpath, 50)
    # Screen time is proportional to physical time, quantized to video frames.
    # Day8 covers the initial display interval since t=0 is absent. Day1920
    # gets an 8-day display interval. The clock stays at the shown saved state.
    boundaries = np.r_[0, np.array(data.times[1:-1]), 1920-8, 1920]
    ticks = np.rint(boundaries / 1920 * FPS * DURATION).astype(int)
    repeats = np.diff(ticks)
    assert len(repeats) == len(data.times) and repeats.min() > 0 and repeats.sum() == FPS * DURATION
    timeline = []
    for idx, (day, repeat) in enumerate(zip(data.times, repeats)):
        parts = []
        for key, title, stem in zip(CASE_KEYS, TITLES, STEMS):
            fig = make_policy_figure(data, key, title, day)
            path = frames / f"{stem}_{idx:03d}.png"
            fig.savefig(path, dpi=200)  # Fixed canvas: never use bbox_inches=tight.
            plt.close(fig)
            with Image.open(path) as im:
                parts.append(im.convert("RGB"))
        combined = Image.new("RGB", (3840, 2160), "white")
        for col, part in enumerate(parts):
            assert part.size == (1280, 2160)
            combined.paste(part, (col * 1280, 0))
        draw = ImageDraw.Draw(combined)
        draw.rectangle((0, 0, 3839, 150), fill="white")
        draw.text((1920, 14), "DTControl | Three controlled ground-truth campaigns", font=titlefont, fill="black", anchor="mt")
        draw.text((1920, 84), f"Day {day:04d} / 1920  |  Monitoring step {int(np.ceil(day/480))} / 4", font=clockfont, fill="black", anchor="mt")
        combined.save(frames / f"comparison_{idx:03d}.png")
        if day in (728, 1920):
            suffix = "day728" if day == 728 else "poster"
            combined.save(out / f"comparison_{suffix}.png")
            for stem, part in zip(STEMS, parts):
                part.save(out / f"{stem}_{suffix}.png")
        timeline.append({"source_index": idx, "saved_day": day, "encoded_start_frame": int(ticks[idx]), "repeat_frames": int(repeat), "screen_duration_seconds": float(repeat / FPS)})
        if idx % 10 == 0:
            print(f"Rendered saved state {idx+1}/{len(data.times)} at day {day}", flush=True)
    write_json(out / "playback_timeline.json", timeline)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    for stem in ["comparison", *STEMS]:
        movie = out / f"{stem}.mp4"
        size = "3840x2160" if stem == "comparison" else "1280x2160"
        command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-n", "-f", "rawvideo", "-vcodec", "rawvideo", "-pix_fmt", "rgb24", "-s", size, "-r", str(FPS), "-i", "-", "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-threads", "4", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(movie)]
        with subprocess.Popen(command, stdin=subprocess.PIPE) as proc:
            for idx, repeat in enumerate(repeats):
                with Image.open(frames / f"{stem}_{idx:03d}.png") as im:
                    pixels = im.convert("RGB").tobytes()
                for _ in range(int(repeat)):
                    proc.stdin.write(pixels)
            proc.stdin.close()
            code = proc.wait()
            if code:
                raise RuntimeError(f"ffmpeg exited {code}: {movie}")
        print(f"Encoded {movie.name}", flush=True)
    outputs = [{"file": p.name, "bytes": p.stat().st_size, "sha256": sha256(p)} for p in sorted(out.iterdir()) if p.suffix in (".mp4", ".png")]
    write_json(out / "output_checksums.json", outputs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", required=True, type=Path)
    parser.add_argument("--audit-only", action="store_true")
    args = parser.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=False)
    data = SavedCampaigns()
    audit = data.audit(args.outdir)
    print(json.dumps({"common_count": audit["common_count"], "checks": [{k: c[k] for k in ["case", "mass_day1920_Mt", "peak_cells_over_available_fields"]} for c in audit["checks"]], "color_limits": audit["shared_color_limits"]}), flush=True)
    if not args.audit_only:
        render(data, args.outdir)
    for f in data.files.values():
        f.close()


if __name__ == "__main__":
    main()
