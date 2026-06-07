#!/usr/bin/env python3
"""Reorganize scripts/shell into topic subfolders."""

from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SHELL = ROOT / "scripts/shell"

MAP = {
    "submit": """
        submit_11_cases_samples_1_128.sh
        submit_11_cases_samples_2_64_smart.sh
        submit_128perm_only.sh
        submit_20_cases_samples_65_128_smart.sh
        submit_all.sh
        submit_bootstrap_cdf.sh
        submit_cvar_2cases_alpha_0.02.sh
        submit_cvar_4cases_alpha_0_0.01.sh
        submit_cvar_g=0.2_a=0.01.sh
        submit_cvar_gamma_0.1_0.2.sh
        submit_cvar_gamma_0.4.sh
        submit_gamma_table_generation.sh
        submit_missing_pof_samples.sh
        submit_missing_pof_samples_fix.sh
        submit_pof_cases_simple.sh
        submit_pof_cases_smart.sh
        submit_pof_sensitivity.sh
        submit_posterior_summary_all_steps_shared.sh
        submit_step2_dual_prior_smoketest.sh
        submit_step3_paired_smoketest.sh
        submit_step4_paired_all.sh
        submit_step4_paired_smoketest.sh
        submit_threshold_sensitivity.sh
        submit_video_generation.sh
    """.split(),
    "check": """
        check_7cases_inj_rate.sh
        check_7cases_outlier.sh
        check_all_pof_cases.sh
        check_ds_verification.sh
        check_missing_samples_progress.sh
        check_step2_progress.sh
        check_step3_smoketest_logs.sh
        check_submit_65_128_progress.sh
        check_test_status.sh
        check_verification_status.sh
        test_ds_verification.sh
        verify_logs_path.sh
        verify_skip_from_log.sh
    """.split(),
    "run": """
        run_bootstrap_cdf.sh
        run_plot_threshold_sensitivity.sh
        run_scaling_all.sh
        run_step2_paired_posterior_stats.sh
        optim_inject_cruyff.sh
        optim_inject_cruyff_cpu.sh
        optim_inject_pace.sh
        optim_inject_pace_7cases_fix.sh
    """.split(),
    "retry": """
        cancel_duplicate_pof_jobs.sh
        rerun_7_missing_cvar_samples_fix.sh
        retry_failed_job.sh
        retry_step2_sample113.sh
    """.split(),
    "maintenance": """
        collect_and_plot_cvar.sh
        move_iteration_files_to_scratch.sh
    """.split(),
}


def main() -> None:
    moved = 0
    for sub, names in MAP.items():
        dest_dir = SHELL / sub
        dest_dir.mkdir(parents=True, exist_ok=True)
        for name in names:
            src = SHELL / name
            if not src.is_file():
                continue
            target = dest_dir / name
            if target.exists():
                continue
            shutil.move(str(src), str(target))
            moved += 1

    cleanup = SHELL / "CLEANUP_PLAN.md"
    hist = ROOT / "docs/historical/shell_cleanup_plan.md"
    if cleanup.is_file() and not hist.exists():
        hist.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(cleanup), str(hist))

    remaining = [p.name for p in SHELL.iterdir() if p.is_file()]
    print(f"moved {moved} shell scripts")
    if remaining:
        print("remaining at shell root:", remaining)


if __name__ == "__main__":
    main()
