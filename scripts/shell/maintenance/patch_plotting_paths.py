#!/usr/bin/env python3
"""Update path references after plotting subfolder reorg."""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

REPLACEMENTS = [
    ("scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py",
     "scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py"),
    ("scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py",
     "scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py"),
    ("scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py",
     "scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py"),
    ("scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl",
     "scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl"),
    ("scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl",
     "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl"),
    ("scripts/julia_scripts/plotting/bootstrap_ecdf/plot_two_panel_bootstrap.jl",
     "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_two_panel_bootstrap.jl"),
    ("scripts/julia_scripts/plotting/bootstrap_ecdf/plot_cdf_ci.jl",
     "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_cdf_ci.jl"),
    ("scripts/julia_scripts/plotting/videos/generate_128samples_video.jl",
     "scripts/julia_scripts/plotting/videos/generate_128samples_video.jl"),
    ("scripts/julia_scripts/plotting/videos/generate_5case_videos.jl",
     "scripts/julia_scripts/plotting/videos/generate_5case_videos.jl"),
    ("scripts/julia_scripts/plotting/videos/generate_stat3case_videos.jl",
     "scripts/julia_scripts/plotting/videos/generate_stat3case_videos.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_cvar.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_cvar.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_pof.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_pof.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_7cases_inj_rate_histogram.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_7cases_inj_rate_histogram.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_individual_cases.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_individual_cases.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_cvar_vs_pof.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_cvar_vs_pof.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_single_pof_eps0.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_single_pof_eps0.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_three_panels.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_three_panels.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_three_panels_5x4.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_three_panels_5x4.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_pof_vs_cvar.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_pof_vs_cvar.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl"),
    ("scripts/julia_scripts/plotting/legacy_step1/plot_pof_cvar_comparison_advanced.jl",
     "scripts/julia_scripts/plotting/legacy_step1/plot_pof_cvar_comparison_advanced.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/check_collected_data.jl",
     "scripts/julia_scripts/plotting/diagnostics/check_collected_data.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/check_gamma0_data.jl",
     "scripts/julia_scripts/plotting/diagnostics/check_gamma0_data.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/check_gamma_matching.jl",
     "scripts/julia_scripts/plotting/diagnostics/check_gamma_matching.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/debug_gamma_data.jl",
     "scripts/julia_scripts/plotting/diagnostics/debug_gamma_data.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/verify_calculation_logic.jl",
     "scripts/julia_scripts/plotting/diagnostics/verify_calculation_logic.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/verify_inj_rate_calculation.jl",
     "scripts/julia_scripts/plotting/diagnostics/verify_inj_rate_calculation.jl"),
    ("scripts/julia_scripts/plotting/diagnostics/test_title_position.jl",
     "scripts/julia_scripts/plotting/diagnostics/test_title_position.jl"),
    ("scripts/julia_scripts/plotting/general/plot_fracture_comparison.jl",
     "scripts/julia_scripts/plotting/general/plot_fracture_comparison.jl"),
    ("scripts/julia_scripts/plotting/general/plot_perm_ensemble.jl",
     "scripts/julia_scripts/plotting/general/plot_perm_ensemble.jl"),
    ("scripts/julia_scripts/plotting/general/plot_perm_samples.jl",
     "scripts/julia_scripts/plotting/general/plot_perm_samples.jl"),
    ("scripts/julia_scripts/plotting/general/plot_inj_and_cause.jl",
     "scripts/julia_scripts/plotting/general/plot_inj_and_cause.jl"),
    ("scripts/python_plots/legacy/plot_pof_cvar.py",
     "scripts/python_plots/legacy/plot_pof_cvar.py"),
    ("scripts/python_plots/legacy/plot_pressure_zones.py",
     "scripts/python_plots/legacy/plot_pressure_zones.py"),
    ("scripts/python_plots/legacy/logistic_exceedance_indicator.py",
     "scripts/python_plots/legacy/logistic_exceedance_indicator.py"),
    ("scripts/julia_scripts/archive/plot_fake.jl",
     "scripts/julia_scripts/archive/plot_fake.jl"),
]

SKIP_PARTS = {".git", "archive", "data", "plots", "logs"}
TEXT_EXT = {".md", ".sh", ".jl", ".py"}


def _walk_files(root: Path):
    def onerror(err: OSError) -> None:
        print(f"skip subtree: {err.filename}: {err.strerror}")

    for dirpath, _dirnames, filenames in os.walk(root, onerror=onerror, followlinks=False):
        base = Path(dirpath)
        if any(part in SKIP_PARTS for part in base.parts):
            continue
        for name in filenames:
            yield base / name


def patch_text(text: str) -> str:
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    return text


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
