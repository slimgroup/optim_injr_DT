#!/usr/bin/env python3
"""Move misplaced step1 plots and aggregates out of data/ root."""

from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
STEP1 = ROOT / "data/DT_control/exp_name=step1"
PLOTS = ROOT / "plots/DT_control/exp_name=step1/statistical_analysis"
AGG = STEP1 / "_aggregates"


def kde_subdir(name: str) -> str:
    lower = name.lower()
    if re.search(r"panel[123]_.*_(4x3|5x4)", lower) or lower.startswith("panel1_histogram_kde"):
        if "5x4" in lower:
            return "panels_5x4"
        return "panels_4x3"
    if any(x in lower for x in ("combined_", "panel_cvar_vs_pof", "panel_cvar_distribution", "panel_pof_distribution")):
        return "comparison"
    if any(x in lower for x in ("_freq_", "_meanstd_", "left1pct_hist_2025", "last_inj_rate_hist_2025", "last_inj_rate_202510")):
        return "legacy_202511"
    if lower.startswith(("pof_eps", "cvar_", "individual_cvar")):
        return "single_case"
    return "other"


def main() -> None:
    moved = {"png": 0, "csv": 0, "jld2": 0, "notes": 0, "skipped": 0}
    errors: list[str] = []

    for sub in ("kde/single_case", "kde/panels_4x3", "kde/panels_5x4", "kde/comparison", "kde/legacy_202511", "kde/other"):
        (PLOTS / sub).mkdir(parents=True, exist_ok=True)
    for sub in ("csv", "jld2", "notes"):
        (AGG / sub).mkdir(parents=True, exist_ok=True)

    for entry in sorted(STEP1.iterdir()):
        if not entry.is_file():
            continue
        name = entry.name

        if name.lower().endswith(".png"):
            kind = "png"
            target = PLOTS / "kde" / kde_subdir(name) / name
        elif name.endswith(".csv"):
            kind = "csv"
            target = AGG / "csv" / name
        elif name.endswith(".jld2"):
            kind = "jld2"
            target = AGG / "jld2" / name
        elif name.endswith((".md", ".py")):
            kind = "notes"
            target = AGG / "notes" / name
        else:
            moved["skipped"] += 1
            continue

        # Preserve both artifacts when a previous organization already created
        # this destination, including a dangling symlink or a directory.
        if target.exists() or target.is_symlink():
            moved["skipped"] += 1
            print(f"Skipping existing destination: {target}")
            continue
        try:
            shutil.move(str(entry), str(target))
            moved[kind] += 1
        except OSError as e:
            errors.append(f"{name}: {e}")

    remaining_files = sum(1 for p in STEP1.iterdir() if p.is_file())
    print("organize_step1_data summary:")
    for k, v in moved.items():
        print(f"  {k}: {v}")
    print(f"  files remaining at step1 root: {remaining_files}")
    if errors:
        print("errors:")
        for e in errors[:10]:
            print(f"  {e}")


if __name__ == "__main__":
    main()
