#!/usr/bin/env python3
"""Read-only source/layout checks; never submit jobs or regenerate artifacts."""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[3]
NAVIGATION = [
    "README.md", "DATA_AVAILABILITY.md", "src/README.md", "test/README.md",
    "scripts/README.md", "scripts/shell/README.md",
    "scripts/python_plots/README.md", "scripts/python_tools/README.md",
    "scripts/julia_scripts/README.md", "scripts/julia_scripts/plotting/README.md",
    "scripts/julia_scripts/data_collection/README.md",
    "docs/README.md", "docs/REPRODUCIBILITY.md", "docs/historical/README.md",
    "docs/workflow/PACE_RUN_GUIDE.md", "docs/reference/DIRECTORY_STRUCTURE.md",
    "docs/reference/SCRIPTS_INDEX.md", "docs/reference/PAPER_FIGURE_MANIFEST.md",
    "docs/reference/REPOSITORY_CLEANUP.md",
    "plots/README.md", "plots/latest/README.md",
    "plots/paper_figures/README.md", "docs/figures/README.md",
    "docs/reference/DELETION_REVIEW_2026-10-03.md",
]


def check_links(root):
    errors = []
    for name in NAVIGATION:
        path = root / name
        if not path.is_file():
            errors.append(f"Missing navigation document: {name}")
            continue
        text = re.sub(r"```.*?```", "", path.read_text(), flags=re.S)
        for target in re.findall(r"\]\(([^\s)]+)\)", text):
            if re.match(r"[a-zA-Z][\w+.-]*:|#", target):
                continue
            target = unquote(target.split("#", 1)[0])
            if not (path.parent / target).exists():
                errors.append(f"Broken local link in {name}: {target}")
    return errors


def check_sources(root):
    errors = []
    python_files = sorted((root / "scripts").rglob("*.py"))
    python_files += sorted((root / "test").rglob("*.py"))
    for path in python_files:
        try:
            ast.parse(path.read_text(), filename=str(path))
        except (SyntaxError, UnicodeError) as exc:
            errors.append(f"{path.relative_to(root)}: {exc}")
    shell_files = sorted((root / "scripts/shell").rglob("*.sh"))
    for path in shell_files:
        result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
        if result.returncode:
            errors.append(result.stderr.strip())
        text = path.read_text()
        # All current shell helpers live three levels below the repository root.
        for expr in re.findall(r'(?:ROOT_DIR|REPO_ROOT)=.*?\$\{?SCRIPT_DIR\}?(/(?:\.\./?)+)', text):
            if (path.parent / expr.lstrip("/")).resolve() != root.resolve():
                errors.append(f"Incorrect repository-root traversal: {path.relative_to(root)}")
        for driver in re.findall(r'SBATCH_FILE="\$\{SCRIPT_DIR\}/([^"]+)"', text):
            if not (path.parent / driver).is_file():
                errors.append(f"Missing batch driver in {path.relative_to(root)}: {driver}")
    return errors, len(python_files), len(shell_files)


def check_assets(root, verify_files=False):
    registry = root / "docs/reference/paper_assets.json"
    manifest = json.loads(registry.read_text())
    errors = []
    seen = set()
    for asset in manifest["assets"]:
        name = asset["path"]
        if name in seen:
            errors.append(f"Duplicate selected asset: {name}")
        seen.add(name)
        for key in ("path", "producer", "selection_record", "view"):
            relative = Path(asset[key])
            if relative.is_absolute() or ".." in relative.parts:
                errors.append(f"Non-repository path in asset {name}: {relative}")
            elif key != "path" and not (root / relative).is_file():
                errors.append(f"Missing {key} for {name}: {relative}")
        view = root / asset["view"]
        if not view.is_symlink() or view.resolve() != (root / name).resolve():
            errors.append(f"Current-results link does not match its selected asset: {asset['view']}")
        if verify_files:
            path = root / name
            if not path.is_file():
                errors.append(f"Missing local paper asset: {name}")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != asset["sha256"]:
                errors.append(f"Paper asset differs from recorded selection: {name}")
    return errors, len(seen)


def check_figure_documents(root):
    """Check compatibility links without reading large research artifacts."""
    records = json.loads((root / "docs/reference/figure_document_locations.json").read_text())
    errors = []
    for item in records["files"]:
        original, document = root / item["original"], root / item["document"]
        if not original.is_symlink() or original.resolve() != document.resolve():
            errors.append(f"Figure-document link mismatch: {item['original']}")
        if not document.is_file():
            errors.append(f"Missing figure reading note: {item['document']}")
        elif hashlib.sha256(document.read_bytes()).hexdigest() != item["sha256"]:
            errors.append(f"Figure reading note differs from relocation record: {item['document']}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--paper-assets", action="store_true",
                        help="also verify selected local PNGs against recorded SHA-256 hashes")
    args = parser.parse_args()
    errors = check_links(ROOT)
    errors.extend(check_figure_documents(ROOT))
    source_errors, n_python, n_shell = check_sources(ROOT)
    errors.extend(source_errors)
    asset_errors, n_assets = check_assets(ROOT, args.paper_assets)
    errors.extend(asset_errors)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    print(f"Checked {len(NAVIGATION)} navigation documents, {n_python} Python files, "
          f"{n_shell} shell scripts, and {n_assets} selected-asset records.")
    if errors:
        return 1
    print("Repository checks passed. No simulations, renders, or Slurm calls were run.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
