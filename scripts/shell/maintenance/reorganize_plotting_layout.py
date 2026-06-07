#!/usr/bin/env python3
"""Move julia_scripts/plotting and related python stats scripts into subfolders."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

MOVES: list[tuple[str, str]] = [
    # posterior stats (Julia)
    (
        "scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl",
        "scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl",
    ),
    # posterior stats (Python) -> python_plots
    (
        "scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py",
        "scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py",
    ),
    (
        "scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py",
        "scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py",
    ),
    (
        "scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py",
        "scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py",
    ),
    # bootstrap / ECDF
    (
        "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl",
        "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl",
    ),
    (
        "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_two_panel_bootstrap.jl",
        "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_two_panel_bootstrap.jl",
    ),
    (
        "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_cdf_ci.jl",
        "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_cdf_ci.jl",
    ),
    # videos
    (
        "scripts/julia_scripts/plotting/videos/generate_128samples_video.jl",
        "scripts/julia_scripts/plotting/videos/generate_128samples_video.jl",
    ),
    (
        "scripts/julia_scripts/plotting/videos/generate_5case_videos.jl",
        "scripts/julia_scripts/plotting/videos/generate_5case_videos.jl",
    ),
    (
        "scripts/julia_scripts/plotting/videos/generate_stat3case_videos.jl",
        "scripts/julia_scripts/plotting/videos/generate_stat3case_videos.jl",
    ),
    # legacy step1
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_cvar.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_cvar.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_pof.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_injr_distributions_pof.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_7cases_inj_rate_histogram.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_7cases_inj_rate_histogram.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_individual_cases.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_individual_cases.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_cvar_vs_pof.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_cvar_vs_pof.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_single_pof_eps0.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_single_pof_eps0.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_three_panels.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_three_panels.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_three_panels_5x4.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_three_panels_5x4.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_pof_vs_cvar.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_pof_vs_cvar.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl",
    ),
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_pof_cvar_comparison_advanced.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_pof_cvar_comparison_advanced.jl",
    ),
    # diagnostics
    (
        "scripts/julia_scripts/plotting/diagnostics/check_collected_data.jl",
        "scripts/julia_scripts/plotting/diagnostics/check_collected_data.jl",
    ),
    (
        "scripts/julia_scripts/plotting/diagnostics/check_gamma0_data.jl",
        "scripts/julia_scripts/plotting/diagnostics/check_gamma0_data.jl",
    ),
    (
        "scripts/julia_scripts/plotting/diagnostics/check_gamma_matching.jl",
        "scripts/julia_scripts/plotting/diagnostics/check_gamma_matching.jl",
    ),
    (
        "scripts/julia_scripts/plotting/diagnostics/debug_gamma_data.jl",
        "scripts/julia_scripts/plotting/diagnostics/debug_gamma_data.jl",
    ),
    (
        "scripts/julia_scripts/plotting/diagnostics/verify_calculation_logic.jl",
        "scripts/julia_scripts/plotting/diagnostics/verify_calculation_logic.jl",
    ),
    (
        "scripts/julia_scripts/plotting/diagnostics/verify_inj_rate_calculation.jl",
        "scripts/julia_scripts/plotting/diagnostics/verify_inj_rate_calculation.jl",
    ),
    (
        "scripts/julia_scripts/plotting/diagnostics/test_title_position.jl",
        "scripts/julia_scripts/plotting/diagnostics/test_title_position.jl",
    ),
    # general Julia figures
    (
        "scripts/julia_scripts/plotting/general/plot_fracture_comparison.jl",
        "scripts/julia_scripts/plotting/general/plot_fracture_comparison.jl",
    ),
    (
        "scripts/julia_scripts/plotting/general/plot_perm_ensemble.jl",
        "scripts/julia_scripts/plotting/general/plot_perm_ensemble.jl",
    ),
    (
        "scripts/julia_scripts/plotting/general/plot_perm_samples.jl",
        "scripts/julia_scripts/plotting/general/plot_perm_samples.jl",
    ),
    (
        "scripts/julia_scripts/plotting/general/plot_inj_and_cause.jl",
        "scripts/julia_scripts/plotting/general/plot_inj_and_cause.jl",
    ),
    # legacy python in plotting -> python_plots/legacy
    (
        "scripts/python_plots/legacy/plot_pof_cvar.py",
        "scripts/python_plots/legacy/plot_pof_cvar.py",
    ),
    (
        "scripts/python_plots/legacy/plot_pressure_zones.py",
        "scripts/python_plots/legacy/plot_pressure_zones.py",
    ),
    (
        "scripts/python_plots/legacy/logistic_exceedance_indicator.py",
        "scripts/python_plots/legacy/logistic_exceedance_indicator.py",
    ),
    # scratch plot -> archive
    (
        "scripts/julia_scripts/archive/plot_fake.jl",
        "scripts/julia_scripts/archive/plot_fake.jl",
    ),
]

PATH_REPLACEMENTS: list[tuple[str, str]] = [
    (old, new) for old, new in MOVES
] + [
    (
        "scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl",
        "scripts/julia_scripts/plotting/legacy_step1/plot_threshold_sensitivity.jl",
    ),
]


def git_mv(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not src.exists():
        if dst.exists():
            return
        raise FileNotFoundError(src)
    if dst.exists():
        raise FileExistsError(dst)
    subprocess.run(["git", "mv", str(src), str(dst)], cwd=ROOT, check=True)


def main() -> None:
    moved = 0
    for rel_src, rel_dst in MOVES:
        src = ROOT / rel_src
        dst = ROOT / rel_dst
        if not src.exists() and dst.exists():
            continue
        git_mv(src, dst)
        moved += 1
    print(f"moved {moved} plotting scripts")


if __name__ == "__main__":
    main()
