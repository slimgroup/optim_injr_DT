#!/usr/bin/env python3
"""Organize plots/DT_control: group videos, geo plots, and ECDF outputs."""

from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DT = ROOT / "plots/DT_control"
STEP1 = DT / "exp_name=step1"
ECDF_SRC = ROOT / "plots/bootstrap_cdf_analysis"
ECDF_DST = STEP1 / "statistical_analysis/ecdf"


def move_dir(src: Path, dst: Path, moved: dict[str, int], label: str) -> None:
    if not src.is_dir():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        moved["skipped"] += 1
        return
    shutil.move(str(src), str(dst))
    moved[label] += 1


def main() -> None:
    moved = {"video_128perm": 0, "videos_5cases": 0, "geo_png": 0, "ecdf_files": 0, "skipped": 0}

    videos_root = DT / "videos"
    (videos_root / "128perm").mkdir(parents=True, exist_ok=True)
    (videos_root / "5cases").mkdir(parents=True, exist_ok=True)
    (STEP1 / "geo").mkdir(parents=True, exist_ok=True)
    ECDF_DST.mkdir(parents=True, exist_ok=True)

    for entry in sorted(DT.iterdir()):
        if not entry.is_dir():
            continue
        name = entry.name
        if name.startswith("video_128perm_"):
            move_dir(entry, videos_root / "128perm" / name, moved, "video_128perm")
        elif name.startswith("videos_5cases_"):
            move_dir(entry, videos_root / "5cases" / name, moved, "videos_5cases")

    if STEP1.is_dir():
        for entry in STEP1.iterdir():
            if entry.is_file() and entry.name.startswith("permeability_samples") and entry.suffix == ".png":
                target = STEP1 / "geo" / entry.name
                if target.exists():
                    moved["skipped"] += 1
                    continue
                shutil.move(str(entry), str(target))
                moved["geo_png"] += 1

    if ECDF_SRC.is_dir():
        for entry in ECDF_SRC.iterdir():
            if not entry.is_file():
                continue
            target = ECDF_DST / entry.name
            if target.exists():
                moved["skipped"] += 1
                continue
            shutil.move(str(entry), str(target))
            moved["ecdf_files"] += 1
        try:
            ECDF_SRC.rmdir()
        except OSError:
            pass

    print("organize_dt_control_plots summary:")
    for k, v in moved.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
