# Historical shell cleanup plan

This is an earlier inventory, not authorization for further deletion. Its
placeholder date was `2025-01-XX`, and its recorded count changed from 29 to
22 shell scripts. Those counts are not the current repository inventory.

The seven scripts recorded as removed were `submit_11_cases_samples_2_64.sh`,
`rerun_7_missing_cvar_samples.sh`, `rerun_two_cases.sh`, `rerun_2_failed_cases.sh`,
`rerun_5_completed_no_final.sh`, `rerun_missing_cvar_samples.sh`, and
`retry_failed_submissions.sh`. The reasons given were replacement by smart/fix
variants or completion of one-time recovery tasks.

The plan retained the PACE/Cruyff drivers, smart PoF/CVaR submitters, seven-case
checks, log checks, scaling helpers, and scratch-file management. It also kept
`retry_failed_job.sh`, `submit_all.sh`, and
`rerun_7_missing_cvar_samples_fix.sh` as potentially reusable tools.

The gamma-table generator, threshold submitter, and threshold plot runner that
this old plan retained were subsequently retired with explicit approval in
[the 2026-10-03 cleanup](../reference/DELETION_REVIEW_2026-10-03.md).
Current entry points are listed in [SCRIPTS_INDEX.md](../reference/SCRIPTS_INDEX.md).
