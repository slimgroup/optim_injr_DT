#!/usr/bin/env python3
"""Save an independent zero-aligned copy of the existing fracture reference."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
from unittest.mock import patch

os.environ.setdefault("MPLBACKEND", "Agg")
os.environ.setdefault("MPLCONFIGDIR", "/tmp/mpl_zero_aligned_reference")
import matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm
import numpy as np
from export_posterior_appendix_e import capture_plot, numeric_contents, sha256, write_json

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = ROOT / "scripts/python_plots/plot_real_fracture_comparison_day408.py"
    with patch.dict(os.environ, {"CVAR_SENSITIVITY": "1.22"}):
        spec = importlib.util.spec_from_file_location("reference_zero_source", source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    inputs = {str(path.relative_to(ROOT)): sha256(path) for _, _, path in module.CASES}
    fig = capture_plot(module.main)
    before = numeric_contents(fig)
    counts = [int(np.count_nonzero(fig.axes[c].images[0].get_array() < 0)) for c in range(3)]
    assert counts == [0, 97, 6953], counts
    norm = BoundaryNorm(np.r_[np.linspace(-.1, 0, 27), np.linspace(0, 1, 231)[1:]], 256)
    for ax in fig.axes[:3]:
        im = ax.images[0]
        cmap = im.cmap.copy()
        cmap.set_under(plt.cm.Reds_r(0.))
        im.set_cmap(cmap)
        im.set_norm(norm)
        np.testing.assert_array_equal(norm(im.get_array()) < 26, im.get_array() < 0)
    cb = fig.axes[2].images[0].colorbar
    cb.set_ticks([0., .25, .5, .75, 1.])
    cb.ax.minorticks_off()
    after = numeric_contents(fig)
    for key in before:
        if int(key.split("_")[0][4:]) < 9:
            np.testing.assert_array_equal(before[key], after[key], err_msg=key)
    path = out / "fracture_comparison_3x3_four_steps_zero_aligned.png"
    with path.open("xb") as stream:
        fig.savefig(stream, format="png", dpi=400, bbox_inches="tight", pad_inches=.04)
    plt.close(fig)
    assert {name: sha256(ROOT / name) for name in inputs} == inputs
    with source.open("rb") as src, (out / source.name).open("xb") as dst:
        shutil.copyfileobj(src, dst)
    with Path(__file__).open("rb") as src, (out / Path(__file__).name).open("xb") as dst:
        shutil.copyfileobj(src, dst)
    write_json(out / "validation.json", {"source_script": str(source.relative_to(ROOT)),
        "source_script_sha256": sha256(source), "input_sha256": inputs,
        "original_field_arrays_and_limits_unchanged": True,
        "case_order": [key for key, _, _ in module.CASES], "exceeding_cells": counts,
        "existing_reference_CVaR_schedule_multiplier": 1.22,
        "new_pressure_transformation_applied_to_reference": False,
        "only_change": "Reference relative-margin red/blue bin boundary aligned at r=0; PNG exported at 400 dpi",
        "png": path.name, "sha256": sha256(path), "slurm_job_id": os.environ.get("SLURM_JOB_ID")})
    print(f"Saved {path}; original field arrays and exceeding counts {counts} retained", flush=True)


if __name__ == "__main__":
    main()
