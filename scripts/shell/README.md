# scripts/shell/

SLURM submit, run, check, retry, and maintenance helpers. Run from the **repository root** unless a script says otherwise.

## Layout

```text
shell/
├── submit/       # sbatch wrappers (primary entry points)
├── run/          # Direct bash drivers (often called from submit/*.sh)
├── check/        # Progress, verification, ds tests
├── retry/        # Failed-job reruns and queue cleanup
└── maintenance/  # Shell-only maintenance helpers
```

## Common commands

| Task | Command |
|------|---------|
| Main optimization array | `sbatch scripts/shell/run/optim_inject_pace.sh` |
| Step-4 paired posterior optimization | `sbatch scripts/shell/submit/submit_step4_paired_all.sh` |
| Step-3/4 paired posterior smoke tests | `bash scripts/shell/submit/submit_step3_paired_smoketest.sh` / `bash scripts/shell/submit/submit_step4_paired_smoketest.sh` |
| Bootstrap ECDF pipeline | `sbatch scripts/shell/submit/submit_bootstrap_cdf.sh` |
| Posterior summary (all steps) | `sbatch scripts/shell/submit/submit_posterior_summary_all_steps_shared.sh` |
| Full-campaign video forward export | `sbatch scripts/shell/submit/submit_full_campaign_video_forwards.sh` |
| Full-campaign video rendering | `sbatch scripts/shell/submit/submit_full_campaign_fracture_video.sh` |
| Threshold sensitivity | `sbatch --array=1-5 scripts/shell/submit/submit_threshold_sensitivity.sh` |
| Organize flat SLURM logs | `python3 scripts/python_tools/maintenance/organize_logs.py` |

Full index: [docs/reference/SCRIPTS_INDEX.md](../../docs/reference/SCRIPTS_INDEX.md)

## Notes

- `#SBATCH --output` paths are relative to the directory you were in when you ran `sbatch` — usually the repo root.
- Historical 7-case reruns use `scripts/shell/run/optim_inject_pace_7cases_fix.sh` → `src/archive/optim_inject_7cases_fix.jl`.
- Python layout helpers live in `scripts/python_tools/maintenance/`; `scripts/shell/maintenance/` is reserved for shell scripts.
