#!/usr/bin/env python3
"""
Generate posterior mean/std summary figures for all four monitoring steps using
shared per-variable color scales across steps.

This script intentionally updates only the paper-style summary figures:
  - state_mean_all_cases.png
  - state_std_all_cases.png
  - state_mean_pressurediff_pressure_sat_all_cases.png
  - state_std_pressurediff_pressure_sat_all_cases.png

It does not clear output folders and does not regenerate movies or the broader
uncertainty grids.
"""

from pathlib import Path

import plot_posterior_uncertainty as ppu


PROJECT_ROOT = Path(ppu.PROJECT_ROOT)

STEP_CONFIG = [
    {
        "label": "t=1",
        "input": PROJECT_ROOT / "data" / "posterior" / "three_set_posteriro_samples_t1_pof_cvar.jld2",
        "outdir": PROJECT_ROOT / "plots" / "posterior_field_uncertainty",
    },
    {
        "label": "t=2",
        "input": PROJECT_ROOT / "data" / "posterior" / "three_set_posteriro_samples_t2_pof_cvar.jld2",
        "outdir": PROJECT_ROOT / "plots" / "posterior_field_uncertainty_t2_static",
    },
    {
        "label": "t=3",
        "input": PROJECT_ROOT / "data" / "posterior" / "three_set_posteriro_samples_t3_pof_cvar.jld2",
        "outdir": PROJECT_ROOT / "plots" / "posterior_field_uncertainty_t3_static",
    },
    {
        "label": "t=4",
        "input": PROJECT_ROOT / "data" / "posterior" / "three_set_posteriro_samples_t4_pof_cvar.jld2",
        "outdir": PROJECT_ROOT / "plots" / "posterior_field_uncertainty_t4_static",
    },
]


def compute_shared_ranges(step_samples, row_vars, stat_name):
    is_mean = stat_name == "mean"
    ranges = {}
    for var_name in row_vars:
        cfg = ppu.VAR_CONFIG[var_name]
        if cfg["fixed_vmin"] is not None and cfg["fixed_vmax"] is not None:
            ranges[var_name] = (cfg["fixed_vmin"], cfg["fixed_vmax"])
            continue

        if is_mean:
            vmin = min(
                float(ppu.to_display_units(samples[key][var_name], var_name).min())
                for samples in step_samples
                for key in ppu.CASES
            )
            vmax = max(
                float(ppu.to_display_units(samples[key][var_name], var_name).max())
                for samples in step_samples
                for key in ppu.CASES
            )
            ranges[var_name] = (vmin, vmax)
        else:
            vmax = max(
                ppu.get_std_vmax(ppu.to_display_units(samples[key][var_name], var_name))
                for samples in step_samples
                for key in ppu.CASES
            )
            ranges[var_name] = (0.0, vmax)
    return ranges


def main():
    loaded = []
    for cfg in STEP_CONFIG:
        samples, _ = ppu.load_samples(str(cfg["input"]))
        loaded.append(samples)

    rm_rows = ["relative_margin", "pressure_diff", "sat"]
    no_rm_rows = ["pressure_diff", "pressure", "sat"]

    shared_rm_mean = compute_shared_ranges(loaded, rm_rows, "mean")
    shared_rm_std = compute_shared_ranges(loaded, rm_rows, "std")
    shared_no_rm_mean = compute_shared_ranges(loaded, no_rm_rows, "mean")
    shared_no_rm_std = compute_shared_ranges(loaded, no_rm_rows, "std")

    for cfg, samples in zip(STEP_CONFIG, loaded):
        outdir = str(cfg["outdir"])
        label = cfg["label"]
        ppu.ensure_clean_output_dir(outdir)
        ppu.plot_paper_style_summary(
            samples,
            outdir,
            "mean",
            label,
            row_vars=rm_rows,
            out_name="state_mean_all_cases.png",
            value_ranges=shared_rm_mean,
        )
        ppu.plot_paper_style_summary(
            samples,
            outdir,
            "std",
            label,
            row_vars=rm_rows,
            out_name="state_std_all_cases.png",
            value_ranges=shared_rm_std,
        )
        ppu.plot_paper_style_summary(
            samples,
            outdir,
            "mean",
            label,
            row_vars=no_rm_rows,
            out_name="state_mean_pressurediff_pressure_sat_all_cases.png",
            value_ranges=shared_no_rm_mean,
        )
        ppu.plot_paper_style_summary(
            samples,
            outdir,
            "std",
            label,
            row_vars=no_rm_rows,
            out_name="state_std_pressurediff_pressure_sat_all_cases.png",
            value_ranges=shared_no_rm_std,
        )


if __name__ == "__main__":
    main()
