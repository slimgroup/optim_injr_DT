#!/usr/bin/env python3
"""Assemble the accepted focused mean/std PNGs without rendering or changing data.

Lightweight file copying and checksum validation only; no Slurm job is needed.
Old paper exports remain in place. A fresh output directory is required.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
PREVIEW = ROOT / "plots/paper_figures/posterior_relative_margin_preview_20261002_v2"
LAYOUT = ROOT / "plots/paper_figures/posterior_appendix_e_layout_20261002"
DOC = ROOT / "docs/analysis/POSTERIOR_RELATIVE_MARGIN_ACCEPTED_2026-10-02.md"
ROWS = ["relative_margin", "pressure_diff", "sat"]


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


class VerifiedSource:
    def __init__(self, root):
        self.root = root
        self.checks = json.loads((root / "delivery_checksums.json").read_text())

    def path(self, relative):
        path = self.root / relative
        assert digest(path) == self.checks[relative], relative
        return path

    def json(self, relative):
        return json.loads(self.path(relative).read_text())

    def copy(self, relative, target):
        source = self.path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as src, target.open("xb") as dst:
            shutil.copyfileobj(src, dst)
        assert digest(target) == self.checks[relative], relative
        return self.checks[relative]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    preview, layout = VerifiedSource(PREVIEW), VerifiedSource(LAYOUT)
    pm = preview.json("manifest.json")
    lm = layout.json("manifest.json")
    audit = preview.json("source_validation.json")
    assert pm["row_order"] == ROWS and not pm["case_specific_pressure_amplification"]
    assert audit["relative_margin_color_limits"]["focused"] == {"mean": [.02, .98], "std": [0., .029]}
    figures = []
    for item in pm["figures"]:
        if item["variant"] != "focused":
            continue
        step, stat = item["step"], item["statistic"]
        stem = f"posterior_{stat}_relative_margin_pressurediff_sat_step{step}"
        paper_name = f"state_{stat}_relative_margin_pressurediff_sat_all_cases_t{step}.png"
        target = f"posterior/{stem}.png"
        compat = f"paper_compat/posterior/{paper_name}"
        checksum = preview.copy(item["path"], out / target)
        assert checksum == item["sha256"]
        assert preview.copy(item["path"], out / compat) == checksum
        source = audit["steps"][str(step)]
        for case in source["cases"].values():
            assert case["sample_count"] == 128
            assert case["statistics"][stat]["pressure_difference_and_saturation_exactly_equal_to_paper_cache"]
        for field in item["field_checks"]:
            assert field["no_added_color_clipping"]
            if field["row"] == "relative_margin":
                assert field["clim"] == audit["relative_margin_color_limits"]["focused"][stat]
        figures.append({"source_path": str((PREVIEW / item["path"]).relative_to(ROOT)),
            "source_step": step, "statistic": stat, "row_order": ROWS,
            "input_dataset": [source["source"] + "::" + k for k in ["X_post1", "X_post2", "X_post3", "pres_Hyd"]],
            "input_sha256": source["sha256"], "canonical_export_path": str((out / target).relative_to(ROOT)),
            "handoff_path": target, "paper_current_path": f"figs/posterior/state_{stat}_pressurediff_pressure_sat_all_cases_t{step}.png",
            "paper_new_path": f"figs/posterior/{paper_name}", "compat_path": compat, "sha256": checksum,
            "byte_identical_to_accepted_focused_preview": True, "numeric_and_layout_validation": item,
            "pixels": item["pixels"]})
        preview.copy(f"arrays/{stat}_step{step}.npz", out / f"validation/arrays/{stat}_step{step}.npz")
    assert len(figures) == 8
    for item in lm["figures"]:
        if not item["handoff_path"].startswith("statistical/"):
            continue
        checksum = layout.copy(item["handoff_path"], out / item["handoff_path"])
        assert checksum == item["sha256"]
        assert layout.copy(item["compat_path"], out / item["compat_path"]) == checksum
        layout.copy(item["numeric_validation"], out / item["numeric_validation"])
        figures.append({**item, "source_path": item["canonical_export_path"],
            "canonical_export_path": str((out / item["handoff_path"]).relative_to(ROOT)),
            "paper_new_path": item["paper_current_path"],
            "byte_identical_to_previous_statistical_delivery": True})
    assert len(figures) == 14
    for item in figures:
        for name in (item["handoff_path"], item["compat_path"]):
            with Image.open(out / name) as image:
                assert list(image.size) == item["pixels"]
                assert round(image.info["dpi"][0]) == 400
                image.verify()
    preview.copy("source_validation.json", out / "validation/posterior_source_validation.json")
    layout.copy("validation/scientific_details.json", out / "validation/historical_scientific_details.json")
    for source, folder in ((preview, "posterior_preview"), (layout, "previous_layout")):
        for name in source.checks:
            if name.startswith("provenance/") or name in ("manifest.json", "delivery_receipt.json", "delivery_commit.json"):
                source.copy(name, out / "provenance" / folder / name)
    manifest = {"status": "accepted focused posterior mean and standard deviation",
        "formats": ["png"], "distinct_figures": 14, "posterior_row_order": ROWS,
        "relative_margin_color_limits": audit["relative_margin_color_limits"]["focused"],
        "pressure_amplification_factor": 1., "all_cases_and_steps_share_color_limits": True,
        "scope": "8 accepted focused posterior maps plus 6 unchanged statistical PNGs",
        "posterior_render_commit": preview.json("delivery_receipt.json")["commit"],
        "posterior_render_slurm_job": pm["slurm_job_id"],
        "assembly_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "figures": figures}
    write_json(out / "manifest.json", manifest)
    for source, name in ((DOC, "README.md"), (Path(__file__), "provenance/assemble_focused_posterior_handoff.py")):
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as src, target.open("xb") as dst:
            shutil.copyfileobj(src, dst)
    doc = DOC.read_text()
    prompt = doc.split("<!-- PAPER_PROMPT_START -->\n", 1)[1].split("\n<!-- PAPER_PROMPT_END -->", 1)[0]
    with (out / "PAPER_REPO_PROMPT.txt").open("x") as stream:
        stream.write(prompt + "\n")
    write_json(out / "delivery_checksums.json", {str(p.relative_to(out)): digest(p) for p in sorted(out.rglob("*")) if p.is_file()})
    print(f"Verified 8 focused posterior and 6 unchanged statistical PNGs, plus byte-identical paper copies: {out}")


if __name__ == "__main__":
    main()
