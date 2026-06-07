#!/usr/bin/env python3
"""Update scripts/shell/... path references after shell subfolder reorg."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

REPLACEMENTS = [
    ("scripts/shell/submit/submit_", "scripts/shell/submit/submit_"),
    ("scripts/shell/check/check_", "scripts/shell/check/check_"),
    ("scripts/shell/check/verify_", "scripts/shell/check/verify_"),
    ("scripts/shell/check/test_ds_verification.sh", "scripts/shell/check/test_ds_verification.sh"),
    ("scripts/shell/run/run_", "scripts/shell/run/run_"),
    ("scripts/shell/run/optim_inject_", "scripts/shell/run/optim_inject_"),
    ("scripts/shell/retry/retry_", "scripts/shell/retry/retry_"),
    ("scripts/shell/retry/rerun_", "scripts/shell/retry/rerun_"),
    ("scripts/shell/retry/cancel_", "scripts/shell/retry/cancel_"),
    ("scripts/shell/maintenance/collect_", "scripts/shell/maintenance/collect_"),
    ("scripts/shell/maintenance/move_", "scripts/shell/maintenance/move_"),
]

FIXUPS = [
    ("scripts/shell/submit/submit_", "scripts/shell/submit/submit_"),
    ("scripts/shell/check/check_", "scripts/shell/check/check_"),
    ("scripts/shell/run/run_", "scripts/shell/run/run_"),
    ("scripts/shell/retry/retry_", "scripts/shell/retry/retry_"),
    ("scripts/shell/retry/rerun_", "scripts/shell/retry/rerun_"),
    ("scripts/shell/retry/cancel_", "scripts/shell/retry/cancel_"),
    ("scripts/shell/maintenance/collect_", "scripts/shell/maintenance/collect_"),
    ("scripts/shell/maintenance/move_", "scripts/shell/maintenance/move_"),
]

SKIP_PARTS = {".git", "archive", "11-24-2025_backup_logs", "data", "plots", "logs"}
TEXT_EXT = {".md", ".sh", ".jl", ".py"}


def patch_text(text: str) -> str:
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    for old, new in FIXUPS:
        text = text.replace(old, new)
    return text


def _walk_files(root: Path):
    """Yield files under root, skipping unreadable or missing subtrees."""
    import os

    def onerror(err: OSError) -> None:
        print(f"skip subtree: {err.filename}: {err.strerror}")

    for dirpath, _dirnames, filenames in os.walk(root, onerror=onerror, followlinks=False):
        base = Path(dirpath)
        if any(part in SKIP_PARTS for part in base.parts):
            continue
        for name in filenames:
            yield base / name


def main() -> None:
    changed = 0
    for path in _walk_files(ROOT):
        if path.suffix not in TEXT_EXT:
            continue
        if any(part in SKIP_PARTS for part in path.parts):
            continue
        try:
            if not path.is_file():
                continue
            original = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        updated = patch_text(original)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed += 1
    print(f"updated {changed} files")


if __name__ == "__main__":
    main()
