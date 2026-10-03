#!/usr/bin/env python3
"""Move existing logs into logs/{optimization,utilities,submit}/ without deleting."""

from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LOGS = ROOT / "logs"

STEP_RE = re.compile(r"step(\d+)", re.I)
RERUN_MARKERS = ("rerun", "_fix")


def dest_for_dt_log(name: str) -> Path:
    """Return destination directory for out_/err_DT_*.txt files."""
    lower = name.lower()
    if any(m in lower for m in RERUN_MARKERS):
        m = STEP_RE.search(name)
        if m:
            return LOGS / "optimization" / f"step{m.group(1)}" / "reruns"
        return LOGS / "optimization" / "step1" / "reruns"

    m = STEP_RE.search(name)
    if m:
        return LOGS / "optimization" / f"step{m.group(1)}"

    return LOGS / "optimization" / "step1"


def dest_for_utility(name: str) -> Path | None:
    prefixes = (
        "ds_verification_",
        "bootstrap_cdf_",
        "video_generation_",
        "128perm_",
        "test_scratch_",
        "check_7cases_outlier_",
        "slurm-",
    )
    if any(name.startswith(p) for p in prefixes):
        return LOGS / "utilities"
    if name.endswith(".out") or name.endswith(".err"):
        return LOGS / "utilities"
    return None


def main() -> None:
    moved = {"optimization": 0, "utilities": 0, "submit": 0, "skipped": 0}
    errors: list[str] = []

    for sub in (
        "optimization/step1",
        "optimization/step1/reruns",
        "optimization/step2",
        "optimization/step2/reruns",
        "optimization/step3",
        "optimization/step3/reruns",
        "optimization/step4",
        "optimization/step4/reruns",
        "utilities",
        "submit",
    ):
        (LOGS / sub).mkdir(parents=True, exist_ok=True)

    # submit archive -> submit/
    archive = LOGS / "submit_65_128_archive"
    if archive.is_dir():
        for f in archive.iterdir():
            if f.is_file():
                target = LOGS / "submit" / f.name
                if target.exists() or target.is_symlink():
                    moved["skipped"] += 1
                    continue
                shutil.move(str(f), str(target))
                moved["submit"] += 1

    for entry in sorted(LOGS.iterdir()):
        if not entry.is_file():
            continue
        name = entry.name

        if name.startswith(("out_DT_", "err_DT_")) and name.endswith(".txt"):
            dest_dir = dest_for_dt_log(name)
            dest_dir.mkdir(parents=True, exist_ok=True)
            target = dest_dir / name
            if target.exists() or target.is_symlink():
                moved["skipped"] += 1
                continue
            try:
                shutil.move(str(entry), str(target))
                moved["optimization"] += 1
            except OSError as e:
                errors.append(f"{name}: {e}")
            continue

        if name.endswith(".log") and name.startswith("submit"):
            target = LOGS / "submit" / name
            if target.exists() or target.is_symlink():
                moved["skipped"] += 1
                continue
            try:
                shutil.move(str(entry), str(target))
                moved["submit"] += 1
            except OSError as e:
                errors.append(f"{name}: {e}")
            continue

        util_dir = dest_for_utility(name)
        if util_dir is not None:
            target = util_dir / name
            if target.exists() or target.is_symlink():
                moved["skipped"] += 1
                continue
            try:
                shutil.move(str(entry), str(target))
                moved["utilities"] += 1
            except OSError as e:
                errors.append(f"{name}: {e}")
            continue

        moved["skipped"] += 1

    print("organize_logs summary:")
    for k, v in moved.items():
        print(f"  {k}: {v}")
    if errors:
        print("errors:")
        for e in errors[:20]:
            print(f"  {e}")
        if len(errors) > 20:
            print(f"  ... and {len(errors) - 20} more")

    remaining = sum(1 for p in LOGS.iterdir() if p.is_file())
    print(f"files remaining at logs/ root: {remaining}")


if __name__ == "__main__":
    main()
